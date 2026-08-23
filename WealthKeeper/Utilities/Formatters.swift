import Foundation

enum MoneyFormat {
    static func amount(_ value: Decimal, currency: String = "CNY", sign: Bool = false) -> String {
        amount(DecimalMath.double(value), currency: currency, sign: sign)
    }

    static func amount(_ value: Double, currency: String = "CNY", sign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        if sign { formatter.positivePrefix = "+" }
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(currency) \(number)"
    }

    static func compact(_ value: Decimal, sign: Bool = false, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = fractionDigits
        if sign { formatter.positivePrefix = "+" }
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func compact(_ value: Double, sign: Bool = false) -> String {
        compact(Decimal(value), sign: sign)
    }

    /// 基金/ETF 单位净值：固定三位小数
    static func nav(_ value: Decimal, sign: Bool = false) -> String {
        compact(value, sign: sign, fractionDigits: 3)
    }

    static func nav(_ value: Double, sign: Bool = false) -> String {
        nav(Decimal(value), sign: sign)
    }

    /// 股价用 2 位，基金/ETF 净值用 3 位
    static func quotePrice(_ value: Decimal, instrumentType: InstrumentType, market: Market) -> String {
        if market == .cnFund || instrumentType == .fund || instrumentType == .etf {
            return nav(value)
        }
        return compact(value)
    }

    static func quantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func quantity(_ value: Double) -> String {
        quantity(Decimal(value))
    }

    static func rateToCNY(_ value: Decimal) -> String {
        compact(value, sign: false, fractionDigits: 4)
    }

    static func fxLine(code: String, rateToCNY: Decimal) -> String {
        "1 \(code) = \(Self.rateToCNY(rateToCNY)) CNY"
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// 小数利率转百分比展示，如 0.12 → "12%"；已是百分数时可传 asFraction: false
    static func percent(_ value: Decimal, fractionDigits: Int = 2, asFraction: Bool = true) -> String {
        let pct = asFraction ? value * 100 : value
        return "\(compact(pct, fractionDigits: fractionDigits))%"
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
