import Foundation
import MailNumbersCore

/// Problems that would stop a weekly grades update, phrased as what to fix in Numbers.
public func checkGradesSheet(_ sheet: SheetSnapshot) -> [String] {
    let headers = sheet.headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let pairsValid = headers.count >= 3 && headers.count % 2 == 1 && headers[0] == "Date"
        && stride(from: 1, to: headers.count, by: 2).allSatisfy { !headers[$0].isEmpty && headers[$0 + 1].isEmpty }
    guard pairsValid else {
        return ["Start with a Date column, then each course name followed by a blank letter column"]
    }
    guard case .date? = sheet.cell(row: 2, column: 1)?.value else {
        return ["Enter the first week by hand so new rows can copy its formatting"]
    }
    var problems: [String] = []
    if let cell = sheet.cell(row: 2, column: 1), !FormatRequirement.dateOnly(.monthDayShortYear).isSatisfied(by: cell) {
        problems.append("Format the Date column like 9/21/26 (row 2)")
    }
    for index in stride(from: 1, to: headers.count, by: 2) {
        guard let cell = sheet.cell(row: 2, column: index + 1), !FormatRequirement.wholePercent.isSatisfied(by: cell) else { continue }
        problems.append("Format \(headers[index]) as Percentage with 0 decimal places (row 2)")
    }
    return problems
}
