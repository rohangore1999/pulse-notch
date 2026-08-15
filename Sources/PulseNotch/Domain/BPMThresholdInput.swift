import Foundation

enum BPMThresholdInput {
    static let allowedRange = 40...220

    static func sanitizeDraft(_ input: String) -> String {
        String(input.filter(\.isNumber).prefix(3))
    }

    static func committedValue(from draft: String, currentValue: Int) -> Int {
        guard let parsedValue = Int(draft) else {
            return currentValue
        }

        return min(max(parsedValue, allowedRange.lowerBound), allowedRange.upperBound)
    }
}
