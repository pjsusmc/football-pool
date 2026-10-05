import * as admin from "firebase-admin";

interface GameDoc {
  isLastGameOfWeek: boolean;
  status: string;
  homeScore: number | null;
  awayScore: number | null;
  winner: "home" | "away" | null;
}

interface PickDoc {
  selections?: Record<string, "home" | "away">;
  tiebreakerGuess?: number | null;
}

/**
 * Scores a week once the final game (the tiebreaker game) is final.
 * One point per correct pick. The most correct picks wins the week; if two or
 * more players tie, the closest guess at the last game's combined score wins.
 * Members who didn't submit picks are ranked last with 0.
 */
export async function scoreWeek(poolId: string, weekId: string): Promise<boolean> {
  const db = admin.firestore();
  const poolRef = db.collection("pools").doc(poolId);
  const weekRef = poolRef.collection("weeks").doc(weekId);

  const gamesSnap = await weekRef.collection("games").get();
  const games = new Map<string, GameDoc>();
  let lastGame: GameDoc | null = null;
  gamesSnap.forEach((d) => {
    const g = d.data() as GameDoc;
    games.set(d.id, g);
    if (g.isLastGameOfWeek) lastGame = g;
  });

  const lg = lastGame as GameDoc | null;
  if (!lg || lg.status !== "final" || lg.homeScore == null || lg.awayScore == null) return false;
  const actualTotal = lg.homeScore + lg.awayScore;

  const members: string[] = (await poolRef.get()).data()?.memberUids ?? [];
  const picksSnap = await weekRef.collection("picks").get();
  const picks = new Map<string, PickDoc>();
  picksSnap.forEach((d) => picks.set(d.id, d.data() as PickDoc));

  const rows = members.map((uid) => {
    const pick = picks.get(uid);
    let correctCount = 0;
    for (const [gameId, side] of Object.entries(pick?.selections ?? {})) {
      const g = games.get(gameId);
      if (g?.winner && g.winner === side) correctCount += 1;
    }
    const guess = pick?.tiebreakerGuess;
    const tiebreakerDiff = guess != null ? Math.abs(guess - actualTotal) : null;
    return { uid, submitted: !!pick, correctCount, tiebreakerDiff };
  });

  // Most correct first; ties broken by closest tiebreaker guess (no guess = last).
  rows.sort((a, b) => {
    if (b.correctCount !== a.correctCount) return b.correctCount - a.correctCount;
    const da = a.tiebreakerDiff ?? Number.POSITIVE_INFINITY;
    const dbb = b.tiebreakerDiff ?? Number.POSITIVE_INFINITY;
    return da - dbb;
  });

  const anySubmitted = rows.some((r) => r.submitted);
  const batch = db.batch();
  rows.forEach((r, i) => {
    batch.set(weekRef.collection("results").doc(r.uid), {
      correctCount: r.correctCount,
      tiebreakerDiff: r.tiebreakerDiff,
      rank: i + 1,
      isWeekWinner: anySubmitted && i === 0,
    });
  });
  batch.set(weekRef, { status: "scored" }, { merge: true });
  await batch.commit();
  return true;
}
