# email-gobbler

Turns recognized emails in macOS Mail into verified rows in Numbers workbooks and
transactions in a GnuCash book. Five use cases run on one shared core:

- **Schoology grades:** weekly summary emails update a student's weekly grades sheet.
- **E*TRADE dividends:** "Dividend or interest paid" alerts append payments to a
  dividend ledger.
- **AmEx purchases:** American Express purchase alerts become a transaction on the card account.
- **PayPal payments:** PayPal receipts in USD become two transactions: the purchase from the PayPal
  account, and a collection that moves the money into PayPal from the bank ("PayPal - Collection")
  or from the card ("AmEx - Collection"). PayPal balance payments need no collection. The PayPal
  transaction ID goes in the Num field.
- **Verizon bills:** "Your Verizon bill is ready." emails for Auto Pay accounts become a transaction
  dated on the Auto Pay date, paid from the account you choose (booked ahead, as the bill is due later).
  Bills without Auto Pay stay in the Inbox.

The GnuCash book is chosen under **Settings… › GnuCash** (`GnuCashBook` reads and appends to the XML
format). Spending emails are booked like the merchant's latest transaction on the same account:
same description and expense account. Purchases from merchants the book has never seen go to a
holding account you choose, for you to recategorize. A purchase counts as already booked when the
account has the same amount within three days, or the same PayPal transaction ID; the email is then
archived without a new transaction. Emails from these senders that are not purchases stay in the
Inbox. Transactions are added only while the book is closed in GnuCash, after a backup.

The Swift package lives in [`EmailGobbler`](EmailGobbler/README.md); run its tests
with `swift test` from that directory. The `email-gobbler` tool processes matching
Inbox messages oldest first: it previews each Numbers update, applies it with a
backup and a full read-back check, and can then mark the message read and move it to
iCloud Archive. See the package documentation for commands and workbook formatting.

## EmailGobbler menu bar app (in progress)

`App/` contains EmailGobbler, the menu bar app, built on the `EmailGobblerService` library. It has no Dock icon or main
window. It checks mail at launch, every 30 minutes, and after the Mac wakes, and offers **Run Now**,
**Pause**, and its last result in the menu. Build and sign it with your Apple Development certificate
(requires Xcode and XcodeGen):

```bash
scripts/build-app.sh            # builds App/build.noindex/Build/Products/Release/EmailGobbler.app
scripts/build-app.sh --install  # also copies it to /Applications and restarts a running copy
```

The app icon is a layered Icon Composer document, `App/Resources/AppIcon.icon`, so macOS applies its
Liquid Glass, dark, and tinted appearances. Regenerate its layers with
`swift scripts/make-app-icon.swift App/Resources/AppIcon.icon/Assets`, or open it in Icon Composer.

On first launch the app opens **Settings…**: choose the dividend ledger and each student's grades
sheet, the GnuCash book and its accounts for AmEx and PayPal, the schedule, and how many backups to
keep. Saving reads every chosen sheet and the book, and refuses to save until the sheets' columns and
formats are ready and every chosen account exists and can hold transactions. Settings live in
`~/Library/Application Support/EmailGobbler/settings.json` and apply immediately. **Launch at login**
is available once valid settings are saved. The app asks for permission to control Mail and Numbers
the first time it runs with an enabled use case.

Runs never write a workbook that is open in Numbers (close it and the next run updates it), wait for
iCloud to download a workbook if needed, hide Numbers or Mail again if a run had to launch it, and post a
notification only when a use case newly stops; details stay in the menu.

The next product step is a [menu bar app that starts at user login](docs/macOS-menu-bar-app-plan.md).
That document covers the app shell, scheduling, permissions, workbook setup,
and the checks required before unattended processing.
The [implementation plan](docs/menu-bar-app-implementation-plan.md) lists the milestones.
