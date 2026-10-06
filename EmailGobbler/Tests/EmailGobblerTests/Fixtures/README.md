# SG-02 Schoology extraction fixtures

`schoology-weekly.synthetic.html` is a decoded, anonymized HTML body derived
from a representative Schoology weekly email. The private source email is not
included. Only these synthetic fixtures may be committed.

## Preserved structure

The source's element hierarchy, tables, nesting, class names, course rows,
assignment rows, student boundaries, and overall-grade field shapes are retained.
There are two student sections with 13 and 12 course rows respectively:

- 9 overall grades with a percentage and letter
- 3 letter-only overall grades
- 13 missing overall grades represented by a dash

Assignment grades, attendance, overdue submissions, upcoming events, and recent
activity remain as surrounding content that the overall-grade parser must ignore.
Several course labels deliberately occur in both student sections.

## Synthetic content

Student names, course/section labels, assignments, prose, grades, reporting dates,
and grading-period text have been replaced. The synthetic reporting range is
March 2–9, 2026. Each course has synthetic grading-period text
`25-26 T2 (14 Jan - 12 Jun)`; this is extracted context, not authorization to infer
an academic year or configure course mappings.

All link/image targets use `example.invalid`. IDs, timestamps, title/alt values,
and data attributes are synthetic. Comments were omitted and script bodies were
replaced with inert comments. Generic CSS and layout attributes remain; HTML
serialization normalizes quoting and entities. Unrelated event/activity prose is
replaced with placeholder text and does not model valid event dates.

## Expected extraction

`schoology-weekly.expected.json` records the expected dates and all 25 synthetic
course results grouped by student. Percentages are decimal strings to avoid
binary floating-point rounding. `null` percentage with `state: present` means
letter-only; `state: missing` means a dash with no grade values.

This JSON is a fixture oracle, not a required production API. It was prepared
alongside anonymization; independently compare it with the HTML while reviewing
tests. It does not demonstrate that a parser has passed tests.

## Claude's next step

Use this fixture for SG-02 RED tests and wire it into SwiftPM test resources.
Keep the existing domain tests unchanged. Add focused synthetic variants for
blank grades, numeric zero, year-boundary dates, absent grading context, HTML
entities/formatting, and malformed/unsupported reports. Those edge cases are not
all present in this baseline and should not be claimed as observed email variants.

Parse overall grades only. Preserve course labels and explicit context without
mapping IDs or inferring the academic year. All course rows, including missing
grades and nonacademic-looking labels, remain extraction results; filtering and
workbook update policies belong to later work.

# E*TRADE dividend fixture

`etrade-dividend.synthetic.eml` keeps the single-part `text/html` structure of a
real "Dividend or interest paid" alert, including its hidden preview text and the
`td.body-content` paragraphs with bold `Account:`, `Security:`, and
`Amount Credited:` labels. The account, security, amount, payment date, headers,
and every link are synthetic. Git stores the file byte for byte (`.gitattributes`).
Live alerts can list several payments; the multi-payment test markup is constructed from the single-payment layout.

# GnuCash book fixture

`gnucash-book.synthetic.xml` is a hand-written GnuCash 5.17 XML book with synthetic accounts
(placeholders, checking, credit card, expenses, dividends), two transactions, and a template
section, following `libgnucash/backend/xml` in GnuCash 5.17. `gnucash-cli` 5.17 loads it and reports
the expected journal and balances. `gnucash-book.synthetic.gnucash` is the same file compressed with
`gzip -n -9`, the way GnuCash saves compressed books. No real account data is included.

# Spending email fixtures

`amex-purchase.synthetic.eml` and `paypal-receipt.synthetic.eml` keep the HTML layout of one real
American Express "Card may not have been present" alert and one real PayPal payment receipt. Names,
card and account endings, merchants, amounts, dates, transaction and invoice IDs, phone numbers,
addresses, headers, and every link are synthetic. Other formats in the tests are constructed variants.
