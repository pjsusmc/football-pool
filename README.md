# Football Pool (Flutter + Firebase)

Weekly straight-up pick 'em. 1 point per correct pick. Picks lock at **noon Eastern the day
before the week's first game**. The last game of the week is the tiebreaker: players guess the
combined score, and if people tie on correct picks, the closest guess wins.

Firebase project ID: `football-pool`

## One-time setup (run on your own machine)

Prereqs: Flutter SDK, Node 20+, Firebase CLI (`npm i -g firebase-tools`).

```bash
# 1. Unzip, then generate the platform folders (android/ios/web) around the existing lib/
cd football_pool
flutter create . --project-name football_pool --org com.yourname

# 2. Sign in and link the app to your Firebase project
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project=football-pool     # creates lib/firebase_options.dart

# 3. Install packages
flutter pub get
(cd functions && npm install)

# 4. In the Firebase console (project: football-pool), turn on:
#    - Authentication -> Sign-in method -> Email/Password
#    - Firestore Database (production mode)
#    - Upgrade to the Blaze plan (required for Cloud Functions; a pool this size costs ~nothing)

# 5. Deploy rules + functions
firebase deploy --only firestore,functions

# 6. Run
flutter run
```

## How it works

- **Create a pool** in the app. That calls `initPoolSeason`, which pulls all 18 regular-season
  weeks from ESPN's public scoreboard and builds week + game docs with each week's `lockAt`.
- **Join a pool**: share the pool ID shown on the pool tile; friends tap Join.
- **`tick`** runs every 10 minutes: locks weeks past `lockAt`, refreshes live scores, and scores a
  week as soon as its last game is final (results appear on the standings screen).
- Picks are locked server-side by Firestore rules (`request.time < lockAt`), not just in the UI.
  Other players' picks stay hidden until the week locks.

## Notes / things to know

- ESPN's scoreboard endpoint is unofficial. If it ever changes, only `functions/src/espn.ts`
  needs updating (or swap in SportsDataIO).
- Ties (NFL tie games) award no point to either side.
- Players who don't submit picks for a week score 0 and rank last.
- The lock time is Eastern. Change `POOL_TZ` in `functions/src/espn.ts` to use another zone.
