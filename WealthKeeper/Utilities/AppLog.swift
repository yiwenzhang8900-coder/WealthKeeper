import Foundation
import OSLog

enum AppLog {
    private static let logger = Logger(subsystem: "com.yiwen.WealthKeeper", category: "app")

    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(sanitize(message), privacy: .public)")
        print("[WealthKeeper] \(sanitize(message))")
        #endif
    }

    /// Release 仅记录脱敏后的短错误类别，不含代码/金额/Token。
    static func error(_ message: String) {
        let safe = sanitize(message)
        #if DEBUG
        logger.error("\(safe, privacy: .public)")
        print("[WealthKeeper][ERROR] \(safe)")
        #else
        logger.error("\(safe, privacy: .private)")
        #endif
    }

    /// 证券代码脱敏：保留市场与末 2～3 位，如 600519 → ***519
    static func maskSymbol(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else { return "***" }
        let suffix = trimmed.suffix(3)
        return "***\(suffix)"
    }

    static func maskInstrumentID(_ id: String) -> String {
        if let idx = id.firstIndex(of: ":") {
            let market = String(id[..<idx])
            let sym = String(id[id.index(after: idx)...])
            return "\(market):\(maskSymbol(sym))"
        }
        return maskSymbol(id)
    }

    /// 去掉疑似金额、完整代码、token/key、URL query
    static func sanitize(_ raw: String) -> String {
        var text = raw
        // token / api_key / password 类
        let patterns = [
            #"(?i)(api[_-]?key|token|password|secret|authorization)\s*[=:]\s*\S+"#,
            #"(?i)Bearer\s+\S+"#,
            #"\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b"#, // 1,680.50
            #"¥\s*-?\d+(?:\.\d+)?"#,
            #"\b\d+\.\d{2,}\b"#, // 小数金额/价格（宽松）
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: "[redacted]"
                )
            }
        }
        // 常见 A/港/美代码形态（连续 5–6 位数字或全大写 ticker）
        if let regex = try? NSRegularExpression(pattern: #"\b([0-9]{5,6}|[A-Z]{1,5})\b"#) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            // 从后往前替换，避免区间错位
            for match in matches.reversed() {
                let token = ns.substring(with: match.range)
                // 保留短状态词
                let keep: Set<String> = ["CNY", "USD", "HKD", "DEBUG", "ERROR", "HTTP", "FX", "OK"]
                if keep.contains(token.uppercased()) { continue }
                if token.count >= 4 || token.allSatisfy(\.isNumber) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: maskSymbol(token))
                }
            }
        }
        return text
    }
}

enum NumberParsing {
    /// 兼容 `1,000` / `1，000` / 首尾空格
    static func double(from raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}
