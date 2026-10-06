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

/**
 * One pool "week" = one ESPN scoreboard slot. Regular season is weeks 1-18. Playoff rounds
 * continue the numbering (19-22) and use ESPN's postseason feed (seasontype=3), where
 * ESPN's week 4 is the Pro Bowl and is deliberately skipped.
 */
export interface Slot {
  number: number; // pool week number (used for ordering and the doc id)
  seasonType: 2 | 3; // 2 = regular season, 3 = postseason
  espnWeek: number; // ESPN's week parameter within that season type
  label: string | null; // display label for playoff rounds
}

export const REGULAR_SEASON_WEEKS = 18;

export const SLOTS: Slot[] = [
  ...Array.from({ length: REGULAR_SEASON_WEEKS }, (_, i): Slot => ({
    number: i + 1,
    seasonType: 2,
    espnWeek: i + 1,
    label: null,
  })),
  { number: 19, seasonType: 3, espnWeek: 1, label: "Wild Card" },
  { number: 20, seasonType: 3, espnWeek: 2, label: "Divisional Round" },
  { number: 21, seasonType: 3, espnWeek: 3, label: "Conference Championships" },
  { number: 22, seasonType: 3, espnWeek: 5, label: "Super Bowl" },
];

export const slotFor = (weekNumber: number): Slot | undefined =>
  SLOTS.find((s) => s.number === weekNumber);

export async function fetchWeekEvents(season: number, slot: Slot): Promise<EspnEvent[]> {
  const url = `${SCOREBOARD}?seasontype=${slot.seasonType}&week=${slot.espnWeek}&dates=${season}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ESPN fetch failed (${res.status}) for ${slot.label ?? "week " + slot.number}`);
  const body = (await res.json()) as { events?: EspnEvent[] };
  return body.events ?? [];
}

/** Playoff games can be listed before their teams are known; ignore those placeholders. */
function hasRealTeams(ev: EspnEvent): boolean {
  const comps = ev.competitions[0]?.competitors ?? [];
  const home = comps.find((c) => c.homeAway === "home");
  const away = comps.find((c) => c.homeAway === "away");
  const ok = (n?: string) => !!n && !/\b(tbd|tba)\b/i.test(n);
  return ok(home?.team?.displayName) && ok(away?.team?.displayName);
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
  slot: Slot,
  allEvents: EspnEvent[]
): Promise<void> {
  const events = allEvents.filter(hasRealTeams);
  if (events.length === 0) return;
  const db = admin.firestore();
  // Don't recreate weeks under a pool that was deleted while the worker was running.
  if (!(await db.collection("pools").doc(poolId).get()).exists) return;
  const weekRef = db
    .collection("pools")
    .doc(poolId)
    .collection("weeks")
    .doc(weekDocId(season, slot.number));

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
      weekNumber: slot.number,
      label: slot.label,
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
