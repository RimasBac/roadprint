# ADR 0005: iCloud sync with SwiftData + CloudKit

Accepted 2026-11-16 (ROA-78, epic ROA-22). Plan §4.2, §6, §8. AGENTS.md §7.2, §7b.

**Status of the code:** the store is CloudKit-ready and its fields are marked for encryption, but sync
is **off** (`cloudKitDatabase: .none`) and the app has no iCloud entitlement. Turning it on is one
small app PR (§9) after the board has done the Apple Developer steps (§10).

## 1. Decision

- SwiftData mirrors the one local store to the user's **CloudKit private database** in the container
  `iCloud.com.rimasbac.roadprint`:
  `ModelConfiguration(schema:, cloudKitDatabase: .private("iCloud.com.rimasbac.roadprint"))`.
- No server and no public or shared database. We (the developer) can't read a private database.
  It is stored under the user's Apple ID and counts against their iCloud storage.
- The phone stays the main copy. Sync is a mirror. Every screen works with sync off, signed out or
  out of storage.
- Feature code sees only the core `SyncService` and `TripStore` protocols. Only `App/Storage/`
  imports SwiftData or CloudKit.
- `cloudKitDatabase` is always passed explicitly. The SwiftData default, `.automatic`, turns on
  CloudKit by itself as soon as the app has an iCloud entitlement.

## 2. CloudKit rules for `TripRecord`

NSPersistentCloudKitContainer, which SwiftData uses for sync, refuses a model that breaks these rules.
`App/Storage/TripRecord.swift` follows them today:

| Rule | `TripRecord` |
|---|---|
| No `@Attribute(.unique)` (CloudKit can't enforce uniqueness) | None. Duplicate `id`s are handled in §5 |
| Every attribute optional or with a default | Yes, every property has a default or is `Optional` |
| Relationships optional, with inverses, no `.deny` delete rule | No relationships. Points, route and parts are encoded blobs |
| No ordered relationships | None |

Once the schema is deployed to **Production**, CloudKit doesn't let us delete, rename or retype a
field, or change whether it's encrypted. So from now on:

- **Changes are additive only:** new optional or defaulted properties. A property we no longer
  need stays in the model, unused.
- Each blob carries its own versioned Codable payload (`Trip.schemaVersion`, plan §7 export
  contract), so a changed shape inside a blob needs no schema change.
- Every shipped shape of `TripRecord` is frozen as a test fixture (`TripSchemaV1` in
  `RoadPrintTests/TripStoreMigrationTests.swift`). The migration test opens that store with the
  current model.

## 3. Encrypted fields

`@Attribute(.allowsCloudEncryption)` makes the CloudKit mirror write the field to the record's
`encryptedValues` and not its plain fields. It has no effect while sync is off. Because it can't be
changed after the Production deploy, we encrypt everything that says **where or when** someone drove:

| Field | Holds | Encrypted |
|---|---|---|
| `pointsData` | raw GPS points while recording (no speed) | yes, also external storage |
| `routeData` | `ProcessedRoute`: geometry, start/end areas, summit | yes, also external storage |
| `placesData` | countries and regions | yes |
| `mainRoadData` | main road (e.g. E85) | yes |
| `summaryData` | distance, times, gap count | yes |
| `createdAt`, `updatedAt`, `endedAt`, `storedStartedAt` | when the trip happened | yes |
| `id` | random UUID | no |
| `schemaVersion`, `statusRaw`, `visibilityRaw` | small enums | no |

Large `externalStorage` blobs may travel as CKAssets, not as fields. Apple treats CloudKit
"encrypted fields **and assets**" the same way (see §4).

## 4. Is it end-to-end encrypted? Only with Advanced Data Protection

What Apple says:

- [iCloud data security overview](https://support.apple.com/en-us/102651): "Third-party app data
  stored in iCloud is always encrypted in transit and on server." And: "When you turn on Advanced
  Data Protection, third-party app data stored in iCloud Backup and CloudKit encrypted fields and
  assets are end-to-end encrypted."
- [Apple Platform Security: Advanced Data Protection for iCloud](https://support.apple.com/guide/security/advanced-data-protection-for-icloud-sec973254c5f/web):
  ADP "automatically protects CloudKit fields that third-party developers choose to mark as
  encrypted". "CloudKit Record fields need to be explicitly declared as encrypted in the
  container's schema to be protected." With standard data protection, "the encryption keys are
  stored by Apple".

So:

| User's iCloud setting | Our encrypted fields | Who could decrypt |
|---|---|---|
| Standard Data Protection (the default) | encrypted in transit and on Apple's servers | the user's devices, and Apple (it holds the keys) |
| Advanced Data Protection on | **end-to-end encrypted** | only the user's trusted devices |
| Either | — | **never us**: a private database has no developer access, and we run no server |

This corrects plan §6 ("which Apple describes as end-to-end encrypted"). That is true only with ADP.

**What the privacy policy may say:**
- "Your trips are stored on your iPhone and in your own iCloud account. RoadPrint has no server and
  can't see your trips or your location."
- "Routes, places and trip times are stored in iCloud as encrypted fields. If you turn on Advanced
  Data Protection for iCloud, they are end-to-end encrypted, and only your devices can read them."
- **Not allowed:** "end-to-end encrypted" without the ADP condition, or "not even Apple can read
  them" without the ADP condition.

## 5. Conflicts and duplicates

- **Rule: the newest `updatedAt` wins, for the whole trip.** This is the same rule as import
  (`TripImporter`, ROA-76). The mirror resolves conflicts per record: the last write to reach the
  server wins. A trip is written as a whole, and `updatedAt` goes up on every write (`TripRecorder`),
  so the outcome matches the rule except when two devices edit the same trip offline at the same time.
  That is rare here, because only one phone records a trip.
- **Duplicates.** With no unique constraint, two devices can each hold a record with the same `id`.
  For example, the same archive is imported on two phones, or a phone is restored before the first
  sync finishes. The enable-sync PR adds a dedupe pass. It runs after each remote-change import
  (`NSPersistentStoreRemoteChange`) and at launch. It groups records by `id`, keeps the one with the
  newest `updatedAt` (ties: keep the one with more data: route, then points), and deletes the rest.
  The choice is a pure function in core, shared with `TripImporter`'s dedupe.
- **Deletes** sync as record deletions (A4 "also removed from iCloud").

## 6. Migrating the existing local store

- Installed builds (up to TestFlight 16) use the default store file (`default.store` in Application
  Support), with sync off. `makeContainer()` keeps that location, and the enable-sync PR must too.
  It changes only `cloudKitDatabase`. A new file location would mean an empty store.
- The ADR 0005 model change only adds `allowsCloudEncryption` to existing attributes. SwiftData
  applies an automatic lightweight migration if one is needed. `TripStoreMigrationTests` writes a
  V1 store to disk and checks two things: it opens with the current model with every trip equal
  field by field, the active trip is still found, and the migrated store can be written to and
  reopened.
- When sync is first turned on, the mirror exports the records that already exist in the store.
  SwiftData has persistent history on. The device restore tests (plan §6: second iPhone, reinstall)
  must confirm that trips recorded before sync appear on the second phone.
- No `SchemaMigrationPlan` yet. Two versioned schemas with the same checksum make SwiftData stop
  with "duplicate version checksums", and additive changes don't need a plan. If we ever need a
  custom migration stage, we add `VersionedSchema`s then, starting from the frozen V1.

## 7. iCloud off, signed out, full

| Case | `SyncStatus` | What the user sees | Data |
|---|---|---|---|
| Sync on, working | `available` | nothing | phone + iCloud |
| User turned sync off (A7) | `off` | toggle off in Settings | stays on the phone, iCloud copy untouched |
| Not signed in, or iCloud off for the app | `noAccount` | banner **A8** on You and Settings, "Open Settings" | stays on the phone. Uploads when the user signs in |
| iCloud storage full | `quotaFull` | banner **A9** "Your trips are safe on this phone." | stays on the phone. Retries by itself |
| Other sync error | `error` | no banner. Logged without the trip data | stays on the phone. Retries by itself |

`SyncStatus.banner` in core maps these to A8/A9. The CloudKit implementation reads
`CKContainer.accountStatus()`, `.CKAccountChanged` and
`NSPersistentCloudKitContainer.eventChangedNotification` (`CKError.quotaExceeded` → `quotaFull`,
`.notAuthenticated` → `noAccount`).

**Turning sync on or off** rebuilds the `ModelContainer` with the other `cloudKitDatabase` value on
the **same store file**. A live container can't switch. The store is flushed first, and the
`TripStore` actor is swapped.

**Account sign-out (verify on device).** When the iCloud account changes, the mirror may clear the
records it mirrored from the old account out of the local store. Those trips are in iCloud and come
back when the user signs in again. As a safety net against losing trips that hadn't uploaded yet,
the enable-sync PR writes a local `TripArchive` (ROA-75 format) to Application Support each time the
app goes to the background while sync is on. That is a few MB a year. The sign-out restore test
must check this case.

## 8. CloudKit environments

- Debug builds from Xcode use the **Development** environment. **TestFlight and App Store builds
  use Production.**
- So the schema must be **deployed to Production** in the CloudKit Console before a TestFlight build
  with sync on is handed out. Without it, records fail with schema errors and every tester sits in
  `error`.
- The schema appears in Development once a Debug build runs with sync on, on a simulator or device
  signed in to iCloud (or by calling `initializeCloudKitSchema` once). After that the board deploys it.
- Without a Mac (ROA-113): `Tools/cloudkit/roadprint.ckdb` is the schema Core Data mirroring creates
  for `TripRecord`, kept in step by `Tools/cloudkit/check_schema.py` (in `check.sh`). The
  `cloudkit-schema` workflow (`mode=import`) imports it into Development with `cktool` and a CloudKit
  management token (secret `CLOUDKIT_MANAGEMENT_TOKEN`), then exports and re-checks it. A model
  change updates the `.ckdb` in the same PR, and the board deploys again.
- Deploying is permanent for the fields it creates (§2), so §3's encryption choices must be final
  before that point. They are, in this ADR.

## 9. The enable-sync PR (next, app only)

1. `App/RoadPrint.entitlements` (new, referenced from `project.yml`):

   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array><string>iCloud.com.rimasbac.roadprint</string></array>
   <key>com.apple.developer.icloud-services</key>
   <array><string>CloudKit</string></array>
   <key>aps-environment</key>
   <string>development</string>
   ```

   Xcode re-signs `aps-environment` as `production` for App Store and TestFlight distribution.
2. `project.yml`, target `RoadPrint`:

   ```yaml
   entitlements:
     path: App/RoadPrint.entitlements
   info:
     properties:
       UIBackgroundModes: [location, remote-notification]
   ```

   (`remote-notification` is for CloudKit's silent pushes. `location` stays.)
3. `SwiftDataTripStore.makeContainer(sync:)` → `.private("iCloud.com.rimasbac.roadprint")` when
   on. A `CloudKitSyncService` replaces `LocalOnlySyncService` in `AppEnvironment.live()`. Sync
   defaults to **on** (plan §6), saved in `AppSettings`.
4. Dedupe pass (§5), background archive (§7), A8/A9 banners, A7 toggle and alert.
5. fastlane: run `match(type: "appstore", readonly: false)` once to regenerate the profile with the
   iCloud and Push capabilities. Note the new App ID capabilities in `docs/BUILD_PIPELINE.md`.
6. No privacy key is needed in `Info.plist`. CloudKit needs no usage description.

## 10. Board steps (Apple Developer, before §9 merges)

1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → `+` → **iCloud
   Containers** → identifier `iCloud.com.rimasbac.roadprint`, description "RoadPrint".
2. **Identifiers** → App ID `com.rimasbac.roadprint` → enable **iCloud** (choose "Include CloudKit
   support") → **Configure** → tick `iCloud.com.rimasbac.roadprint` → Save.
3. Same App ID → enable **Push Notifications** → Save. No push certificate is needed. CloudKit
   pushes need only the capability.
4. Confirm that the existing App Store provisioning profile now shows "Invalid". The CTO
   regenerates it with match (§9.5), so there's nothing to download.
5. After the first Debug run with sync on, or the `cloudkit-schema` import (§8): icloud.developer.apple.com → CloudKit Console →
   `iCloud.com.rimasbac.roadprint` → **Schema** → check that record type `CD_TripRecord` lists the
   encrypted fields from §3 → **Deploy Schema Changes…** → Production → Deploy.
6. Tell the CTO on the board issue. Only then does a TestFlight build with sync on go out.
