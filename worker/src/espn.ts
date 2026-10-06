import * as admin from "firebase-admin";

/**
 * ESPN's public scoreboard endpoint: unofficial and undocumented, but free and
 * keyless. If it ever breaks, this file is the only place that needs swapping
 * (e.g. for SportsDataIO) as long as fetchWeekEvents keeps returning EspnEvent[].
 */
const SCOREBOARD = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard";
const POOL_TZ = "America/New_York";

export interface EspnEvent {
  id: string;
  date: string;
  status: { type: { state: "pre" | "in" | "post" } };
  competitions: Array<{
    competitors: Array<{
      homeAway: "home" | "away";
      team: { displayName: string };
      score?: string;
      winner?: boolean;
    }>;
  }>;
}

export async function fetchWeekEvents(season: number, week: number): Promise<EspnEvent[]> {
  const url = `${SCOREBOARD}?seasontype=2&week=${week}&dates=${season}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ESPN fetch failed (${res.status}) for week ${week}`);
  const body = (await res.json()) as { events?: EspnEvent[] };
  return body.events ?? [];
}

function tzOffsetMinutes(date: Date, tz: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(date);
  const n = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  const asUtc = Date.UTC(n("year"), n("month") - 1, n("day"), n("hour"), n("minute"), n("second"));
  return (asUtc - Math.floor(date.getTime() / 1000) * 1000) / 60000;
}

/** Noon Eastern on the calendar day before the given kickoff (Eastern date). */
export function lockTimeFor(firstKickoff: Date): Date {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: POOL_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(firstKickoff);
  const n = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  // Date.UTC normalises day 0 / negative days into the previous month.
  const guess = new Date(Date.UTC(n("year"), n("month") - 1, n("day") - 1, 12, 0, 0));
  return new Date(guess.getTime() - tzOffsetMinutes(guess, POOL_TZ) * 60000);
}

export const weekDocId = (season: number, week: number) =>
  `${season}-W${String(week).padStart(2, "0")}`;

/**
 * Writes the week doc and its games for one pool. Never touches a scored week,
 * never moves lockAt once a week is no longer open, and never reopens one.
 */
export async function upsertWeek(
  poolId: string,
  season: number,
  week: number,
  events: EspnEvent[]
): Promise<void> {
  if (events.length === 0) return;
  const db = admin.firestore();
  // Don't recreate weeks under a pool that was deleted while the worker was running.
  if (!(await db.collection("pools").doc(poolId).get()).exists) return;
  const weekRef = db.collection("pools").doc(poolId).collection("weeks").doc(weekDocId(season, week));

  const existing = await weekRef.get();
  const existingStatus = existing.exists ? (existing.data()!.status as string) : null;
  if (existingStatus === "scored") return;

  const sorted = [...events].sort((a, b) => +new Date(a.date) - +new Date(b.date));
  const first = new Date(sorted[0].date);
  const last = sorted[sorted.length - 1];
  const lockAt = lockTimeFor(first);
  const now = new Date();

  let status = existingStatus ?? (now >= lockAt ? "locked" : "open");
  const lockUnchanged = existing.exists && existingStatus !== "open";

  await weekRef.set(
    {
      weekNumber: week,
      seasonYear: season,
      firstKickoffAt: admin.firestore.Timestamp.fromDate(first),
      tiebreakerGameId: last.id,
      lastSyncedAt: admin.firestore.Timestamp.now(),
      status,
      ...(lockUnchanged ? {} : { lockAt: admin.firestore.Timestamp.fromDate(lockAt) }),
    },
    { merge: true }
  );

  const batch = db.batch();
  for (const ev of sorted) {
    const comps = ev.competitions[0]?.competitors ?? [];
    const home = comps.find((c) => c.homeAway === "home");
    const away = comps.find((c) => c.homeAway === "away");
    if (!home || !away) continue;

    const state = ev.status.type.state;
    const gameStatus = state === "post" ? "final" : state === "in" ? "in_progress" : "scheduled";
    const started = gameStatus !== "scheduled";
    let winner: "home" | "away" | null = null;
    if (gameStatus === "final") winner = home.winner ? "home" : away.winner ? "away" : null;

    batch.set(
      weekRef.collection("games").doc(ev.id),
      {
        homeTeam: home.team.displayName,
        awayTeam: away.team.displayName,
        kickoffAt: admin.firestore.Timestamp.fromDate(new Date(ev.date)),
        isLastGameOfWeek: ev.id === last.id,
        status: gameStatus,
        homeScore: started ? Number(home.score ?? 0) : null,
        awayScore: started ? Number(away.score ?? 0) : null,
        winner,
      },
      { merge: true }
    );
  }
  await batch.commit();
}