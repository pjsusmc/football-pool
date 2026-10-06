import * as admin from "firebase-admin";
import { EspnEvent, SLOTS, Slot, fetchWeekEvents, slotFor, upsertWeek, weekDocId } from "./espn";
import { scoreWeek } from "./scoring";

/**
 * Sync worker, run on a schedule by GitHub Actions (see .github/workflows/sync.yml).
 * It uses a Firebase service account, so it bypasses the Firestore security rules.
 *
 * Each run, for every pool:
 *  1. builds the season's weeks if the pool has none yet
 *  2. marks open weeks as locked once their lockAt has passed
 *  3. refreshes games/scores for weeks in progress, and refreshes upcoming weeks hourly
 *     (to catch flex scheduling)
 *  4. scores a week once its last game is final
 *  5. adds each playoff round once ESPN publishes its matchups (after the previous round starts)
 */
const HOUR = 3600 * 1000;

async function main(): Promise<void> {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT is not set.");
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(raw)) });
  const db = admin.firestore();

  const now = new Date();
  let failures = 0;

  const cache = new Map<string, EspnEvent[]>();
  const events = async (season: number, slot: Slot) => {
    const key = `${season}-${slot.number}`;
    if (!cache.has(key)) cache.set(key, await fetchWeekEvents(season, slot));
    return cache.get(key)!;
  };

  const pools = await db.collection("pools").get();
  console.log(`Processing ${pools.size} pool(s)`);

  for (const pool of pools.docs) {
    const season = pool.data().season as number;
    try {
      let weeks = await pool.ref.collection("weeks").get();

      if (weeks.empty) {
        console.log(`Pool ${pool.id}: building ${season} season`);
        for (const slot of SLOTS) {
          // Playoff slots usually have no matchups yet and are simply skipped here.
          await upsertWeek(pool.id, season, slot, await events(season, slot));
        }
        weeks = await pool.ref.collection("weeks").get();
      }

      for (const w of weeks.docs) {
        const d = w.data();
        if (d.status === "scored") continue;

        try {
          const slot = slotFor(d.weekNumber);
          if (!slot) continue;
          const lockAt = (d.lockAt as admin.firestore.Timestamp).toDate();
          const firstKickoff = (d.firstKickoffAt as admin.firestore.Timestamp).toDate();
          const lastSynced = (d.lastSyncedAt as admin.firestore.Timestamp | undefined)?.toDate();

          if (d.status === "open" && lockAt <= now) {
            await w.ref.update({ status: "locked" });
            console.log(`Pool ${pool.id} ${w.id}: locked`);
          }

          const started = firstKickoff <= now;
          const soon = firstKickoff.getTime() - now.getTime() < 7 * 24 * HOUR;
          const stale = !lastSynced || now.getTime() - lastSynced.getTime() > 55 * 60 * 1000;

          if (started || (soon && stale)) {
            await upsertWeek(pool.id, season, slot, await events(season, slot));
            if (started && (await scoreWeek(pool.id, w.id))) {
              console.log(`Pool ${pool.id} ${w.id}: scored`);
            }
          }
        } catch (err) {
          failures++;
          console.error(`Pool ${pool.id} ${w.id} failed:`, err);
        }
      }

      // Playoffs: create each round once the previous round (or week 18) has kicked off.
      // ESPN only lists real matchups after the earlier round sets them; until then this is a no-op.
      const byNumber = new Map<number, admin.firestore.DocumentData>();
      weeks.docs.forEach((w) => byNumber.set(w.data().weekNumber as number, w.data()));
      for (const slot of SLOTS.filter((s) => s.seasonType === 3)) {
        if (byNumber.has(slot.number)) continue;
        const prev = byNumber.get(slot.number - 1);
        const prevStart = (prev?.firstKickoffAt as admin.firestore.Timestamp | undefined)?.toDate();
        if (!prevStart || prevStart > now) break; // earlier round hasn't started; later ones can't exist yet
        try {
          await upsertWeek(pool.id, season, slot, await events(season, slot));
          const created = await pool.ref.collection("weeks").doc(weekDocId(season, slot.number)).get();
          if (created.exists) {
            byNumber.set(slot.number, created.data()!);
            console.log(`Pool ${pool.id}: added ${slot.label}`);
          } else {
            break; // matchups not published yet
          }
        } catch (err) {
          failures++;
          console.error(`Pool ${pool.id} playoff ${slot.label} failed:`, err);
          break;
        }
      }
    } catch (err) {
      failures++;
      console.error(`Pool ${pool.id} failed:`, err);
    }
  }

  // A non-zero exit makes GitHub email you that the run failed.
  if (failures > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});