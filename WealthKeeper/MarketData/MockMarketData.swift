import Foundation
import SwiftData

/// 模拟器或网络不可用时的本地 Mock，便于验证 UI 与计算流程（不含真实持仓隐私）
enum MockMarketData {
    static let searchCatalog: [InstrumentSearchHit] = [
        .init(id: "CN_A:600519", symbol: "600519", name: "贵州茅台", market: .cnA, currency: "CNY", assetType: .stock, securityTypeName: "沪A"),
        .init(id: "CN_A:000001", symbol: "000001", name: "平安银行", market: .cnA, currency: "CNY", assetType: .stock, securityTypeName: "深A"),
        .init(id: "HK:00700", symbol: "00700", name: "腾讯控股", market: .hk, currency: "HKD", assetType: .stock, securityTypeName: "港股"),
        .init(id: "US:AAPL", symbol: "AAPL", name: "苹果", market: .us, currency: "USD", assetType: .stock, securityTypeName: "美股"),
        .init(id: "US:MSFT", symbol: "MSFT", name: "微软", market: .us, currency: "USD", assetType: .stock, securityTypeName: "美股"),
        .init(id: "CN_FUND:110022", symbol: "110022", name: "易方达消费行业股票", market: .cnFund, currency: "CNY", assetType: .fund, securityTypeName: "基金"),
        .init(id: "CN_A:510300", symbol: "510300", name: "沪深300ETF华泰柏瑞", market: .cnA, currency: "CNY", assetType: .etf, securityTypeName: "ETF"),
    ]

    static func search(query: String) -> [InstrumentSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let upper = q.uppercased()
        let digits = String(q.filter(\.isNumber))

        let hits = searchCatalog.filter { hit in
            hit.symbol.uppercased().contains(upper)
                || hit.name.contains(q)
                || (!digits.isEmpty && hit.symbol.contains(digits))
                || (hit.market == .hk && !digits.isEmpty && hit.symbol.hasSuffix(digits))
        }
        return InstrumentSearchService.rank(hits, query: q)
    }

    /// Mock 分红事件：便于离线验收「本地 → 远程 → 手填」链路
    static func sampleDividends(for instrument: InstrumentDTO, now: Date = .now) -> [RemoteCorporateAction] {
        let cal = Calendar(identifier: .gregorian)
        let record = cal.date(byAdding: .day, value: -32, to: now) ?? now
        let ex = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let perShare: Decimal = {
            switch instrument.market {
            case .cnA:
                // 模拟「10 派 2.5」→ 每股 0.25
                return Decimal(string: "0.25")!
            case .cnFund:
                return Decimal(string: "0.012")!
            case .hk:
                return Decimal(string: "0.40")!
            case .us:
                return Decimal(string: "0.24")!
            }
        }()
        return [
            RemoteCorporateAction(
                instrumentID: instrument.id,
                kind: .dividend,
                exDate: ex,
                value: perShare,
                currency: instrument.currency,
                source: "mock-div",
                recordDate: record,
                settlement: .cash
            )
        ]
    }

    static func quote(for instrument: InstrumentDTO, now: Date = .now) -> DailyQuote {
        let seed: Double = {
            switch instrument.symbol.uppercased() {
            case "600519": return 1680
            case "000001": return 11.5
            case "00700", "0700": return 380
            case "AAPL": return 190
            case "MSFT": return 420
            case "110022": return 3.15
            case "510300": return 4.2
            default:
                let hash = abs(instrument.symbol.hashValue % 500)
                return 50 + Double(hash) / 10
            }
        }()
        let prev = seed * 0.99
        let ts: Date
        let official: Bool
        if instrument.market == .cnFund {
            let cal = TradingCalendar.calendar(for: .cnFund)
            // 模拟「最新净值日」为上一工作日，便于验证非实时净值
            var cursor = cal.date(byAdding: .day, value: -1, to: now) ?? now
            while TradingCalendar.isWeekend(cursor, market: .cnFund) {
                cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            }
            ts = cursor
            official = true
        } else {
            ts = now
            official = TradingCalendar.phase(at: now, market: instrument.market) == .afterClose
        }

        return QuoteMetadataBuilder.make(
            instrumentID: instrument.id,
            symbol: instrument.symbol,
            market: instrument.market,
            closeOrNAV: Decimal(seed),
            previousClose: Decimal(prev),
            currency: instrument.currency,
            quoteTimestamp: ts,
            now: now,
            forceOfficialClose: instrument.market == .cnFund ? true : official
        )
    }

    static func fxRates(toBase base: String) -> [String: Double] {
        var rates = [base: 1.0]
        if base == "CNY" {
            rates["USD"] = 7.2
            rates["HKD"] = 0.92
        } else if base == "USD" {
            rates["CNY"] = 1 / 7.2
            rates["HKD"] = 0.128
        } else {
            rates["CNY"] = 1 / 0.92
            rates["USD"] = 7.8
        }
        return rates
    }

    /// 仅首次植入演示用手动资产（可删）；不覆盖用户数据
    @MainActor
    static func seedManualAssetsIfNeeded(context: ModelContext) {
        if UserDefaults.standard.bool(forKey: LocalDataMaintenance.skipDemoSeedKey) {
            return
        }
        let key = "wk_manual_assets_seeded_v1"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }

        let existingDeposits = (try? context.fetch(FetchDescriptor<BankDepositAccount>())) ?? []
        let existingCash = (try? context.fetch(FetchDescriptor<CashOtherAsset>())) ?? []
        guard existingDeposits.isEmpty && existingCash.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        let deposit = BankDepositAccount(
            name: "示例·招商银行",
            balance: Decimal(string: "50000")!,
            currency: "CNY",
            annualRate: Decimal(string: "0.015")!,
            valueDate: Calendar.current.date(byAdding: .month, value: -1, to: .now),
            maturityDate: Calendar.current.date(byAdding: .month, value: 11, to: .now),
            accruedInterest: Decimal(string: "62.50")!,
            receivedInterest: 0,
            depositKind: .fixed,
            note: "Mock 示例，可删除"
        )
        let demand = BankDepositAccount(
            name: "示例·工商银行",
            balance: Decimal(string: "8000")!,
            currency: "CNY",
            annualRate: Decimal(string: "0.002")!,
            accruedInterest: Decimal(string: "1.20")!,
            depositKind: .demand,
            note: "Mock 活期示例"
        )
        let wealth = BankDepositAccount(
            name: "示例·招商银行",
            balance: Decimal(string: "20000")!,
            currency: "CNY",
            annualRate: Decimal(string: "0.025")!,
            depositKind: .wealth,
            productName: "朝朝宝",
            wealthStyle: .cashManagement,
            riskLevel: .r1,
            unitNav: Decimal(string: "1.0025")!,
            note: "Mock 现金管理类理财"
        )
        let usd = FXSavingsAccount(
            name: "示例·美元储蓄",
            balance: Decimal(string: "2000")!,
            currency: "USD",
            annualRate: Decimal(string: "0.04")!,
            accruedInterest: Decimal(string: "5")!,
            note: "Mock 示例"
        )
        let bond = BondHolding(
            name: "示例·国债",
            currency: "CNY",
            faceValue: Decimal(string: "10000")!,
            cost: Decimal(string: "9800")!,
            couponRate: Decimal(string: "0.028")!,
            purchaseDate: Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now,
            valueDate: Calendar.current.date(byAdding: .month, value: -6, to: .now),
            maturityDate: Calendar.current.date(byAdding: .year, value: 2, to: .now),
            expectedRedemptionDate: Calendar.current.date(byAdding: .year, value: 2, to: .now),
            couponFrequency: .annual,
            marketValue: Decimal(string: "9950")!,
            note: "Mock 示例"
        )
        let cash = CashOtherAsset(name: "示例·现金钱包", balance: Decimal(string: "3000")!, currency: "CNY", kind: .cash)
        let debt = LiabilityRecord(name: "示例·信用卡", balance: Decimal(string: "1500")!, currency: "CNY")

        context.insert(deposit)
        context.insert(demand)
        context.insert(wealth)
        context.insert(usd)
        context.insert(bond)
        context.insert(cash)
        context.insert(debt)
        context.insert(ManualCapitalEvent(
            assetID: deposit.id, assetClass: .bankDeposit, kind: .deposit,
            amount: deposit.balance, currency: "CNY", note: "示例本金"
        ))
        context.insert(ManualCapitalEvent(
            assetID: usd.id, assetClass: .fxSavings, kind: .deposit,
            amount: usd.balance, currency: "USD", note: "示例本金"
        ))
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
        AppLog.debug("seeded mock manual assets")
    }
}
