import Foundation

public enum DecodeBudget {
    public static func sourceCost(width: Int, height: Int, budget: Int) throws -> Int {
        let (row, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (bytes, imageOverflow) = row.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !rowOverflow, !imageOverflow, bytes <= budget else {
            throw ImageDecodeError.budgetExceeded
        }
        return bytes
    }
    public static func isHeavy(width: Int, height: Int) -> Bool {
        // Division avoids multiplying untrusted header dimensions.
        width > 0 && height > 0 && width > 12_000_000 / height
    }
}
