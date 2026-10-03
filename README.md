# email-gobbler

Turns recognized emails in macOS Mail into verified rows in Numbers workbooks.
Two use cases run on one shared core:

- **Schoology grades:** weekly summary emails update a student's weekly grades sheet.
- **E*TRADE dividends:** "Dividend or interest paid" alerts append payments to a
  dividend ledger.

The Swift package lives in [`MailToNumbers`](MailToNumbers/README.md); run its tests
with `swift test` from that directory. The `mail-to-numbers` tool processes matching
Inbox messages oldest first: it previews each Numbers update, applies it with a
backup and a full read-back check, and can then mark the message read and move it to
iCloud Archive. See the package documentation for commands and workbook formatting.

## EmailGobbler menu bar app (in progress)

`App/` contains EmailGobbler, the menu bar app, built on the `MailToNumbersService` library. It has no Dock icon or main
window. It checks mail at launch, every 30 minutes, and after the Mac wakes, and offers **Run Now**,
**Pause**, and its last result in the menu. Build and sign it with your Apple Development certificate
(requires Xcode and XcodeGen):

```bash
scripts/build-app.sh            # builds App/build.noindex/Build/Products/Release/EmailGobbler.app
scripts/build-app.sh --install  # also copies it to /Applications
```

On first launch the app opens **Settings…**: choose the dividend ledger and each student's grades
sheet, the schedule, and how many backups to keep. Saving reads every chosen sheet and refuses to save
until its columns and formats are ready. Settings live in
`~/Library/Application Support/EmailGobbler/settings.json` and apply immediately. **Launch at login**
is available once valid settings are saved. The app asks for permission to control Mail and Numbers
the first time it runs with an enabled use case.

Runs never write a workbook that is open in Numbers (close it and the next run updates it), wait for
iCloud to download a workbook if needed, hide Numbers again if a run had to launch it, and post a
notification only when a use case newly stops; details stay in the menu.

The next product step is a [menu bar app that starts at user login](docs/macOS-menu-bar-app-plan.md).
That document covers the app shell, scheduling, permissions, workbook setup,
and the checks required before unattended processing.
The [implementation plan](docs/menu-bar-app-implementation-plan.md) lists the milestones.
