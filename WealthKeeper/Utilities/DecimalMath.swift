import Foundation

enum DecimalMath {
    static let zero = Decimal(0)
    static let one = Decimal(1)

    static func parse(_ raw: String) -> Decimal? {
        var cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "．", with: ".")
            .replacingOccurrences(of: "。", with: ".") // 中文句号当小数点
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        // 全角数字转半角
        cleaned = cleaned.map { ch -> Character in
            guard let v = ch.unicodeScalars.first?.value, (0xFF10...0xFF19).contains(v) else { return ch }
            return Character(UnicodeScalar(v - 0xFF10 + 0x30)!)
        }.reduce(into: "") { $0.append($1) }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// 按实际天数 / 365：本金 × 年利率 × 天数 / 365（annualRate 为小数，如 0.015）
    static func simpleInterest(
        principal: Decimal,
        annualRate: Decimal,
        from valueDate: Date,
        to asOf: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Decimal {
        guard principal > 0, annualRate > 0 else { return 0 }
        let start = calendar.startOfDay(for: valueDate)
        let end = calendar.startOfDay(for: asOf)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        guard days > 0 else { return 0 }
        return principal * annualRate * Decimal(days) / Decimal(365)
    }

    static func plainString(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

enum NetworkProbe {
    struct Result: Sendable {
        let url: String
        let source: String
        let statusCode: Int?
        let elapsedMs: Int
        let errorKind: String?
        let detail: String?
    }

    static func get(
        url: URL,
        source: String,
        session: URLSession,
        headers: [String: String] = [:]
    ) async -> (data: Data?, probe: Result) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            // 标明本应用身份，避免伪装成 Safari/系统浏览器。
            request.setValue(
                "WealthKeeper/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (iOS; personal portfolio; local-only)",
                forHTTPHeaderField: "User-Agent"
            )
        }

        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let code = (response as? HTTPURLResponse)?.statusCode
            let probe = Result(
                url: url.absoluteString,
                source: source,
                statusCode: code,
                elapsedMs: ms,
                errorKind: (code != nil && !(200..<300).contains(code!)) ? "http" : nil,
                detail: code.map { "HTTP \($0)" }
            )
            AppLog.debug("net \(source) status=\(code ?? -1) ms=\(ms) url=\(url.host ?? "")")
            if let code, !(200..<300).contains(code) {
                AppLog.error("net \(source) http=\(code)")
                return (nil, probe)
            }
            return (data, probe)
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let kind: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut: kind = "timeout"
                case .notConnectedToInternet: kind = "offline"
                case .cannotFindHost: kind = "dns"
                case .cannotConnectToHost: kind = "connect"
                case .secureConnectionFailed: kind = "tls"
                default: kind = "urlError(\(urlError.code.rawValue))"
                }
            } else {
                kind = "unknown"
            }
            let probe = Result(
                url: url.absoluteString,
                source: source,
                statusCode: nil,
                elapsedMs: ms,
                errorKind: kind,
                detail: error.localizedDescription
            )
            AppLog.error("net \(source) fail=\(kind) ms=\(ms) host=\(url.host ?? "")")
            return (nil, probe)
        }
    }
}
