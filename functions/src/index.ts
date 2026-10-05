import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import { EspnEvent, fetchWeekEvents, upsertWeek } from "./espn";
import { scoreWeek } from "./scoring";

admin.initializeApp();
setGlobalOptions({ region: "us-central1" });

const db = admin.firestore();
const REGULAR_SEASON_WEEKS = 18;

/** Called by the app right after a pool is created: builds the whole season. */
export const initPoolSeason = onCall({ timeoutSeconds: 300 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const poolId = String(req.data?.poolId ?? "");
  const snap = await db.collection("pools").doc(poolId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Pool not found.");
  const pool = snap.data()!;
  if (pool.commissionerUid !== req.auth.uid) {
    throw new HttpsError("permission-denied", "Only the commissioner can do this.");
  }
  for (let week = 1; week <= REGULAR_SEASON_WEEKS; week++) {
    const events = await fetchWeekEvents(pool.season, week);
    await upsertWeek(poolId, pool.season, week, events);
  }
  return { ok: true };
});

/** Joining goes through here because only the commissioner may edit the pool doc. */
export const joinPool = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const poolId = String(req.data?.poolId ?? "").trim();
  if (!poolId) throw new HttpsError("invalid-argument", "Pool ID required.");
  const ref = db.collection("pools").doc(poolId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "No pool with that ID.");
  await ref.update({ memberUids: admin.firestore.FieldValue.arrayUnion(req.auth.uid) });
  return { ok: true };
});

/**
 * Runs every 10 minutes:
 *  1. locks any open week whose lockAt (noon ET the day before the first game) has passed
 *  2. refreshes games/scores for weeks in progress (and schedules hourly, for flex changes)
 *  3. scores a week once its last game is final
 */
export const tick = onSchedule(
  { schedule: "every 10 minutes", timeZone: "America/New_York", timeoutSeconds: 300 },
  async () => {
    const now = new Date();
    const hourly = now.getMinutes() < 10;
    const cache = new Map<string, EspnEvent[]>();
    const events = async (season: number, week: number) => {
      const key = `${season}-${week}`;
      if (!cache.has(key)) cache.set(key, await fetchWeekEvents(season, week));
      return cache.get(key)!;
    };

    const pools = await db.collection("pools").get();
    for (const pool of pools.docs) {
      const season = pool.data().season as number;
      const weeks = await pool.ref.collection("weeks").where("status", "!=", "scored").get();

      for (const w of weeks.docs) {
        const d = w.data();
        const lockAt = (d.lockAt as admin.firestore.Timestamp).toDate();
        const firstKickoff = (d.firstKickoffAt as admin.firestore.Timestamp).toDate();

        if (d.status === "open" && lockAt <= now) {
          await w.ref.update({ status: "locked" });
        }

        const started = firstKickoff <= now;
        const soon = firstKickoff.getTime() - now.getTime() < 7 * 24 * 3600 * 1000;
        if (started || (hourly && soon)) {
          try {
            await upsertWeek(pool.id, season, d.weekNumber, await events(season, d.weekNumber));
            if (started) await scoreWeek(pool.id, w.id);
          } catch (err) {
            console.error(`Sync failed for pool ${pool.id} ${w.id}`, err);
          }
        }
      }
    }
  }
);
