import Foundation

/// 单标的/单市场行情数据状态（与用户本地时间解耦）
enum QuoteDataStatus: Equatable, Sendable {
    /// 交易时段内的最新价，仅作盘中估值
    case intradayEstimate
    /// 已收盘但尚未拿到该交易日正式收盘价
    case awaitingOfficialClose
    /// 已取得该交易日正式收盘价
    case officialClose
    /// 场外基金：最新净值日期（非实时）
    case fundNAV
    /// 休市，展示上一交易日收盘
    case previousSessionClose
    /// 开盘前等，沿用昨收
    case preOpen
    /// 拉取失败或过期
    case stale

    var displayLabel: String {
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

    /// 是否可计入组合「最终今日收益」
    var countsTowardFinalDayPnL: Bool {
        switch self {
        case .officialClose:
            return true
        case .fundNAV:
            // 基金：仅当净值日等于「期望的最新净值日」时由 Resolver 另行判定；默认 false，由带上下文的方法决定
            return false
        default:
            return false
        }
    }
}

enum QuoteStatusResolver {
    /// 按「该市场自己的交易日/时区」判定状态；不同市场独立调用，禁止混用 now 的本地日历日。
    static func resolve(
        market: Market,
        now: Date,
        quoteMarketDate: String?,
        isOfficialClose: Bool,
        hasQuote: Bool,
        isStale: Bool = false
    ) -> QuoteDataStatus {
        if isStale || !hasQuote {
            return .stale
        }

        if market == .cnFund {
            return .fundNAV
        }

        let phase = TradingCalendar.phase(at: now, market: market)
        let today = TradingCalendar.currentMarketDateString(at: now, market: market)
        let quoteDate = quoteMarketDate ?? ""

        switch phase {
        case .fundNAVCycle:
            return .fundNAV

        case .holidayOrWeekend:
            return .previousSessionClose

        case .preOpen:
            if quoteDate == today && isOfficialClose {
                // 不应出现「今日已收盘却在开盘前」；视为昨收缓存异常时仍显示开盘前
                return .preOpen
            }
            return .preOpen

        case .trading:
            if quoteDate == today {
                return isOfficialClose ? .officialClose : .intradayEstimate
            }
            // 仍是昨日收盘价在盘中展示 → 也视为盘中估值基准不足，标盘中估值（价可能未刷新）
            return .intradayEstimate

        case .afterClose:
            if quoteDate == today && isOfficialClose {
                return .officialClose
            }
            if quoteDate == today && !isOfficialClose {
                return .awaitingOfficialClose
            }
            // 收盘后仍只有更早日期 → 等待今日收盘数据
            return .awaitingOfficialClose
        }
    }

    /// 基金：净值日若落后于最近一个潜在净值日，则不算「最终今日」
    static func fundCountsAsFinalDayPnL(
        now: Date,
        navMarketDate: String?
    ) -> Bool {
        guard let navMarketDate, !navMarketDate.isEmpty else { return false }
        let expected = latestExpectedFundNAVDate(at: now)
        return navMarketDate == expected
    }

    /// 期望的最新净值日：跳过周末，取不晚于「今天（上海）」的最近工作日。
    /// 注：真实公募常 T+1 公布，测试与产品可把「未更新当日净值」表现为 navDate < expected。
    static func latestExpectedFundNAVDate(at now: Date) -> String {
        let market = Market.cnFund
        var cursor = now
        let cal = TradingCalendar.calendar(for: market)
        for _ in 0..<10 {
            if TradingCalendar.isTradingDay(cursor, market: market) {
                return TradingCalendar.marketDateString(for: cursor, market: market)
            }
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return TradingCalendar.marketDateString(for: now, market: market)
    }

    static func countsTowardFinalDayPnL(
        status: QuoteDataStatus,
        market: Market,
        now: Date,
        quoteMarketDate: String?
    ) -> Bool {
        switch status {
        case .officialClose:
            let today = TradingCalendar.currentMarketDateString(at: now, market: market)
            return quoteMarketDate == today
        case .fundNAV:
            return fundCountsAsFinalDayPnL(now: now, navMarketDate: quoteMarketDate)
        default:
            return false
        }
    }
}
