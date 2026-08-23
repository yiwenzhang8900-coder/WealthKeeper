import Foundation
import SwiftUI
import SwiftData

struct AssetAllocationSlice: Identifiable {
    var id: String { assetClass.rawValue }
    let assetClass: AssetClass
    let valueCNY: Decimal
    let weight: Decimal
}

struct PnLBreakdown {
    /// 本金存取变动（不计入收益合计）
    var principalChangeCNY: Decimal
    /// 价格/估值相对成本（含债券估值差）
    var priceReturnCNY: Decimal
    /// 股票/ETF/基金的价格收益（不含分红）
    var stockReturnCNY: Decimal
    /// 利息（预计+已到账）
    var interestCNY: Decimal
    var dividendCNY: Decimal
    var feesCNY: Decimal

    /// 累计收益 = 价格 + 利息 + 分红 − 手续费（不含本金）
    var totalReturnCNY: Decimal {
        priceReturnCNY + interestCNY + dividendCNY - feesCNY
    }
}

struct ManualAssetLine: Identifiable {
    let id: String
    let assetClass: AssetClass
    let name: String
    let currency: String
    let marketValueNative: Decimal
    let marketValueCNY: Decimal
    let rateToCNY: Decimal
    let detail: String
}

struct WealthSummary {
    let totalAssetsCNY: Decimal
    let totalLiabilitiesCNY: Decimal
    let netWorthCNY: Decimal
    let allocation: [AssetAllocationSlice]
    let pnl: PnLBreakdown
    let equityAndFund: PortfolioSummary
    let manualLines: [ManualAssetLine]
    let fxSource: String
    let fxUpdatedAt: Date?
    let rateToCNYMap: [String: Decimal]

    var totalAssetsBase: Double { DecimalMath.double(totalAssetsCNY) }
    var netWorthBase: Double { DecimalMath.double(netWorthCNY) }
    var liabilitiesBase: Double { DecimalMath.double(totalLiabilitiesCNY) }

    /// 与首页「资产类别占比」同一分母：五类正资产合计（不含外币/生活结余/负债）
    var allocationBaseCNY: Decimal {
        allocation.reduce(Decimal(0)) { $0 + max($1.valueCNY, 0) }
    }

    func allocationWeight(forValueCNY valueCNY: Decimal) -> Decimal {
        let base = allocationBaseCNY
        guard base > 0 else { return 0 }
        return valueCNY / base
    }
}

// MARK: - SwiftUI 注入（详情页占比与首页「资产类别占比」对齐）

private struct WealthSummaryEnvironmentKey: EnvironmentKey {
    static let defaultValue: WealthSummary? = nil
}

extension EnvironmentValues {
    var wealthSummary: WealthSummary? {
        get { self[WealthSummaryEnvironmentKey.self] }
        set { self[WealthSummaryEnvironmentKey.self] = newValue }
    }
}

/// 向导航栈内注入最新 `WealthSummary`，供类别详情卡计算占总正资产比例。
struct InjectWealthSummaryModifier: ViewModifier {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Instrument.symbol) private var instruments: [Instrument]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]
    @Query private var deposits: [BankDepositAccount]
    @Query private var fxSavings: [FXSavingsAccount]
    @Query private var bonds: [BondHolding]
    @Query private var cashOthers: [CashOtherAsset]
    @Query private var liabilities: [LiabilityRecord]
    @Query private var capitalEvents: [ManualCapitalEvent]
    @Query private var lifestyleEntries: [LifestyleEntry]

    private var wealth: WealthSummary {
        WealthSummaryEngine.summarize(
            instruments: instruments,
            positions: positions,
            quotes: quotes,
            settings: settingsList.first ?? AppSettings(),
            deposits: deposits,
            fxSavings: fxSavings,
            bonds: bonds,
            cashOthers: cashOthers,
            liabilities: liabilities,
            capitalEvents: capitalEvents,
            lifestyleEntries: lifestyleEntries
        )
    }

    func body(content: Content) -> some View {
        content.environment(\.wealthSummary, wealth)
    }
}

extension View {
    func injectWealthSummary() -> some View {
        modifier(InjectWealthSummaryModifier())
    }
}

enum WealthSummaryEngine {
    static func summarize(
        instruments: [Instrument],
        positions: [Position],
        quotes: [CachedQuote],
        settings: AppSettings,
        deposits: [BankDepositAccount],
        fxSavings: [FXSavingsAccount],
        bonds: [BondHolding],
        cashOthers: [CashOtherAsset],
        liabilities: [LiabilityRecord],
        capitalEvents: [ManualCapitalEvent],
        lifestyleEntries: [LifestyleEntry] = [],
        now: Date = .now
    ) -> WealthSummary {
        let portfolio = PortfolioEngine.summarize(
            instruments: instruments,
            positions: positions,
            quotes: quotes,
            settings: settings,
            now: now
        )

        var classTotals: [AssetClass: Decimal] = [:]
        var manualLines: [ManualAssetLine] = []

        // —— 股票/ETF vs 基金 ——
        var equityValue = Decimal(0)
        var fundValue = Decimal(0)
        for pos in portfolio.positions {
            let instrument = instruments.first(where: { $0.id == pos.instrumentID })
            let isFund = instrument?.type == .fund || pos.market == .cnFund
            if isFund {
                fundValue += pos.marketValueCNY
            } else {
                equityValue += pos.marketValueCNY
            }
        }
        classTotals[.equity] = equityValue
        classTotals[.fund] = fundValue

        // —— 银行存款 ——
        var depositValue = Decimal(0)
        for item in deposits {
            let rate = settings.rateToCNY(for: item.currency)
            let cny = item.marketValueNative * rate
            depositValue += cny
            manualLines.append(
                ManualAssetLine(
                    id: item.id.uuidString,
                    assetClass: .bankDeposit,
                    name: item.displayTitle,
                    currency: item.currency,
                    marketValueNative: item.marketValueNative,
                    marketValueCNY: cny,
                    rateToCNY: rate,
                    detail: wealthSummaryDetail(for: item)
                )
            )
        }
        classTotals[.bankDeposit] = depositValue

        // —— 外币储蓄 ——
        var fxValue = Decimal(0)
        for item in fxSavings {
            let rate = settings.rateToCNY(for: item.currency)
            let cny = item.marketValueNative * rate
            fxValue += cny
            manualLines.append(
                ManualAssetLine(
                    id: item.id.uuidString,
                    assetClass: .fxSavings,
                    name: item.name,
                    currency: item.currency,
                    marketValueNative: item.marketValueNative,
                    marketValueCNY: cny,
                    rateToCNY: rate,
                    detail: interestDetail(rate: item.annualRate, accrued: item.accruedInterest, received: item.receivedInterest)
                )
            )
        }
        classTotals[.fxSavings] = fxValue

        // —— 债券 ——
        var bondValue = Decimal(0)
        for item in bonds {
            let rate = settings.rateToCNY(for: item.currency)
            let cny = item.valuationNative * rate
            bondValue += cny
            manualLines.append(
                ManualAssetLine(
                    id: item.id.uuidString,
                    assetClass: .bond,
                    name: item.name,
                    currency: item.currency,
                    marketValueNative: item.valuationNative,
                    marketValueCNY: cny,
                    rateToCNY: rate,
                    detail: "面值 \(MoneyFormat.compact(item.faceValue)) · 成本 \(MoneyFormat.compact(item.cost))"
                )
            )
        }
        classTotals[.bond] = bondValue

        // —— 现金/其他 ——
        var cashValue = Decimal(0)
        for item in cashOthers {
            let rate = settings.rateToCNY(for: item.currency)
            let cny = item.balance * rate
            cashValue += cny
            manualLines.append(
                ManualAssetLine(
                    id: item.id.uuidString,
                    assetClass: .cashOther,
                    name: item.name,
                    currency: item.currency,
                    marketValueNative: item.balance,
                    marketValueCNY: cny,
                    rateToCNY: rate,
                    detail: item.note.isEmpty ? "现金/其他" : item.note
                )
            )
        }
        classTotals[.cashOther] = cashValue

        // —— 生活记账结余（收入 − 支出）计入总资产 ——
        var lifestyleNet = Decimal(0)
        for item in lifestyleEntries {
            let rate = settings.rateToCNY(for: item.currency)
            lifestyleNet += item.signedAmount * rate
        }
        classTotals[.lifestyle] = lifestyleNet
        if lifestyleNet != 0 || !lifestyleEntries.isEmpty {
            manualLines.append(
                ManualAssetLine(
                    id: "lifestyle-net",
                    assetClass: .lifestyle,
                    name: "生活结余",
                    currency: "CNY",
                    marketValueNative: lifestyleNet,
                    marketValueCNY: lifestyleNet,
                    rateToCNY: 1,
                    detail: "共 \(lifestyleEntries.count) 笔生活账"
                )
            )
        }

        // —— 负债 ——
        var liabilityCNY = Decimal(0)
        for item in liabilities {
            let rate = settings.rateToCNY(for: item.currency)
            liabilityCNY += item.balance * rate
        }
        classTotals[.liability] = liabilityCNY

        // 总资产：正资产 + 生活结余（负债单独展示，不计入总资产）
        var totalAssets = Decimal(0)
        totalAssets += classTotals[.bankDeposit] ?? Decimal(0)
        totalAssets += classTotals[.bond] ?? Decimal(0)
        totalAssets += classTotals[.fund] ?? Decimal(0)
        totalAssets += classTotals[.equity] ?? Decimal(0)
        totalAssets += classTotals[.fxSavings] ?? Decimal(0)
        totalAssets += classTotals[.cashOther] ?? Decimal(0)
        totalAssets += classTotals[.lifestyle] ?? Decimal(0)

        let netWorth = totalAssets - liabilityCNY

        // 资产类别占比：正资产五类（不含外币/生活结余/负债）；分母为正资产合计，权重和为 100%
        let allocationOrder: [AssetClass] = [
            .bankDeposit, .bond, .fund, .equity, .cashOther
        ]
        let allocValues: [(AssetClass, Decimal)] = allocationOrder.map { cls in
            (cls, max(classTotals[cls] ?? 0, 0))
        }
        let positiveBase = allocValues.reduce(Decimal(0)) { $0 + $1.1 }
        let positiveIndices = allocValues.indices.filter { allocValues[$0].1 > 0 }
        var allocation: [AssetAllocationSlice] = []
        var weightRemaining = Decimal(1)
        for index in allocValues.indices {
            let cls = allocValues[index].0
            let value = allocValues[index].1
            guard value > 0, positiveBase > 0 else {
                allocation.append(AssetAllocationSlice(assetClass: cls, valueCNY: value, weight: 0))
                continue
            }
            let isLastPositive = index == positiveIndices.last
            let weight = isLastPositive ? weightRemaining : (value / positiveBase)
            if !isLastPositive {
                weightRemaining -= weight
            }
            allocation.append(AssetAllocationSlice(assetClass: cls, valueCNY: value, weight: weight))
        }

        let pnl = buildPnL(
            portfolio: portfolio,
            deposits: deposits,
            fxSavings: fxSavings,
            bonds: bonds,
            capitalEvents: capitalEvents,
            settings: settings
        )

        manualLines.sort { $0.marketValueCNY > $1.marketValueCNY }

        return WealthSummary(
            totalAssetsCNY: totalAssets,
            totalLiabilitiesCNY: liabilityCNY,
            netWorthCNY: netWorth,
            allocation: allocation,
            pnl: pnl,
            equityAndFund: portfolio,
            manualLines: manualLines,
            fxSource: settings.fxSource,
            fxUpdatedAt: settings.lastFXRefresh,
            rateToCNYMap: settings.rateToCNYMap
        )
    }

    private static func interestDetail(rate: Decimal, accrued: Decimal, received: Decimal) -> String {
        let pct = rate * 100
        return "利率 \(MoneyFormat.compact(pct, fractionDigits: 2))% · 预计利息 \(MoneyFormat.compact(accrued)) · 已到账 \(MoneyFormat.compact(received))"
    }

    private static func wealthSummaryDetail(for item: BankDepositAccount) -> String {
        switch item.depositKind {
        case .wealth:
            switch item.wealthStyle {
            case .netValue, .cashManagement:
                let pnl = item.marketValueNative - item.balance
                return "\(item.depositKind.displayName) · \(item.wealthStyle.displayName) · 净值 \(MoneyFormat.compact(item.unitNav, fractionDigits: 4)) · 浮动 \(MoneyFormat.compact(pnl, sign: true))"
            case .closed:
                return "\(item.depositKind.displayName) · \(item.wealthStyle.displayName) · \(interestDetail(rate: item.annualRate, accrued: item.displayAccruedInterest, received: item.receivedInterest))"
            }
        case .demand, .fixed:
            return "\(item.depositKind.displayName) · \(interestDetail(rate: item.annualRate, accrued: item.displayAccruedInterest, received: item.receivedInterest))"
        }
    }

    private static func buildPnL(
        portfolio: PortfolioSummary,
        deposits: [BankDepositAccount],
        fxSavings: [FXSavingsAccount],
        bonds: [BondHolding],
        capitalEvents: [ManualCapitalEvent],
        settings: AppSettings
    ) -> PnLBreakdown {
        // 股基：浮动 = 价格收益；分红/手续费沿用；已实现中的卖出盈亏并入价格收益
        // 简化：priceReturn = 浮动 + (已实现 − 分红) 的已实现卖出部分
        // 现有 realized 已含分红，故：
        // priceReturn ≈ unrealized + (realized − dividends 中已计入 realized 的部分)
        // 为避免双计，采用：
        //   priceReturn = unrealizedPnL + (realizedPnL − dividends) 当 realized 含分红时
        // 查看 PortfolioEngine：dividend 时 realized += cash，所以 realized 含分红。
        let priceFromTrading = portfolio.unrealizedPnLCNY + (portfolio.realizedPnLCNY - portfolio.dividendsCNY)
        let dividend = portfolio.dividendsCNY
        let fees = portfolio.feesCNY

        var interest = Decimal(0)
        for d in deposits {
            let rate = settings.rateToCNY(for: d.currency)
            switch d.depositKind {
            case .wealth:
                switch d.wealthStyle {
                case .netValue, .cashManagement:
                    interest += (d.marketValueNative - d.balance + d.receivedInterest) * rate
                case .closed:
                    interest += (d.displayAccruedInterest + d.receivedInterest) * rate
                }
            case .demand, .fixed:
                interest += (d.displayAccruedInterest + d.receivedInterest) * rate
            }
        }
        for f in fxSavings {
            let rate = settings.rateToCNY(for: f.currency)
            interest += (f.accruedInterest + f.receivedInterest) * rate
        }
        for b in bonds {
            let rate = settings.rateToCNY(for: b.currency)
            interest += (b.accruedInterest + b.receivedInterest) * rate
        }

        var bondPrice = Decimal(0)
        for b in bonds {
            let rate = settings.rateToCNY(for: b.currency)
            let mv = b.marketValue ?? b.cost
            bondPrice += (mv - b.cost) * rate
        }

        var principal = Decimal(0)
        for ev in capitalEvents {
            let rate = settings.rateToCNY(for: ev.currency)
            let signed: Decimal
            switch ev.kind {
            case .deposit, .adjustPrincipal:
                signed = ev.amount
            case .withdraw, .maturityRedeem:
                signed = -ev.amount
            case .interestReceived:
                // 利息到账已体现在 interest / receivedInterest，这里不重复计入本金变化
                continue
            }
            principal += signed * rate
        }

        // 若用户未记流水，用「当前本金余额」不作为收益；principal 仅来自流水
        // 存款余额本身不是收益

        return PnLBreakdown(
            principalChangeCNY: principal,
            priceReturnCNY: priceFromTrading + bondPrice,
            stockReturnCNY: priceFromTrading,
            interestCNY: interest,
            dividendCNY: dividend,
            feesCNY: fees
        )
    }
}
