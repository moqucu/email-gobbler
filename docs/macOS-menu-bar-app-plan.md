# macOS menu bar app plan

## Goal and boundary

Turn the current Swift command-line workflow into a macOS app that starts when
the user logs in, stays in the right side of the menu bar, and processes new
Schoology mail without a main window. A menu click may open a small status and
settings panel. The app must not bring Mail or Numbers to the foreground during
an automatic run.

This is a **user login app**, not a system boot daemon. It needs the logged-in
user's Mail account, Numbers workbook, and macOS Automation permissions. If the
Mac is off, asleep, or no user is logged in, work waits until the next login or
wake. The app can process mail while the user works in another app.

Use a SwiftUI `MenuBarExtra` as the only persistent scene and set `LSUIElement`
to `YES` so the app has no Dock icon or ordinary app window. Apple documents
both the [menu bar scene](https://developer.apple.com/documentation/swiftui/menubarextra)
and the [agent-app property](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement).
Build the app target for macOS 13 or later, where `SMAppService` is available;
the `MailToNumbers` libraries can keep its lower deployment target.

## Proposed architecture

| Component | Responsibility |
| --- | --- |
| `SchoologyGrades` | Keep the deterministic HTML extraction and grade types independent of Mail, Numbers, and UI. |
| Shared workflow module | Move MIME decoding, course/column mapping, planning, backup, verification, and consume-after-save sequencing out of the CLI into reusable Swift code. Keep the CLI as a diagnostic harness. |
| Mail adapter | Query only the configured iCloud account and Inbox, identify messages by stable message ID, fetch source, and mark read/move to that account's `Archive` mailbox only after every workbook update verifies. |
| Numbers adapter | Read the chosen workbook, apply validated row changes, save, and read back the result. Retain a recoverable backup before writing. |
| Menu bar app | Own configuration, status, scheduling, permissions, error display, and explicit user commands. It calls the same workflow used by the CLI. |

The menu should show the last successful week and run time, current activity,
and a concise error if a run stops. Include **Run Now**, **Pause/Resume**,
**Choose Workbook**, **Review Mapping**, **Launch at Login**, and **Quit**.
Keep detailed student grades out of notifications and routine logs.

## Startup and processing loop

1. On first launch, let the user select the `.numbers` workbook, choose the
   iCloud Mail account and destination sheet rules, and review course mappings.
   Store user-specific settings outside the Git repository. A one-time file
   picker or settings panel is acceptable; normal operation needs no window.
2. Request macOS permission to automate Mail and Numbers with a clear
   `NSAppleEventsUsageDescription`. Configure the Apple Events entitlement for
   the signed app. The current CLI's Automation grants will not automatically
   authorize a new app bundle. See Apple's [usage-description key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
   and [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).
3. Offer a **Launch at Login** toggle backed by `SMAppService.mainAppService`.
   Register it only after first-run setup succeeds, and show the system's
   approval state. Apple's [login-item API](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
   launches the main app on subsequent user logins; [registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)
   may require user approval.
4. Run one scan after login, then on a modest interval (initially 30 minutes),
   when the Mac wakes, and when the user chooses **Run Now**. Coalesce triggers
   so only one run can access the workbook at a time. Wake detection can use
   [`NSWorkspace.didWakeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification).
5. Query matching messages in the iCloud Inbox and process all eligible ones
   **oldest first**. The current CLI picks only the newest match; the app must
   handle a backlog. Validate sender, subject, dates, MIME, and student/course
   mappings before any write. Route each student to a configured academic-year
   sheet rather than guessing from the email's grading-period text.
6. For each message, plan all affected sheet updates, back up the workbook,
   apply and verify every update, then mark the exact message read and move it
   to iCloud `Archive`. A workbook failure must leave Mail untouched. If the
   Mail move fails after a verified workbook save, inspect the message's current
   mailbox before retrying; a rerun must replace the same week, never add a
   duplicate. Show the error in the menu and record message ID, reporting week,
   stage, result, and timestamp for diagnostics without storing raw mail or
   grades in logs.

## Workbook access and packaging

Package this as a signed `.app` installed at a stable location such as
`/Applications` before enabling launch at login. If the app is sandboxed, the
user's workbook selection needs a persistent security-scoped bookmark and
read/write access when the app relaunches; see Apple's [sandbox file-access
guide](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
Keep backups in a private Application Support location, with a retention rule
and a way to locate the latest backup from the menu. Do not embed the user's
workbook path, student names, or course mappings in source control.

The current Numbers adapter opens a document through Apple Events. Before
calling the app windowless, verify on a clean login that automatic runs do not
activate Mail or Numbers, expose a document window in front, or steal keyboard
focus. If they do, change the adapter or its presentation behavior and repeat
the test. Also test iCloud Drive files that are temporarily unavailable and
workbooks already open with unsaved edits; neither should be silently replaced.

## Implementation order and acceptance checks

1. **Extract the workflow:** shared service and protocol-backed Mail/Numbers
   adapters; keep pure unit tests for message selection, multi-student routing,
   duplicate weeks, mapping failures, and consume-after-verify ordering.
2. **Build the app shell:** one `MenuBarExtra`, no `WindowGroup`, `LSUIElement`,
   status menu, manual run, pause, and clear errors.
3. **Add setup and login:** workbook picker, persistent configuration, Automation
   prompts, `SMAppService` toggle, signed app bundle, and relaunch checks.
4. **Add unattended scans:** login, interval, and wake triggers; oldest-first
   backlog; one-run-at-a-time guard; retries without duplicate rows.
5. **Verify end to end:** use a disposable workbook and test Mail account for
   failure paths, then run against the real setup. Confirm the app has no Dock
   icon or foreground window, survives logout/login, writes each week once,
   leaves failed mail untouched, and archives only verified messages.

The first usable release can target one configured workbook and the current
Schoology email format. General course naming changes and multiple workbook
destinations should be handled through explicit mapping, not silent guesses.
