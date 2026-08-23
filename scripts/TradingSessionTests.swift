#!/usr/bin/env swift
/**
 可重复运行的多市场收盘/状态测试。
 用法: swift scripts/TradingSessionTests.swift
 或:   ./scripts/run_trading_session_tests.sh
 */

import Foundation

// MARK: - Minimal copies aligned with app (keep in sync with MarketEnums / TradingCalendar / QuoteStatus)

enum Market: String {
    case cnA = "CN_A"
    case hk = "HK"
    case us = "US"
    case cnFund = "CN_FUND"
}

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

    static func marketDateString(for date: Date, market: Market) -> String {
        let f = DateFormatter()
        f.calendar = calendar(for: market)
        f.timeZone = timeZone(for: market)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static let cnHolidays: Set<String> = [
        "2026-01-01", "2026-01-02",
        "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
        "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07",
    ]
    static let hkHolidays: Set<String> = [
        "2026-01-01", "2026-02-17", "2026-02-18", "2026-07-01", "2026-10-01", "2026-12-25", "2026-12-26",
    ]
    static let hkHalfDays: Set<String> = ["2026-02-16", "2026-12-24", "2026-12-31"]
    static let usHolidays: Set<String> = [
        "2026-01-01", "2026-01-19", "2026-02-16", "2026-05-25", "2026-06-19", "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
    ]
    static let usEarlyCloseDays: Set<String> = ["2026-11-27", "2026-12-24"]

    static func isWeekend(_ date: Date, market: Market) -> Bool {
        let w = calendar(for: market).component(.weekday, from: date)
        return w == 1 || w == 7
    }

    static func isHoliday(_ date: Date, market: Market) -> Bool {
        let key = marketDateString(for: date, market: market)
        switch market {
        case .cnA, .cnFund: return cnHolidays.contains(key)
        case .hk: return hkHolidays.contains(key)
        case .us: return usHolidays.contains(key)
        }
    }

    static func isTradingDay(_ date: Date, market: Market) -> Bool {
        if market == .cnFund { return !isWeekend(date, market: market) }
        return !isWeekend(date, market: market) && !isHoliday(date, market: market)
    }

    static func closeClock(on marketDate: Date, market: Market) -> (Int, Int) {
        let key = marketDateString(for: marketDate, market: market)
        switch market {
        case .cnA: return (15, 0)
        case .hk: return hkHalfDays.contains(key) ? (12, 0) : (16, 0)
        case .us: return usEarlyCloseDays.contains(key) ? (13, 0) : (16, 0)
        case .cnFund: return (23, 59)
        }
    }

    static func openClock(market: Market) -> (Int, Int) {
        switch market {
        case .cnFund: return (0, 0)
        default: return (9, 30)
        }
    }

    enum Phase: String { case preOpen, trading, afterClose, holidayOrWeekend, fundNAVCycle }

    static func phase(at now: Date, market: Market) -> Phase {
        if market == .cnFund { return .fundNAVCycle }
        if !isTradingDay(now, market: market) { return .holidayOrWeekend }
        let cal = calendar(for: market)
        let open = openClock(market: market)
        let close = closeClock(on: now, market: market)
        var oc = cal.dateComponents([.year, .month, .day], from: now)
        oc.hour = open.0; oc.minute = open.1; oc.second = 0
        var cc = cal.dateComponents([.year, .month, .day], from: now)
        cc.hour = close.0; cc.minute = close.1; cc.second = 0
        let openDate = cal.date(from: oc)!
        let closeDate = cal.date(from: cc)!
        if now < openDate { return .preOpen }
        if now < closeDate { return .trading }
        return .afterClose
    }

    static func currentMarketDateString(at now: Date, market: Market) -> String {
        marketDateString(for: now, market: market)
    }

    static func date(market: Market, ymd: String, hour: Int, minute: Int) -> Date {
        let f = DateFormatter()
        f.calendar = calendar(for: market)
        f.timeZone = timeZone(for: market)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: "\(ymd) \(String(format: "%02d:%02d:00", hour, minute))")!
    }
}

enum QuoteDataStatus: Equatable {
    case intradayEstimate, awaitingOfficialClose, officialClose, fundNAV, previousSessionClose, preOpen, stale
    var label: String {
        switch self {
        case .intradayEstimate: return "盘中估值"
        case .awaitingOfficialClose: return "等待收盘数据"
        case .officialClose: return "正式收盘"
        case .fundNAV: return "基金净值"
        case .previousSessionClose: return "休市·昨收"
        case .preOpen: return "开盘前"
        case .stale: return "数据陈旧"
        }
    }
}

enum QuoteStatusResolver {
    static func resolve(
        market: Market,
        now: Date,
        quoteMarketDate: String?,
        isOfficialClose: Bool,
        hasQuote: Bool,
        isStale: Bool = false
    ) -> QuoteDataStatus {
        if isStale || !hasQuote { return .stale }
        if market == .cnFund { return .fundNAV }
        let phase = TradingCalendar.phase(at: now, market: market)
        let today = TradingCalendar.currentMarketDateString(at: now, market: market)
        let quoteDate = quoteMarketDate ?? ""
        switch phase {
        case .fundNAVCycle: return .fundNAV
        case .holidayOrWeekend: return .previousSessionClose
        case .preOpen: return .preOpen
        case .trading:
            if quoteDate == today { return isOfficialClose ? .officialClose : .intradayEstimate }
            return .intradayEstimate
        case .afterClose:
            if quoteDate == today && isOfficialClose { return .officialClose }
            return .awaitingOfficialClose
        }
    }

    static func latestExpectedFundNAVDate(at now: Date) -> String {
        var cursor = now
        let cal = TradingCalendar.calendar(for: .cnFund)
        for _ in 0..<10 {
            if TradingCalendar.isTradingDay(cursor, market: .cnFund) {
                return TradingCalendar.marketDateString(for: cursor, market: .cnFund)
            }
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return TradingCalendar.marketDateString(for: now, market: .cnFund)
    }

    static func countsTowardFinalDayPnL(
        status: QuoteDataStatus,
        market: Market,
        now: Date,
        quoteMarketDate: String?
    ) -> Bool {
        switch status {
        case .officialClose:
            return quoteMarketDate == TradingCalendar.currentMarketDateString(at: now, market: market)
        case .fundNAV:
            guard let quoteMarketDate else { return false }
            return quoteMarketDate == latestExpectedFundNAVDate(at: now)
        default:
            return false
        }
    }
}

// MARK: - Test harness

var passed = 0
var failed = 0

func expect(_ name: String, _ cond: @autoclosure () -> Bool, _ detail: @autoclosure () -> String = "") {
    if cond() {
        passed += 1
        print("PASS  \(name)")
    } else {
        failed += 1
        let d = detail()
        print("FAIL  \(name)\(d.isEmpty ? "" : " — \(d)")")
    }
}

// 1) A股盘中
do {
    let now = TradingCalendar.date(market: .cnA, ymd: "2026-08-12", hour: 10, minute: 30)
    expect("A股盘中 phase=trading", TradingCalendar.phase(at: now, market: .cnA) == .trading)
    let status = QuoteStatusResolver.resolve(
        market: .cnA, now: now, quoteMarketDate: "2026-08-12", isOfficialClose: false, hasQuote: true
    )
    expect("A股盘中 status=盘中估值", status == .intradayEstimate, status.label)
    expect(
        "A股盘中 不计入最终今日",
        !QuoteStatusResolver.countsTowardFinalDayPnL(status: status, market: .cnA, now: now, quoteMarketDate: "2026-08-12")
    )
}

// 2) A股收盘后 + 已有正式收盘
do {
    let now = TradingCalendar.date(market: .cnA, ymd: "2026-08-12", hour: 15, minute: 30)
    expect("A股收盘后 phase=afterClose", TradingCalendar.phase(at: now, market: .cnA) == .afterClose)
    let status = QuoteStatusResolver.resolve(
        market: .cnA, now: now, quoteMarketDate: "2026-08-12", isOfficialClose: true, hasQuote: true
    )
    expect("A股收盘后 status=正式收盘", status == .officialClose, status.label)
    expect(
        "A股收盘后 计入最终今日",
        QuoteStatusResolver.countsTowardFinalDayPnL(status: status, market: .cnA, now: now, quoteMarketDate: "2026-08-12")
    )
}

// 2b) A股收盘后尚未取得今日收盘
do {
    let now = TradingCalendar.date(market: .cnA, ymd: "2026-08-12", hour: 15, minute: 30)
    let status = QuoteStatusResolver.resolve(
        market: .cnA, now: now, quoteMarketDate: "2026-08-11", isOfficialClose: true, hasQuote: true
    )
    expect("A股收盘后无今日数据=等待收盘数据", status == .awaitingOfficialClose, status.label)
    expect(
        "A股等待中 不计入最终今日",
        !QuoteStatusResolver.countsTowardFinalDayPnL(status: status, market: .cnA, now: now, quoteMarketDate: "2026-08-11")
    )
}

// 3) 港股盘中
do {
    let now = TradingCalendar.date(market: .hk, ymd: "2026-08-12", hour: 11, minute: 0)
    expect("港股盘中 phase=trading", TradingCalendar.phase(at: now, market: .hk) == .trading)
    let status = QuoteStatusResolver.resolve(
        market: .hk, now: now, quoteMarketDate: "2026-08-12", isOfficialClose: false, hasQuote: true
    )
    expect("港股盘中 status=盘中估值", status == .intradayEstimate, status.label)
}

// 4) 港股收盘后
do {
    let now = TradingCalendar.date(market: .hk, ymd: "2026-08-12", hour: 16, minute: 30)
    expect("港股收盘后 phase=afterClose", TradingCalendar.phase(at: now, market: .hk) == .afterClose)
    let status = QuoteStatusResolver.resolve(
        market: .hk, now: now, quoteMarketDate: "2026-08-12", isOfficialClose: true, hasQuote: true
    )
    expect("港股收盘后 status=正式收盘", status == .officialClose, status.label)
}

// 4b) 港股半日市 12:00 收盘
do {
    let before = TradingCalendar.date(market: .hk, ymd: "2026-12-24", hour: 11, minute: 0)
    let after = TradingCalendar.date(market: .hk, ymd: "2026-12-24", hour: 12, minute: 30)
    expect("港股半日市 11:00 仍交易", TradingCalendar.phase(at: before, market: .hk) == .trading)
    expect("港股半日市 12:30 已收盘", TradingCalendar.phase(at: after, market: .hk) == .afterClose)
}

// 5) 美股盘中（夏令时 EDT）
do {
    let now = TradingCalendar.date(market: .us, ymd: "2026-08-12", hour: 11, minute: 0)
    expect("美股夏令时盘中 phase=trading", TradingCalendar.phase(at: now, market: .us) == .trading)
    let status = QuoteStatusResolver.resolve(
        market: .us, now: now, quoteMarketDate: "2026-08-12", isOfficialClose: false, hasQuote: true
    )
    expect("美股盘中 status=盘中估值", status == .intradayEstimate, status.label)
}

// 6) 美股收盘后 + 夏令时验证
do {
    let closeEDT = TradingCalendar.date(market: .us, ymd: "2026-08-12", hour: 16, minute: 0)
    let afterEDT = TradingCalendar.date(market: .us, ymd: "2026-08-12", hour: 16, minute: 1)
    expect("美股夏令时 16:00 为收盘边界后", TradingCalendar.phase(at: afterEDT, market: .us) == .afterClose)
    // EDT = UTC-4 → 16:00 EDT = 20:00 UTC
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let hourUTC = utc.component(.hour, from: closeEDT)
    expect("美股夏令时 16:00 ET == 20:00 UTC", hourUTC == 20, "got hourUTC=\(hourUTC)")

    let status = QuoteStatusResolver.resolve(
        market: .us, now: afterEDT, quoteMarketDate: "2026-08-12", isOfficialClose: true, hasQuote: true
    )
    expect("美股收盘后 status=正式收盘", status == .officialClose, status.label)
}

// 6b) 美股冬令时 EST：16:00 ET = 21:00 UTC
do {
    let closeEST = TradingCalendar.date(market: .us, ymd: "2026-01-15", hour: 16, minute: 0)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let hourUTC = utc.component(.hour, from: closeEST)
    expect("美股冬令时 16:00 ET == 21:00 UTC", hourUTC == 21, "got hourUTC=\(hourUTC)")
    let after = TradingCalendar.date(market: .us, ymd: "2026-01-15", hour: 16, minute: 5)
    expect("美股冬令时收盘后 phase=afterClose", TradingCalendar.phase(at: after, market: .us) == .afterClose)
}

// 6c) 美股提前收盘
do {
    let before = TradingCalendar.date(market: .us, ymd: "2026-12-24", hour: 12, minute: 0)
    let after = TradingCalendar.date(market: .us, ymd: "2026-12-24", hour: 13, minute: 5)
    expect("美股提前收盘前仍交易", TradingCalendar.phase(at: before, market: .us) == .trading)
    expect("美股提前收盘后 afterClose", TradingCalendar.phase(at: after, market: .us) == .afterClose)
}

// 7) 周末或节假日
do {
    let sunday = TradingCalendar.date(market: .cnA, ymd: "2026-08-09", hour: 12, minute: 0)
    expect("A股周日 holidayOrWeekend", TradingCalendar.phase(at: sunday, market: .cnA) == .holidayOrWeekend)
    let status = QuoteStatusResolver.resolve(
        market: .cnA, now: sunday, quoteMarketDate: "2026-08-07", isOfficialClose: true, hasQuote: true
    )
    expect("周末 status=休市·昨收", status == .previousSessionClose, status.label)
    expect(
        "周末 不计入最终今日",
        !QuoteStatusResolver.countsTowardFinalDayPnL(status: status, market: .cnA, now: sunday, quoteMarketDate: "2026-08-07")
    )

    let cnHoliday = TradingCalendar.date(market: .cnA, ymd: "2026-10-01", hour: 12, minute: 0)
    expect("国庆休市", TradingCalendar.phase(at: cnHoliday, market: .cnA) == .holidayOrWeekend)
}

// 8) 基金：最新净值日落后于期望日 → 非最终今日；等于期望日 → 可计最终
do {
    let now = TradingCalendar.date(market: .cnFund, ymd: "2026-08-12", hour: 20, minute: 0)
    let expected = QuoteStatusResolver.latestExpectedFundNAVDate(at: now)
    expect("基金期望净值日为工作日", expected == "2026-08-12", "got \(expected)")

    let staleNAV = QuoteStatusResolver.resolve(
        market: .cnFund, now: now, quoteMarketDate: "2026-08-11", isOfficialClose: true, hasQuote: true
    )
    expect("基金状态始终为净值（非实时）", staleNAV == .fundNAV, staleNAV.label)
    expect(
        "基金净值未更新当日 不计入最终今日",
        !QuoteStatusResolver.countsTowardFinalDayPnL(status: staleNAV, market: .cnFund, now: now, quoteMarketDate: "2026-08-11")
    )

    let fresh = QuoteStatusResolver.resolve(
        market: .cnFund, now: now, quoteMarketDate: "2026-08-12", isOfficialClose: true, hasQuote: true
    )
    expect(
        "基金净值已更新当日 计入最终今日",
        QuoteStatusResolver.countsTowardFinalDayPnL(status: fresh, market: .cnFund, now: now, quoteMarketDate: "2026-08-12")
    )
}

// 9) 不同市场不要混用：同一 UTC 瞬间，A 已收盘、美股可能仍在交易
do {
    // 2026-08-12 15:30 上海 = 03:30 New York（美股未开盘）
    let shanghaiAfter = TradingCalendar.date(market: .cnA, ymd: "2026-08-12", hour: 15, minute: 30)
    expect("同时刻 A股 afterClose", TradingCalendar.phase(at: shanghaiAfter, market: .cnA) == .afterClose)
    expect("同时刻 美股 preOpen/非trading", TradingCalendar.phase(at: shanghaiAfter, market: .us) != .trading)
    expect("同时刻 美股为 preOpen", TradingCalendar.phase(at: shanghaiAfter, market: .us) == .preOpen)
}

print("\n——")
print("Result: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
