# email-gobbler

A Swift package for extracting Schoology weekly overall grades and validating
and updating weekly grade rows. See the [MailToNumbers documentation](MailToNumbers/README.md)
for its API, requirements, and current scope.

Run the tests from `MailToNumbers` with `swift test`. The Swift executable
can read a Schoology `.eml` file or the newest matching message in macOS Mail,
preview a Numbers update, apply it with a backup and read-back check, and then
optionally mark the Mail message read and move it to iCloud Archive; see the
package documentation for commands.

The next product step is a [menu bar app that starts at user login](docs/macOS-menu-bar-app-plan.md).
That document covers the app shell, scheduling, permissions, workbook setup,
and the checks required before unattended processing.
