import Foundation

/// 各市场交易时区、交易日与收盘时刻（美股用系统 IANA 时区自动处理夏令时）
enum TradingCalendar {
    static func timeZoneID(for market: Market) -> String {
        switch market {
        case .cnA, .cnFund: return "Asia/Shanghai"
        case .hk: return "Asia/Hong_Kong"
        case .us: return "America/New_York"
        }
    }

    static func timeZone(for market: Market) -> TimeZone {
        TimeZone(identifier: timeZoneID(for: market)) ?? .gmt
    }

    static func calendar(for market: Market) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone(for: market)
        return cal
    }

    /// 市场本地日历日 yyyy-MM-dd
    static func marketDateString(for date: Date, market: Market) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(for: market)
        formatter.timeZone = timeZone(for: market)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseMarketDate(_ string: String, market: Market) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar(for: market)
        formatter.timeZone = timeZone(for: market)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    /// 常规或半日/提前收盘的收盘时刻（市场本地时区墙上时钟）
    static func sessionCloseDate(onMarketDate marketDate: Date, market: Market) -> Date {
        let cal = calendar(for: market)
        let ymd = cal.dateComponents([.year, .month, .day], from: marketDate)
        let close = closeClock(on: marketDate, market: market)
        var comps = ymd
        comps.hour = close.hour
        comps.minute = close.minute
        comps.second = 0
        return cal.date(from: comps) ?? marketDate
    }

    static func openClock(market: Market) -> (hour: Int, minute: Int) {
        switch market {
        case .cnA: return (9, 30)
        case .hk: return (9, 30)
        case .us: return (9, 30)
        case .cnFund: return (0, 0)
        }
    }

    static func closeClock(on marketDate: Date, market: Market) -> (hour: Int, minute: Int) {
        let key = marketDateString(for: marketDate, market: market)
        switch market {
        case .cnA:
            return (15, 0)
        case .hk:
            if hkHalfDays.contains(key) { return (12, 0) }
            return (16, 0)
        case .us:
            if usEarlyCloseDays.contains(key) { return (13, 0) }
            return (16, 0)
        case .cnFund:
            return (23, 59)
        }
    }

    static func isWeekend(_ date: Date, market: Market) -> Bool {
        let cal = calendar(for: market)
        let weekday = cal.component(.weekday, from: date) // 1=Sun ... 7=Sat
        return weekday == 1 || weekday == 7
    }

    static func isHoliday(_ date: Date, market: Market) -> Bool {
        let key = marketDateString(for: date, market: market)
        switch market {
        case .cnA, .cnFund:
            return cnHolidays.contains(key)
        case .hk:
            return hkHolidays.contains(key)
        case .us:
            return usHolidays.contains(key)
        }
    }

    static func isTradingDay(_ date: Date, market: Market) -> Bool {
        if market == .cnFund {
            // 基金净值日：非周末即可作为潜在净值日（实际以公告为准）
            return !isWeekend(date, market: market)
        }
        return !isWeekend(date, market: market) && !isHoliday(date, market: market)
    }

    /// 当前（或指定时刻）所处会话阶段——按该市场自己的时区判断
    static func phase(at now: Date, market: Market) -> MarketSessionPhase {
        if market == .cnFund {
            return .fundNAVCycle
        }
        if !isTradingDay(now, market: market) {
            return .holidayOrWeekend
        }
        let cal = calendar(for: market)
        let open = openClock(market: market)
        let close = closeClock(on: now, market: market)

        var openComps = cal.dateComponents([.year, .month, .day], from: now)
        openComps.hour = open.hour
        openComps.minute = open.minute
        openComps.second = 0

        var closeComps = cal.dateComponents([.year, .month, .day], from: now)
        closeComps.hour = close.hour
        closeComps.minute = close.minute
        closeComps.second = 0

        guard let openDate = cal.date(from: openComps),
              let closeDate = cal.date(from: closeComps) else {
            return .holidayOrWeekend
        }

        if now < openDate { return .preOpen }
        if now < closeDate { return .trading }
        return .afterClose
    }

    /// 相对 `now` 的“本市场交易日”字符串；休市日仍返回该日历日（由 phase 区分）
    static func currentMarketDateString(at now: Date, market: Market) -> String {
        marketDateString(for: now, market: market)
    }

    // MARK: - Holiday / special sessions (可扩展)

    /// 中国内地休市（节选 2025–2026）
    static let cnHolidays: Set<String> = [
        "2025-01-01", "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31", "2025-02-01", "2025-02-02", "2025-02-03", "2025-02-04",
        "2025-04-04", "2025-04-05", "2025-04-06",
        "2025-05-01", "2025-05-02", "2025-05-03", "2025-05-04", "2025-05-05",
        "2025-05-31", "2025-06-01", "2025-06-02",
        "2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08",
        "2026-01-01", "2026-01-02",
        "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
        "2026-04-04", "2026-04-05", "2026-04-06",
        "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
        "2026-06-19", "2026-06-20", "2026-06-21",
        "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07",
    ]

    static let hkHolidays: Set<String> = [
        "2025-01-01", "2025-01-29", "2025-01-30", "2025-01-31",
        "2025-04-04", "2025-04-18", "2025-04-19", "2025-04-21",
        "2025-05-01", "2025-05-05", "2025-05-31",
        "2025-07-01", "2025-10-01", "2025-10-07", "2025-10-29",
        "2025-12-25", "2025-12-26",
        "2026-01-01", "2026-02-17", "2026-02-18",
        "2026-04-03", "2026-04-04", "2026-04-06",
        "2026-05-01", "2026-05-25", "2026-06-19",
        "2026-07-01", "2026-10-01", "2026-10-19", "2026-10-26",
        "2026-12-25", "2026-12-26",
    ]

    /// 港股半日市（收盘 12:00）
    static let hkHalfDays: Set<String> = [
        "2025-01-28", "2025-12-24", "2025-12-31",
        "2026-02-16", "2026-12-24", "2026-12-31",
    ]

    static let usHolidays: Set<String> = [
        "2025-01-01", "2025-01-20", "2025-02-17", "2025-04-18",
        "2025-05-26", "2025-06-19", "2025-07-04", "2025-09-01",
        "2025-11-27", "2025-12-25",
        "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03",
        "2026-05-25", "2026-06-19", "2026-07-03", "2026-09-07",
        "2026-11-26", "2026-12-25",
    ]

    /// 美股提前收盘 13:00 ET
    static let usEarlyCloseDays: Set<String> = [
        "2025-07-03", "2025-11-28", "2025-12-24",
        "2026-11-27", "2026-12-24",
    ]
}

enum MarketSessionPhase: String, Equatable {
    case preOpen
    case trading
    case afterClose
    case holidayOrWeekend
    case fundNAVCycle
}
