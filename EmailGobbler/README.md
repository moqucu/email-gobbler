# EmailGobbler package

Turns recognized emails in macOS Mail into verified rows in Numbers workbooks.
Each kind of email is a *use case* built on one shared core:

| Module | Contents |
| --- | --- |
| `EmailGobblerCore` | Dates, MIME decoding, Mail listing/fetching/archiving, the Numbers sheet model (snapshot, plan, format checks, verification), AppleScript generation, backups, and the per-message workflow (`MailToNumbersUseCase`, `processMessage`). |
| `SchoologyGrades` | Schoology weekly-summary extraction, the weekly grades sheet planner, and the weekly-row upsert library. |
| `EtradeDividends` | E*TRADE "Dividend or interest paid" alert extraction and the dividend ledger planner. |
| `email-gobbler` | Command-line tool that runs a use case through the shared workflow. |

A use case only parses its email and turns it into a `SheetUpdatePlan`: replace one
row, or insert rows above or below an existing *anchor row*, with typed values,
expected displays, and formats required on the anchor row. Everything else is
shared: reading the sheet, checking formats, backing up, writing, verifying the
whole saved sheet, and archiving the email. To add a use case, implement
`MailToNumbersUseCase` (a `MailQuery`, `summarize(html:)`, and `plan(html:sheet:)`)
and add a subcommand.

## Requirements

- **macOS:** 13 or later, with Mail and Numbers; the tool asks for Automation access.
- **Swift Compiler:** 6.3 or later, Swift 6 language mode.
- **Dependency:** SwiftSoup (from 2.7.0, below 3.0.0; `Package.resolved` pins 2.13.9) for HTML parsing.

## Testing

```bash
cd EmailGobbler
swift test
```

All 148 tests are offline and use synthetic fixtures; they do not drive Mail or Numbers.

## Command line

```bash
cd EmailGobbler
swift run email-gobbler etrade-dividends --mail \
  --numbers "/path/to/Dividend or Interest Paid.numbers"
swift run email-gobbler schoology-grades --mail \
  --numbers /path/to/trend.numbers --sheet "Student 2026/27" --student "Student Full Name"
```

- **Source:** `--eml <path>` reads one saved message. `--mail` lists every Inbox
  message matching the use case (`Dividend or interest paid` from `etrade.com`, or
  `Weekly Schoology Summary`; override the subject with `--subject`) and processes
  them **oldest first**, stopping at the first failure.
- **Summary only:** without `--numbers`, the tool prints what it extracted.
- **Preview:** with `--numbers`, it reads a disposable copy of the workbook, prints
  the planned rows, and checks the anchor row's formats. Nothing is written.
- **Apply:** `--apply --backup-dir <dir>` backs up the workbook to a timestamped file,
  writes, saves, and verifies every value of the saved sheet and the written rows'
  displays. It stops without writing if the workbook changed since it was read.
- **Archive:** `--consume` (with `--mail --apply`) marks each message read and moves it
  to iCloud Archive, only after its write verified, or when the sheet already holds
  all of its data. A failed write leaves that message and later ones in the Inbox.

The dividend ledger uses sheet `Sheet 1` unless `--sheet` is given. Grades require
`--sheet` and `--student`.

### Formatting the workbooks

Numbers scripting cannot choose a date style, percentage decimals, or currency
symbol, but rows added next to an existing row inherit that row's formats. So the
tool needs at least one formatted data row and checks it before writing.

| Sheet | Date | Values |
| --- | --- | --- |
| Grades | Date & Time, date only, shown like `9/21/26` | Percentage, 0 decimal places (`0.8794` shows as `88%`) |
| Dividend ledger | Date & Time, date only, shown like `9/21/2026` | Amount Credited: Currency (`$3.39`); the tool reapplies Currency after writing because Numbers resets it when a number is written |

Stored values stay exact: dates at midnight, fractions, and amounts.

### Dividend ledger rules

- Columns are found by header: `Financial Institution`, `Account`, `Type`, `Date`,
  `Security`, `Amount Credited`.
- Each payment in an alert becomes one row: `E*Trade Financial`, the account as
  `XXXX-` plus its last four digits, `Dividend or Interest Paid`, the payment date,
  the security with whitespace collapsed, and the amount.
- New rows are appended below the last non-empty row; the ledger is not re-sorted.
- A payment whose account, date, security, and amount already appear in one row is
  reported as already recorded and not written again. Two genuinely identical
  payments from separate alerts would therefore be recorded once.

### Grades sheet rules

The grades sheet has a Date column followed by percentage/letter column pairs, with
the course name above each percentage column. Course labels match by the part before
a ` - <number>:` section suffix. Every workbook course must occur in the email; a
graded email course without a column stops the plan, and ungraded unmatched courses
are reported as ignored. Dates must run newest first from row 2. An existing week is
replaced; a new week is inserted next to a dated row so it inherits its formats.

## Schoology weekly-email extraction

`parseSchoologyWeeklyEmail(html:)` turns decoded Schoology weekly-digest HTML into `SchoologyWeeklyExtraction`: the reporting period, then each student's course labels, optional grading-period text, and overall grade. Extraction types are separate from `WeeklyReport`. Labels are not mapped to IDs, and no course is filtered out. MIME decoding, Mail access, and Numbers updates are handled by `EmailGobblerCore`.

Prototype rules, encoded by the tests. These are contract decisions for the anonymized fixture, not claims about every format Schoology may produce:

- **Dates:** each date uses one or two ASCII digits for month and day, then a two-digit year (`M/D/YY` or `MM/DD/YY`). Single slashes separate fields; signs and extra digits are rejected. `YY` maps to 2000–2099, independent of today's date. An absent, empty, or whitespace-only date span is `missingReportingDates`. Nonempty text that isn't a valid date is `invalidReportingDate`. A start date after the end date is `reversedReportingRange`.
- **Text:** ordinary HTML whitespace (space, tab, CR, LF, FF) is collapsed and trimmed. Entities are decoded. Nonbreaking spaces (literal or `&nbsp;`) are preserved.
- **Context:** grading-period text follows the text-normalization rule above when present and is `nil` when absent. No academic year is inferred.
- **Grades:** only the overall grade cell counts. Assignment, attendance, and activity grades are ignored. A letter with a `NN%` value becomes `present(letter, percentage)`. A letter alone becomes `present(letter, nil)`. A dash is `missing(.dash)`, and an empty cell is `missing(.blank)`; both are distinct from `0%`. Numeric decimal values are preserved, but not textual trailing zeros. Finite percentages outside 0–100 are kept unclipped.
- **Malformed grades:** a percentage without a letter, a populated numeric field without `%`, or a non-numeric or non-finite value throws `malformedGrade(studentLabel:courseLabel:)`.
- **Structure:** each student section needs a nonblank label and a summary table with at least one course row. Every course row needs a nonblank label and a grade cell. Otherwise extraction throws `unsupportedReportStructure`, and no partial result is returned. Duplicate course labels within a student stay as separate rows in document order.
- **Errors:** error tests contain one fault each. Precedence among multiple independent faults is unspecified.

Fixture provenance is described in `Tests/EmailGobblerTests/Fixtures/README.md`.

## Weekly grade rows (`upsertWeeklyRows`)

The examples below cover weekly grade-row validation and upserts. The command-line grades workflow uses `planGradesWorkbookUpdate` instead; this API is kept for callers that map courses to stable IDs. The caller supplies decoded HTML to the extraction API and maps the extracted student, year, and course context into `WeeklyReport` before upserting. MIME decoding and those mappings remain upstream responsibilities.

### Complete-Snapshot Requirement

Input a **complete snapshot** of grades for a single student/year/sheet:
- **Report grades must be complete:** Every course in the report must appear exactly once; no partial updates. The caller is responsible for ensuring the report's course set matches the configured courses for that student/year sheet.
- **Library validation:** The library checks that each existing row's course set matches the report's course set exactly (as supplied); it does not validate against a separate course configuration.
- **All grades require a letter:** No blanks allowed in the incoming report.
- **Percentage is optional:** May be `nil` (letter-only) or a precise decimal value; never inferred.

### Data Types

```swift
import Foundation
import EmailGobblerCore
import SchoologyGrades

let date = try CalendarDate(year: 2025, month: 3, day: 9)
let grade = CourseGrade(courseId: "math", percentage: Decimal(string: "95.5"), letter: "A")
let row = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date, grades: [grade])
let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", 
                           periodStart: try CalendarDate(year: 2025, month: 3, day: 3), 
                           periodEnd: date, 
                           grades: [grade])
```

### Upsert Example

```swift
import EmailGobblerCore
import SchoologyGrades

let existing = [
    WeeklyRow(studentId: "student-a", academicYear: "2024-25", 
              weekEnd: try CalendarDate(year: 2025, month: 2, day: 23),
              grades: [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")])
]

let incomingReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25",
    periodStart: try CalendarDate(year: 2025, month: 3, day: 3),
    periodEnd: try CalendarDate(year: 2025, month: 3, day: 9),
    grades: [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")])

let result = try upsertWeeklyRows(existingRows: existing, report: incomingReport)
// result contains both weeks, sorted newest first, with canonical course ordering
```

## Validation Behavior

`upsertWeeklyRows()` is strict and rejects invalid input **before modifying anything**:

### Report Validation
- Student ID and academic year must not be blank (ignoring whitespace/newlines)
- Date range: `periodStart ≤ periodEnd` required
- Grades must not be empty
- Each grade must have:
  - Nonblank course ID
  - Valid letter (not blank or "-" when trimmed of whitespace/newlines)
  - Finite decimal or `nil` percentage
- No duplicate course IDs within the report

### Existing Row Validation
- All rows must match the report's student ID and academic year exactly
- No duplicate `weekEnd` dates (even identical rows are rejected)
- Each row's course set must match the report's course set exactly
- Each grade in each row must have valid identifiers and values (including rows being replaced)

### Errors

Validation failures throw `DomainError.validationFailed(_)` or `DomainError.invalidDate`:

```swift
import Foundation
import EmailGobblerCore
import SchoologyGrades

do {
    let result = try upsertWeeklyRows(existingRows: existing, report: report)
} catch DomainError.validationFailed(let message) {
    // Invalid input; no rows modified
    print("Validation error: \(message)")
} catch DomainError.invalidDate {
    // Invalid calendar date
    print("Calendar date error")
}
```

## CalendarDate

`CalendarDate` validates Gregorian calendar dates using proper leap-year rules:
- Years divisible by 400 are leap years
- Years divisible by 100 (not by 400) are not leap years
- Years divisible by 4 (not by 100) are leap years
- All other years are not leap years

Example:
```swift
try CalendarDate(year: 2024, month: 2, day: 29)  // ✓ Valid leap year
try CalendarDate(year: 2000, month: 2, day: 29)  // ✓ Valid (century leap year)
try CalendarDate(year: 1900, month: 2, day: 29)  // ✗ Invalid (century, not divisible by 400)
try CalendarDate(year: 2023, month: 2, day: 29)  // ✗ Invalid (not a leap year)
```

## Scope & limitations

- ✓ Extraction, planning, format checks, backed-up writes, and full read-back verification
- ✓ Oldest-first Mail backlog processing with archive-after-verify
- ✗ No automatic student/sheet routing, report precedence, or academic-year inference
- ✗ No menu bar app yet; see `docs/macOS-menu-bar-app-plan.md`
- The first data row of each sheet must be entered and formatted by hand.

Extraction and planning code is deterministic and has no side effects; only the
Mail and Numbers adapters in `EmailGobblerCore` automate other applications.
