# MailToNumbers

A Swift library for extracting Schoology weekly overall grades from decoded HTML and validating and upserting weekly grade rows. HTML extraction uses SwiftSoup; parsing and row updates are deterministic and have no external side effects.

## Requirements

- **macOS:** 10.15 or later
- **Swift Compiler:** 6.3 or later
- **Language Mode:** Swift 6 (see Package.swift `swiftLanguageModes: [.v6]`)

## Dependencies

HTML extraction uses SwiftSoup. `Package.swift` allows compatible releases from 2.7.0 up to, but not including, 3.0.0; `Package.resolved` currently pins 2.13.9. Swift Package Manager fetches the dependency during setup. Parsing itself does not access the network.

## Testing

Run the test suite from the package directory:

```bash
cd MailToNumbers
swift test
```

The weekly-upsert domain tests, weekly-email extraction tests, mail-decoder tests,
workbook planning tests, Numbers formatting tests, and mail-consumption ordering
tests are GREEN. All 118 tests pass.

## Mail preview and Numbers update

The `mail-to-numbers` Swift executable reads a message from an `.eml` file
or from the macOS Mail Inbox through Mail's Apple Events interface. It decodes a
`text/html` MIME part, extracts the Schoology weekly summary, and prints the
reporting dates and counts of students, courses, and present grades. The Mail mode
uses the account already configured in macOS Mail and may prompt for Automation
access. It selects the newest Inbox message whose subject contains the supplied
text.

```bash
cd MailToNumbers
swift run mail-to-numbers --eml /path/to/schoology-message.eml
swift run mail-to-numbers --mail-subject "Your Children's Weekly Schoology Summary"
```

The preview supports `text/html` with base64, quoted-printable, or unencoded
content and common UTF-8/Latin-1/Windows-1252 charsets. It reports an error for
unsupported MIME formats or Schoology layouts. Message content stays in memory;
the program does not save a copy. The domain library remains independent of
Mail and the filesystem.

### Preview a Numbers update

Supply an exact student label and target sheet to compare the extracted email
with a Numbers workbook. The command opens a temporary copy of the workbook,
reads its headers and date rows, and prints the proposed row and cell values.
Without `--apply`, it never writes to the source workbook.

```bash
swift run mail-to-numbers \
  --mail-subject "Your Children's Weekly Schoology Summary" \
  --numbers /path/to/trend.numbers \
  --sheet "Student 2026/27" \
  --student "Student Full Name"
```

The current planner expects a Date column followed by percentage/letter column
pairs, with the course name above each percentage column. It matches the part
of a Schoology course label before its numeric section suffix to the header.
Every workbook course must occur in the email. A graded email course without a
matching header stops the plan; unmatched courses with missing grades are
reported as ignored. Percentages are displayed as Numbers fractions (for
example, `0.8794` for `87.94%`). The planner identifies an existing week for
replacement or a row position for insertion. It has not yet been connected to
the domain row-upsert API.

Before the first write, format the existing data rows in Numbers: set the Date
cells to a date-only Date & Time style that shows `9/21/26`, and set every
percentage column to Percentage with 0 decimal places. Numbers scripting cannot
choose a date style or decimal places, so the writer relies on these formats. A
replaced row keeps its own formatting. A new row is added next to a dated row and
inherits that row's formatting. The stored values stay exact: a date at midnight
and a fraction such as `0.8794`, displayed as `88%`. If the row being replaced,
or the row a new week would inherit from, lacks these formats, the command stops
before writing and names the cell to format. The sheet needs at least one dated
row, so enter the first week by hand.

To save the proposed row, add `--apply --backup /path/to/backup.numbers` to the
same command. The backup path must not exist. The writer checks that the workbook
still matches the preview, copies the original to the backup, inserts a new row
at the planned position or replaces the existing week, saves, and reopens a
temporary copy to verify the date, all planned values, and how the date and
percentages are displayed. A failed save or
verification leaves the backup available for recovery. Repeating a run for the
same week replaces its row rather than adding a duplicate.

For a message read directly from Mail, add `--consume` alongside `--apply` to
mark that exact message as read and move it from the iCloud Inbox to the iCloud
Archive mailbox. The command verifies the moved message in Archive. Consumption
runs only after the Numbers save and read-back checks pass. `.eml` input and
preview-only commands cannot consume mail. Without `--consume`, Mail remains
unchanged.

## Weekly-Email Extraction (SG-02, completed)

`parseSchoologyWeeklyEmail(html:)` turns decoded Schoology weekly-digest HTML into `SchoologyWeeklyExtraction`: the reporting period, then each student's course labels, optional grading-period text, and overall grade. Extraction types are separate from `WeeklyReport`. Labels are not mapped to IDs, and no course is filtered out. MIME decoding, Mail access, and Numbers updates are handled by the executable.

Prototype rules, encoded by the tests. These are contract decisions for the anonymized fixture, not claims about every format Schoology may produce:

- **Dates:** each date uses one or two ASCII digits for month and day, then a two-digit year (`M/D/YY` or `MM/DD/YY`). Single slashes separate fields; signs and extra digits are rejected. `YY` maps to 2000–2099, independent of today's date. An absent, empty, or whitespace-only date span is `missingReportingDates`. Nonempty text that isn't a valid date is `invalidReportingDate`. A start date after the end date is `reversedReportingRange`.
- **Text:** ordinary HTML whitespace (space, tab, CR, LF, FF) is collapsed and trimmed. Entities are decoded. Nonbreaking spaces (literal or `&nbsp;`) are preserved.
- **Context:** grading-period text follows the text-normalization rule above when present and is `nil` when absent. No academic year is inferred.
- **Grades:** only the overall grade cell counts. Assignment, attendance, and activity grades are ignored. A letter with a `NN%` value becomes `present(letter, percentage)`. A letter alone becomes `present(letter, nil)`. A dash is `missing(.dash)`, and an empty cell is `missing(.blank)`; both are distinct from `0%`. Numeric decimal values are preserved, but not textual trailing zeros. Finite percentages outside 0–100 are kept unclipped.
- **Malformed grades:** a percentage without a letter, a populated numeric field without `%`, or a non-numeric or non-finite value throws `malformedGrade(studentLabel:courseLabel:)`.
- **Structure:** each student section needs a nonblank label and a summary table with at least one course row. Every course row needs a nonblank label and a grade cell. Otherwise extraction throws `unsupportedReportStructure`, and no partial result is returned. Duplicate course labels within a student stay as separate rows in document order.
- **Errors:** error tests contain one fault each. Precedence among multiple independent faults is unspecified.

Fixture provenance is described in `Tests/MailToNumbersTests/Fixtures/README.md`.

## Usage

The examples below cover weekly grade-row validation and upserts. The caller supplies decoded HTML to the extraction API and maps the extracted student, year, and course context into `WeeklyReport` before upserting. MIME decoding and those mappings remain upstream responsibilities.

### Complete-Snapshot Requirement

Input a **complete snapshot** of grades for a single student/year/sheet:
- **Report grades must be complete:** Every course in the report must appear exactly once; no partial updates. The caller is responsible for ensuring the report's course set matches the configured courses for that student/year sheet.
- **Library validation:** The library checks that each existing row's course set matches the report's course set exactly (as supplied); it does not validate against a separate course configuration.
- **All grades require a letter:** No blanks allowed in the incoming report.
- **Percentage is optional:** May be `nil` (letter-only) or a precise decimal value; never inferred.

### Data Types

```swift
import Foundation
import MailNumbersCore
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
import MailNumbersCore
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
import MailNumbersCore
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

## Scope & Limitations

The library provides HTML extraction and weekly grade-row processing:
- ✓ Validates grade snapshots
- ✓ Upserts rows without duplicates
- ✓ Canonical course ordering
- ✓ HTML weekly-digest extraction
- ✓ Read-only Mail preview in a separate Swift executable
- ✓ Numbers change preview, backed-up write, and read-back verification in the executable
- ✓ Optional mark-read and iCloud Archive move after a verified write
- ✗ No mapping, routing, or precedence resolution
- ✗ No application shell or UI

**Not yet integrated:** Automatic student/sheet routing, report precedence, multi-sheet runs, and academic-year inference remain upstream concerns outside this library.

## Guarantees

- **Side-effect free:** No filesystem, network, logging, or environment access
- **Immutable:** Input is never modified; new instances created on output
- **Deterministic:** Same valid input always produces identical output
- **Complete validation:** All rows and all input values validated before any modification
