import * as admin from "firebase-admin";
import { EspnEvent, fetchWeekEvents, upsertWeek } from "./espn";
import { scoreWeek } from "./scoring";

/**
 * Sync worker, run on a schedule by GitHub Actions (see .github/workflows/sync.yml).
 * It uses a Firebase service account, so it bypasses the Firestore security rules.
 *
 * Each run, for every pool:
 *  1. builds the whole season if the pool has no weeks yet
 *  2. marks open weeks as locked once their lockAt has passed
 *  3. refreshes games/scores for weeks in progress, and refreshes upcoming weeks hourly
 *     (to catch flex scheduling)
 *  4. scores a week once its last game is final
 */
const REGULAR_SEASON_WEEKS = 18;
const HOUR = 3600 * 1000;

async function main(): Promise<void> {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT is not set.");
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(raw)) });
  const db = admin.firestore();

  const now = new Date();
  let failures = 0;

  const cache = new Map<string, EspnEvent[]>();
  const events = async (season: number, week: number) => {
    const key = `${season}-${week}`;
    if (!cache.has(key)) cache.set(key, await fetchWeekEvents(season, week));
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
        for (let w = 1; w <= REGULAR_SEASON_WEEKS; w++) {
          await upsertWeek(pool.id, season, w, await events(season, w));
        }
        weeks = await pool.ref.collection("weeks").get();
      }

      for (const w of weeks.docs) {
        const d = w.data();
        if (d.status === "scored") continue;

        try {
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
            await upsertWeek(pool.id, season, d.weekNumber, await events(season, d.weekNumber));
            if (started && (await scoreWeek(pool.id, w.id))) {
              console.log(`Pool ${pool.id} ${w.id}: scored`);
            }
          }
        } catch (err) {
          failures++;
          console.error(`Pool ${pool.id} ${w.id} failed:`, err);
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
