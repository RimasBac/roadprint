# ADR 0008: Backup and restore on Android (no iCloud)

- Date: 2026-11-26
- Status: **Proposed.** No work before the iOS App Store launch (board, 2026-11-26). Option B (Drive sync) is a later decision.
- Owner: CTO. Plan §6. ADR 0005 (iCloud sync), ADR 0007 (Android app). AGENTS.md §7.2, §7.3, §8.

## Context

On iPhone, CloudKit does two jobs (ADR 0005): **sync** between the user's Apple devices, and **backup**, so a new phone restores everything with no login. There's no server, and we can't read the data.

Android has no CloudKit. What a driver actually needs, in order:

1. **New or reset phone → trips come back.** This is plan §15's "a trip restores correctly on a new phone".
2. **Moving between iPhone and Android** keeps every trip.
3. Two phones at once (live sync). Rare for a driver: one phone records a trip (ADR 0005 §5).

Constraints: no RoadPrint server and no accounts in v1 (plan §6, AGENTS.md §7b), privacy as a feature (AGENTS.md §8), and no new network use without board approval.

## Options

| Option | What it is | Needs 1 | Needs 2 | Needs 3 | Cost / privacy |
|---|---|---|---|---|---|
| **A. Android Auto Backup + export/import** | The OS copies the app's database to the user's Google Drive backup about once a day (idle, charging, Wi-Fi) and restores it on setup or reinstall. **Limit: 25 MB per app.** On Android 9+ with a screen lock, the backup is encrypted on the device with a key derived from the lock screen PIN, pattern or password, so Google can't read it | Yes (as fresh as the last daily backup) | Through the export file | No | Free. No sign-in, no code that talks to Google. Data goes to the user's own Google account, like iCloud |
| B. Google Drive `appDataFolder` sync | The app signs in with Google and writes one JSON file per trip to a hidden app folder in the user's Drive. Merge with the core's existing `updatedAt` / dedupe rules (`TripImporter`, `TripDeduplicator`) | Yes (immediately) | Through the export file | Yes | Free to us. Needs Google sign-in, an OAuth consent screen and possibly verification, and a sync engine of our own (there is no NSPersistentCloudKitContainer). Drive isn't end-to-end encrypted unless we encrypt it ourselves |
| C. Own server (Supabase, Firebase) | Accounts plus a cloud database | Yes | **Yes, automatic** | Yes | Monthly cost, GDPR controller duties, account deletion rules. Plan §6 says this is "v2 or later". It's also the base for social, share links and cross-platform Pro |
| D. Export/import only | Manual file | Only if the user remembered | Yes | No | Free, but most users never export |

## Decision

1. **Android v1 uses option A: Auto Backup, plus the existing export/import as the cross-platform path.**
   - `android:allowBackup="true"`, with explicit `dataExtractionRules` (Android 12+) and `fullBackupContent` (older). Include only: the Room database (or, safer, a backup archive, see point 2) and the settings store. **Exclude** the terrain tile cache (ADR 0006, rebuilt on demand), the derived heat index (plan §5.4: it's rebuilt and never synced), and temporary files.
   - Allow **device-to-device transfer** (cable or Wi-Fi when setting up a new phone). It has no 25 MB limit and is the best path for a new phone.
   - After a restore, the app runs the same dedupe pass as iOS (ADR 0005 §5) and rebuilds the heat index.
2. **Back up a compact `TripArchive`, not the raw database.** When the app goes to the background after a trip changes, write `backup/trips.rparchive`: the ROA-75 export archive, compressed. This is the same safety net iOS writes for iCloud sign-out (ADR 0005 §7). Back up that file plus settings, and restore by importing it with `TripImporter`. Reasons:
   - It stays far under 25 MB. Processed trips are simplified routes without raw points ("a few MB a year"), so a heavy driver has years of headroom. If the archive grows past **20 MB**, the app tells the driver to export a copy and keeps backing up the newest trips that fit (see open question).
   - The format is the cross-platform contract, tested for older versions, so a restore never depends on a Room schema migration.
   - The same file is what "Move to iPhone / Move to Android" uses (point 3).
3. **Moving between platforms:** a guided flow in Settings ("Moving to a new phone?"). It explains: "Same platform: it's automatic. iPhone ↔ Android: export here, import there." Export shares the archive through the system sheet (Drive, Files, email, AirDrop, Quick Share). Import accepts the file from either platform. Pro doesn't move (PLAY_STORE.md §6.7).
4. **Settings and banners:** Android has no A8/A9 iCloud banners. The `SyncService` implementation on Android is `BackupOnlySyncService`. Its status is `off` for live sync, and it adds one line in Settings: "Backed up with your Google account backup (Android settings). Last backup: …". The OS doesn't report the time, so we show the time the archive was last written and link to the system backup settings. The core's `SyncStatus` may gain a `systemBackup` case. That's additive.
5. **Option B (Drive sync) is a later, separate decision.** It's only worth doing if beta drivers really use two Android phones, or lose trips between daily backups. Option C stays the plan §6 trigger: cross-platform sync, Pro on both stores, social.
6. **Privacy policy:** "On Android, your trips are stored on your phone. If Android backup is on, your phone includes them in its backup to your Google account, which RoadPrint can't read." Check the Data safety wording for OS backup (PLAY_STORE.md §5).

## Consequences

- No new SDK, no sign-in, no server. Matches iOS's "no login screen".
- Restore can be up to a day out of date (the last backup), and up to the user's backup settings: backup can be off, or the phone has no screen lock, in which case the backup isn't end-to-end encrypted. Onboarding or Settings should say "Turn on Google backup to keep your trips on a new phone" and link to it.
- **Tests before launch** (Android version of plan §6): uninstall and reinstall · new phone through setup restore · device-to-device transfer · backup off · `adb shell bmgr backupnow` / `bmgr restore` in CI · export on iPhone → import on Android and back, checking the trips field by field against the golden fixtures.

## Risks

- **Auto Backup is a black box.** Its schedule and quota aren't under our control, and OEM backup apps (Samsung Cloud and others) behave differently. Mitigations: the export flow, and a "last exported" reminder after N trips.
- **25 MB cap.** If the backup data is over 25 MB, Android doesn't back up that app at all. Mitigation: the 20 MB archive limit in point 2, measured in CI with a 10-year synthetic fixture (`Tools/fixtures`).
- **Users expect live sync** because the iPhone version has it. Mitigation: the Settings wording in point 4. The store listing doesn't promise sync on Android.
