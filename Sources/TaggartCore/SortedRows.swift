import Foundation

/// The file list in sorted order, recomputed only when the files or the sort
/// order change, rather than on every view update. Editing tags doesn't
/// re-sort: rows stay put while you edit (Return moves to the next row, which
/// would otherwise jump away), and re-ordering a big list is slow. Clicking a
/// column header sorts again with the current values.
///
/// Sorting reads each file's sort values once and compares those, which is
/// several times faster than `sorted(using:)` with the key-path comparators
/// (that recomputes the values on every comparison). Strings compare like
/// Finder ("Track 2" before "Track 10"), as `KeyPathComparator` does.
@MainActor
public final class SortedRows {
    private struct Key: Equatable {
        var ids: [AudioFileItem.ID]
        var sortOrder: [KeyPathComparator<AudioFileItem>]
    }

    private var key: Key?
    private var cached: [AudioFileItem] = []
    /// How many times the order was actually computed (for tests).
    private(set) var computations = 0

    public init() {}

    public func rows(of items: [AudioFileItem], sortOrder: [KeyPathComparator<AudioFileItem>]) -> [AudioFileItem] {
        let key = Key(ids: items.map(\.id), sortOrder: sortOrder)
        if key == self.key {
            return cached
        }
        self.key = key
        computations += 1
        cached = sortOrder.isEmpty ? items : Self.sorted(items, by: sortOrder)
        return cached
    }

    private enum Value {
        case string(String)
        case int(Int)
        case double(Double)
        case other
    }

    static func sorted(_ items: [AudioFileItem], by comparators: [KeyPathComparator<AudioFileItem>]) -> [AudioFileItem] {
        let keyed = items.enumerated().map { index, item in
            (item: item, values: comparators.map { value(of: item[keyPath: $0.keyPath]) }, index: index)
        }
        return keyed.sorted { a, b in
            for (position, comparator) in comparators.enumerated() {
                var result = compare(a.values[position], b.values[position])
                if comparator.order == .reverse {
                    result = result == .orderedAscending ? .orderedDescending
                        : result == .orderedDescending ? .orderedAscending : .orderedSame
                }
                if result != .orderedSame {
                    return result == .orderedAscending
                }
            }
            // Equal values keep their list order.
            return a.index < b.index
        }
        .map(\.item)
    }

    private static func value(of any: Any) -> Value {
        switch any {
        case let string as String: .string(string)
        case let int as Int: .int(int)
        case let double as Double: .double(double)
        default: .other
        }
    }

    private static func compare(_ a: Value, _ b: Value) -> ComparisonResult {
        switch (a, b) {
        case let (.string(x), .string(y)):
            x.localizedStandardCompare(y)
        case let (.int(x), .int(y)):
            x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        case let (.double(x), .double(y)):
            x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        default:
            .orderedSame
        }
    }
}
