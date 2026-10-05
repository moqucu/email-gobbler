import Foundation

public enum DomainError: Error, Equatable {
    case notImplemented
    case invalidDate
    case validationFailed(String)
}

public struct CalendarDate: Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    private static func isLeapYear(_ year: Int) -> Bool {
        if year % 400 == 0 { return true }
        if year % 100 == 0 { return false }
        return year % 4 == 0
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    public init(year: Int, month: Int, day: Int) throws {
        guard year > 0 else { throw DomainError.invalidDate }
        guard month >= 1 && month <= 12 else { throw DomainError.invalidDate }
        guard day >= 1 && day <= Self.daysInMonth(month, year: year) else { throw DomainError.invalidDate }

        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}
