# Football Pool (Flutter + Firebase, free Spark plan)

Weekly straight-up pick 'em. 1 point per correct pick. Picks lock at **noon Eastern the day
before the week's first game**. The last game of the week is the tiebreaker: players guess the
combined score, and if people tie on correct picks, the closest guess wins.

Firebase project ID: `football-pool-7a153`. No Cloud Functions, so no Blaze plan needed.

## How it works

- **App (Flutter):** sign in, create/join pools, make picks, view results.
- **Firestore rules:** enforce the pick lock server-side (`request.time < lockAt`) and keep other
  players' picks hidden until the week locks. Joining a pool is a rule-checked write: a user can
  only add their own uid to the member list.
- **Sync worker (`worker/`):** a small Node script run by GitHub Actions every ~15 minutes using a
  Firebase service account. It builds the season for new pools, locks weeks, pulls live scores from
  ESPN's public scoreboard, and scores each week (including the tiebreaker) when the last game ends.

## One-time setup

### 1. Firebase (console: project football-pool-7a153)
- Authentication -> Sign-in method -> enable **Email/Password**
- Firestore Database -> Create database (production mode)

### 2. Deploy the rules (PowerShell, from this folder)
```powershell
flutter pub get
firebase deploy --only firestore
```

### 3. Service account key for the worker
1. Firebase console -> gear icon -> **Project settings** -> **Service accounts**
2. **Generate new private key** and save the JSON file **outside this project folder**.
   This key has full admin access to your project. Never commit it or share it.

### 4. GitHub
1. Create a new GitHub repository and push this project to it.
   - A **public** repo gets unlimited free Actions minutes (it's safe: the key is stored as a
     secret, not in the code).
   - A **private** repo gets 2,000 free minutes/month. A run every 15 minutes uses more than that,
     so change `*/15` to `0 * * * *` (hourly) in `.github/workflows/sync.yml`, or keep it public.
2. Repo -> Settings -> Secrets and variables -> Actions -> **New repository secret**
   - Name: `FIREBASE_SERVICE_ACCOUNT`
   - Value: paste the **entire contents** of the JSON key file.
3. Repo -> **Actions** tab -> enable workflows if prompted -> open **Pool sync** -> **Run workflow**
   to trigger the first run by hand. It should finish green.
4. Delete the downloaded key file from your computer once the secret is saved (or store it somewhere
   safe).

### 5. Run the app
```powershell
flutter run
```
Sign up, create a pool, and wait for the next sync (use **Run workflow** to speed it up). The weeks
then appear in the pool.

## Things to know

- **Delays:** GitHub's scheduled runs can start several minutes late, so scores and the "locked"
  label can lag a bit. The pick lock itself is exact: it's enforced by the rules against `lockAt`.
- **60-day rule:** GitHub pauses scheduled workflows in repos with no activity for 60 days. The
  season is shorter than that, but if syncing ever stops, re-enable it in the Actions tab.
- **Failures:** if a run fails, GitHub emails you. Logs are in the Actions tab.
- **ESPN endpoint:** unofficial. If it changes, only `worker/src/espn.ts` needs updating.
- **Ties:** a tied NFL game gives no point to either side. Players with no picks score 0.
- **Time zone:** Eastern. Change `POOL_TZ` in `worker/src/espn.ts` for another zone.
- **Upgrading later:** if you ever move to Blaze, this worker can be swapped for scheduled Cloud
  Functions without changing the app much.
