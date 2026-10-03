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

The next product step is a [menu bar app that starts at user login](docs/macOS-menu-bar-app-plan.md).
That document covers the app shell, scheduling, permissions, workbook setup,
and the checks required before unattended processing.
The [implementation plan](docs/menu-bar-app-implementation-plan.md) lists the milestones.
