# SchoologyDomain

A pure Swift domain library for processing Schoology student weekly overall-grade snapshots. Validates and upserts grade rows without external dependencies, timezone logic, or side effects.

## Requirements

- **Swift:** 6.0 or later (macOS 12+)
- **Toolchain:** Swift Compiler 6.3+ (matches Package.swift `swiftLanguageModes: [.v6]`)

## Testing

Run the test suite from the package directory:

```bash
cd SchoologyDomain
swift test
```

Expected output: **46 tests, 0 failures**

## Usage

SchoologyDomain validates and upserts weekly grade snapshots. The caller is responsible for email parsing, report extraction, and student/year/course mapping upstream.

### Complete-Snapshot Requirement

Input a **complete snapshot** of grades for a single student/year/sheet:
- **Report grades must be complete:** Every configured course must appear exactly once in the report; no partial updates.
- **All grades require a letter:** No blanks allowed in the incoming report.
- **Percentage is optional:** May be `nil` (letter-only) or a precise decimal value; never inferred.

### Data Types

```swift
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
import SchoologyDomain

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

This is a **pure domain library** for a single isolated concern:
- ✓ Validates grade snapshots
- ✓ Upserts rows without duplicates
- ✓ Canonical course ordering
- ✗ No email/HTML parsing
- ✗ No Mail or Numbers integration
- ✗ No mapping, routing, or precedence resolution
- ✗ No application shell or UI

**Not yet integrated:** Mail/Numbers automation, report precedence, multi-sheet workbooks, and academic-year inference remain upstream concerns outside this library.

## Guarantees

- **Side-effect free:** No filesystem, network, logging, or environment access
- **Immutable:** Input is never modified; new instances created on output
- **Deterministic:** Same valid input always produces identical output
- **Complete validation:** All rows and all input values validated before any modification
