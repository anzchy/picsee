import Foundation

public enum DecodeBudget {
    public static func bytesPerPixel(depth: Int, components: Int, hasAlpha: Bool, isFloat: Bool) -> Int {
        let bits = max(isFloat ? 32 : 1, min(64, depth))
        let channels = components >= 3 ? 4 : max(1, components) + (hasAlpha ? 1 : 0)
        return max(4, ((bits + 7) / 8) * channels)
    }

    public static func sourceCost(width: Int, height: Int, budget: Int, bytesPerPixel: Int = 4) throws -> Int {
        let (row, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        let (bytes, imageOverflow) = row.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, bytesPerPixel > 0, !rowOverflow, !imageOverflow, bytes <= budget else {
            throw ImageDecodeError.budgetExceeded
        }
        return bytes
    }
    public static func isHeavy(width: Int, height: Int) -> Bool {
        // Division avoids multiplying untrusted header dimensions.
        width > 0 && height > 0 && width > 12_000_000 / height
    }
}
