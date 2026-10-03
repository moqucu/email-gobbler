# Menu bar app: implementation plan

This plan turns the `mail-to-numbers` workflow into a menu bar app that starts at
login and processes both use cases unattended. The [design document](macOS-menu-bar-app-plan.md)
covers goals, permissions, and safety rules. This document turns them into
reviewable steps against the current code. The milestones land on one dedicated PR
as test-first commits (failing tests, then implementation), and each keeps `swift test` green.

## Starting point

`MailToNumbers` already provides most of the engine:

- `MailNumbersCore`:
  - Mail listing (oldest first), fetching, and archiving.
  - MIME decoding.
  - Sheet snapshot, plan, format check, backup, write, and full read-back verification.
  - `processMessage`, which never consumes mail before a verified write.
- `SchoologyGrades` and `EtradeDividends`: email parsing and sheet planning.
- `mail-to-numbers`: a CLI that the app replaces for routine use and that remains a diagnostic tool.

Gaps the app must close:

| Gap | Why it matters unattended |
| --- | --- |
| A Schoology email covers several students, but a run updates one `--student`/`--sheet`. | With `--consume`, the first student's write archives the email before the other students' sheets are updated. |
| Options exist only as CLI flags. | The app needs persisted settings: workbooks, sheets, student-to-sheet routes, schedule, and backups. |
| Mail listing uses the unified Inbox. | A match in another account would stop the backlog at consume time. Listing should be limited to the iCloud account. |
| AppleScript runs synchronously through `NSAppleScript`. | Runs must not block the menu, must not overlap, and need a timeout. |
| Runs report through `print`. | The app needs structured run results for its menu and a log without grades or amounts. |
| Numbers is driven by opening documents. | It may show windows or take focus; this must be measured and contained. |

## Decisions (proposed defaults)

- **Distribution:** a personal, non-sandboxed app installed in `/Applications`.
  - Signed with the existing Apple Development identity and hardened runtime.
  - Entitlement: `com.apple.security.automation.apple-events`.
  - Info.plist: an `NSAppleEventsUsageDescription`.
  - Not sandboxed, because automating Mail and Numbers from a sandbox needs temporary exceptions.
  - No App Store, no notarization.
- **Project:** an XcodeGen spec (`App/project.yml`) for a `MailToNumbersApp` target.
  - It depends on the local `MailToNumbers` package.
  - The generated `.xcodeproj` is not committed.
  - The package and app require macOS 13 or later, for `MenuBarExtra`, `SMAppService`, and Swift concurrency clocks.
- **Settings:** a versioned `Codable` file in `~/Library/Application Support/MailToNumbers/`.
  - Paths, student labels, and sheet names stay out of the repository.
- **Backups:** kept in the same folder under `Backups/<use case>/`.
  - The newest 30 are kept per use case, and older ones are deleted only after a newer verified write.
  - The menu has a **Show Backups** item.
- **Schedule (confirmed):** a scan at launch, every 30 minutes, on wake, and on **Run Now**.
  - Triggers that arrive during a run collapse into one follow-up run.
- **Failure policy:** a failed message stops that use case's backlog for the run; other use cases still run.
  - The error shows in the menu, the message stays in the Inbox, and the next scheduled run retries it.
  - Reruns are safe: grades replace their week, and dividends skip identical rows.
- **Privacy:** logs record message ID, use case, stage, outcome, and duration, through `os.Logger`.
  - They never record grades, amounts, securities, or email content.
  - Notifications (confirmed) appear only on failures and contain no data. A daily or weekly
    summary may follow later.
- **Grades routing (confirmed):** one student is routed to a grades sheet. Other students in
  the email are ignored and noted. Student labels live only in local settings.
- **Sweep interest (confirmed):** bank sweep interest is recorded like any other payment.

## Milestones

### 1. Multi-target workflow (package)

- [x] Let one message produce several sheet updates: `UseCasePlan` gains a list of `(workbook, sheet, SheetUpdatePlan)` targets.
- [x] Extend `processMessage`:
  - Plan every target first.
  - Write and verify them one at a time.
  - Consume only after all targets are verified or have nothing to write.
  - If a later target fails, report which targets were already written; reruns are safe because they replace or skip.
- [x] Schoology routing from settings:
  - Each configured student label maps to a workbook and sheet.
  - Students without a route are ignored and noted.
  - A configured student missing from the email stops the run.
  - Two routes to the same sheet are rejected.
- [x] Return a structured `MessageReport` per message instead of printing; the CLI prints it. Per-run reports for the menu follow in milestone 2.
- [x] Tests (fakes, no automation):
  - Two students write two sheets, then consume.
  - The second sheet fails: no consume, and the report lists the first sheet as written.
  - An unrouted student is ignored.
  - Empty plans for all targets still consume.
  - Existing single-target behavior is unchanged.

### 2. Settings, run coordination, and scheduling (package, UI-free)

Implemented in the `MailToNumbersService` module: `AppSettings`, `SettingsStore`, `runUseCase`/`runAll` with a swappable `AutomationClient`, `RunCoordinator`, `runSchedule`, `pruneBackups`, and content-free run log events.


- [x] `AppSettings` (Codable, versioned):
  - Per use case: enabled, workbook path, sheet name, routes, and subject/sender overrides.
  - Schedule interval, backup folder, and retention count.
  - Validation errors name the field.
- [x] `SettingsStore`: atomic load and save in Application Support; a missing file means defaults.
- [x] `RunCoordinator` (actor):
  - At most one run.
  - Triggers during a run collapse into one follow-up.
  - Pause and resume.
  - Publishes state (idle, running with use case and step, paused, or last result and error) for the UI.
- [x] `Scheduler`: launch, interval, and wake triggers, with an injectable clock and wake source.
- [x] Backup retention with an injectable file system.
- [x] Mail listing limited to the iCloud account that archiving already requires.
- [x] Tests:
  - Coalescing, pause, and interval timing with a fake clock.
  - Settings round-trip and migration.
  - Retention never deletes the newest backup.
  - The iCloud account filter.

### 3. App shell (XcodeGen project)

- [ ] `App/project.yml`, `MailToNumbersApp` with a `MenuBarExtra` and no window scene.
  - Info.plist: `LSUIElement`, `NSAppleEventsUsageDescription`.
  - Entitlements, signing, and hardened runtime.
- [ ] Menu items:
  - Status line: idle, running with use case and step, or last success with time.
  - Last error, if any.
  - **Run Now**, **Pause/Resume**, **Settings…**, **Show Backups**, **Quit**.
- [ ] Automation runs off the main actor, one script at a time, with a timeout. The UI observes `RunCoordinator`.
- [ ] `scripts/build-app.sh`: XcodeGen generate, `xcodebuild` Release, signature verification, and copy to `/Applications`.
- [ ] Acceptance:
  - No Dock icon.
  - **Run Now** processes the dividend backlog exactly as the CLI does.
  - Automation prompts name the app.

### 4. Settings window and launch at login

- [ ] A settings window opened only from the menu:
  - Workbook pickers.
  - Sheet names, read from the workbook.
  - Student routes, prefilled from the latest Schoology email.
  - Schedule, and **Launch at Login**.
- [ ] Settings are checked on save by reading each sheet once, which is a format preflight using the existing template checks.
- [ ] **Launch at Login** through `SMAppService.mainApp`:
  - It shows the system approval state and a link to System Settings when approval is required.
  - It is enabled only after settings are valid.
- [ ] First launch with no settings opens the settings window once and stays paused until settings are saved.
- [ ] Acceptance: settings survive relaunch, login item registration shows in System Settings, and the app starts after logout and login.

### 5. Unattended behavior hardening

- [ ] Measure whether a scheduled run activates Numbers or Mail, shows a document window, or steals focus. Test it while typing in another app.
  - If it does, add containment: open documents with `activate` avoided, hide Numbers windows after opening, and restore the frontmost app.
  - Retest after each change.
- [ ] A workbook already open in Numbers is skipped with a clear status, so unsaved edits are never saved or closed. This needs a new test seam and `writeSheetUpdate` checks for open documents.
- [ ] An iCloud workbook not downloaded locally is reported and retried later.
- [ ] Sleep during a run: on wake, the coordinator re-reads state before writing, which the existing changed-workbook check already enforces.
- [ ] A failure notification without personal data.

### 6. End-to-end acceptance

- [ ] A disposable dividend ledger and a copy of the grades workbook first, using `--eml` fixtures and live Mail in preview mode.
- [ ] Then the real setup:
  - No Dock icon or foreground window during scheduled runs.
  - Survives logout and login.
  - Each week or payment is written once.
  - Failed mail stays in the Inbox, and only verified messages are archived.
- [ ] Update the README and the design document. Retire CLI-only guidance that the app replaces.

## Resolved questions

- **Students:** one routed student; the others are ignored.
- **Schedule:** every 30 minutes, plus launch, wake, and **Run Now**.
- **Notifications:** failures only; a daily or weekly summary may come later.
- **Sweep interest:** keep it.
