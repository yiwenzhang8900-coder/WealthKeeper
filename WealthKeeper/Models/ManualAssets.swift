import Foundation
import SwiftData

/// 银行存款 / 银行理财（手动，不接银行接口；分活期 / 定期 / 理财）
@Model
final class BankDepositAccount {
    @Attribute(.unique) var id: UUID
    /// 银行名称，如「招商银行」
    var name: String
    /// 理财产品名称；活期/定期可空
    var productName: String
    var balance: Decimal
    var currency: String
    /// 年利率或理财业绩比较基准 / 预期年化，如 0.015 = 1.5%
    var annualRate: Decimal
    var valueDate: Date?
    var maturityDate: Date?
    /// 预计赎回到账日（可空；无固定期限产品可不填）
    var expectedRedemptionDate: Date?
    /// 预计未到账利息 / 浮动收益估算
    var accruedInterest: Decimal
    /// 已到账利息或已兑付收益
    var receivedInterest: Decimal
    /// demand / fixed / wealth
    var depositKindRaw: String
    /// 理财：净值型 / 封闭式 / 现金管理
    var wealthStyleRaw: String
    /// 理财风险等级 r1…r5
    var riskLevelRaw: String
    /// 理财当前单位净值（相对申购成本，默认 1）
    var unitNav: Decimal
    var note: String
    var updatedAt: Date
    var createdAt: Date

    init(
        name: String,
        balance: Decimal,
        currency: String = "CNY",
        annualRate: Decimal = 0,
        valueDate: Date? = nil,
        maturityDate: Date? = nil,
        expectedRedemptionDate: Date? = nil,
        accruedInterest: Decimal = 0,
        receivedInterest: Decimal = 0,
        depositKind: BankDepositKind = .demand,
        productName: String = "",
        wealthStyle: BankWealthStyle = .netValue,
        riskLevel: BankWealthRiskLevel = .r2,
        unitNav: Decimal = 1,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.productName = productName
        self.balance = balance
        self.currency = currency.uppercased()
        self.annualRate = annualRate
        self.valueDate = valueDate
        self.maturityDate = maturityDate
        self.expectedRedemptionDate = expectedRedemptionDate
        self.accruedInterest = accruedInterest
        self.receivedInterest = receivedInterest
        self.depositKindRaw = depositKind.rawValue
        self.wealthStyleRaw = wealthStyle.rawValue
        self.riskLevelRaw = riskLevel.rawValue
        self.unitNav = unitNav
        self.note = note
        self.updatedAt = .now
        self.createdAt = .now
    }

    var depositKind: BankDepositKind {
        get {
            if let kind = BankDepositKind(rawValue: depositKindRaw) { return kind }
            return maturityDate != nil ? .fixed : .demand
        }
        set { depositKindRaw = newValue.rawValue }
    }

    var wealthStyle: BankWealthStyle {
        get { BankWealthStyle(rawValue: wealthStyleRaw) ?? .netValue }
        set { wealthStyleRaw = newValue.rawValue }
    }

    var riskLevel: BankWealthRiskLevel {
        get { BankWealthRiskLevel(rawValue: riskLevelRaw) ?? .r2 }
        set { riskLevelRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let product = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if depositKind == .wealth, !product.isEmpty { return product }
        return name
    }

    /// 预计赎回到账日展示：未设置时显示「未设置」，不编造日期。
    var expectedRedemptionDateText: String {
        guard let expectedRedemptionDate else { return "未设置" }
        return MoneyFormat.shortDate(expectedRedemptionDate)
    }

    /// 是否已到预计赎回到账日且仍有持仓（用于提醒确认到账）
    func isExpectedRedemptionDue(asOf: Date = .now, calendar: Calendar = .current) -> Bool {
        guard depositKind == .wealth, balance > 0 else { return false }
        guard let expected = expectedRedemptionDate else { return false }
        return calendar.startOfDay(for: expected) <= calendar.startOfDay(for: asOf)
    }

    /// 封闭式理财 / 定期：按起息→到期估算利息；理财也可按起息→预计到账日估算（日期或利率缺失则不估算）。
    func estimatedMaturityInterest(calendar: Calendar = Calendar(identifier: .gregorian)) -> Decimal? {
        guard depositKind == .fixed || depositKind == .wealth else { return nil }
        guard let valueDate else { return nil }
        let endDate: Date?
        if let maturityDate {
            endDate = maturityDate
        } else if depositKind == .wealth {
            endDate = expectedRedemptionDate
        } else {
            endDate = nil
        }
        guard let endDate else { return nil }
        guard balance > 0, annualRate > 0 else { return nil }
        return DecimalMath.simpleInterest(
            principal: balance,
            annualRate: annualRate,
            from: valueDate,
            to: endDate,
            calendar: calendar
        )
    }

    var displayAccruedInterest: Decimal {
        estimatedMaturityInterest() ?? accruedInterest
    }

    /// 起息日至今日（不超过到期日）应计利息；缺日期或利率时返回 nil。
    func accruedInterestToDate(
        asOf: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Decimal? {
        guard depositKind == .fixed else { return nil }
        guard let valueDate, balance > 0, annualRate > 0 else { return nil }
        var end = calendar.startOfDay(for: asOf)
        if let maturityDate {
            let maturity = calendar.startOfDay(for: maturityDate)
            if end > maturity { end = maturity }
        }
        return DecimalMath.simpleInterest(
            principal: balance,
            annualRate: annualRate,
            from: valueDate,
            to: end,
            calendar: calendar
        )
    }

    /// 存期（起息→到期）文案
    func depositTermDescription(
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        guard let valueDate, let maturityDate else { return "未设置" }
        let start = calendar.startOfDay(for: valueDate)
        let end = calendar.startOfDay(for: maturityDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        guard days > 0 else { return "—" }
        if days < 30 { return "\(days)天" }
        let years = days / 365
        let remDays = days % 365
        let months = remDays / 30
        if years >= 1 {
            if months == 0 { return "约\(years)年" }
            return "约\(years)年\(months)个月"
        }
        if months >= 1 { return "约\(months)个月" }
        return "\(days)天"
    }

    /// 市值原币
    var marketValueNative: Decimal {
        switch depositKind {
        case .demand:
            return balance + displayAccruedInterest
        case .fixed:
            return balance + displayAccruedInterest
        case .wealth:
            switch wealthStyle {
            case .netValue, .cashManagement:
                let nav = unitNav > 0 ? unitNav : 1
                return balance * nav
            case .closed:
                return balance + displayAccruedInterest
            }
        }
    }
}

/// 外币储蓄（手动）
@Model
final class FXSavingsAccount {
    @Attribute(.unique) var id: UUID
    var name: String
    var balance: Decimal
    var currency: String
    var annualRate: Decimal
    var valueDate: Date?
    var maturityDate: Date?
    var accruedInterest: Decimal
    var receivedInterest: Decimal
    var note: String
    var updatedAt: Date
    var createdAt: Date

    init(
        name: String,
        balance: Decimal,
        currency: String,
        annualRate: Decimal = 0,
        valueDate: Date? = nil,
        maturityDate: Date? = nil,
        accruedInterest: Decimal = 0,
        receivedInterest: Decimal = 0,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.balance = balance
        self.currency = currency.uppercased()
        self.annualRate = annualRate
        self.valueDate = valueDate
        self.maturityDate = maturityDate
        self.accruedInterest = accruedInterest
        self.receivedInterest = receivedInterest
        self.note = note
        self.updatedAt = .now
        self.createdAt = .now
    }

    var marketValueNative: Decimal {
        balance + accruedInterest
    }
}

/// 债券（手动估值）
@Model
final class BondHolding {
    @Attribute(.unique) var id: UUID
    /// 产品名称（必填）
    var name: String
    var currency: String
    /// 持有面值（必填）
    var faceValue: Decimal
    /// 成本（本金投入口径，可选；空口径用 0）
    var cost: Decimal
    /// 票面利率（可选）
    var couponRate: Decimal
    /// 买入日期（必填）
    var purchaseDate: Date
    /// 起息日（可选）
    var valueDate: Date?
    var maturityDate: Date?
    /// 预计赎回到账日（可选）
    var expectedRedemptionDate: Date?
    /// 付息方式 raw
    var couponFrequencyRaw: String
    /// 最新估值（手动）；空则回退 cost
    var marketValue: Decimal?
    var accruedInterest: Decimal
    var receivedInterest: Decimal
    var note: String
    var updatedAt: Date
    var createdAt: Date

    init(
        name: String,
        currency: String = "CNY",
        faceValue: Decimal,
        cost: Decimal = 0,
        couponRate: Decimal = 0,
        purchaseDate: Date = .now,
        valueDate: Date? = nil,
        maturityDate: Date? = nil,
        expectedRedemptionDate: Date? = nil,
        couponFrequency: BondCouponPaymentFrequency = .unset,
        marketValue: Decimal? = nil,
        accruedInterest: Decimal = 0,
        receivedInterest: Decimal = 0,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.currency = currency.uppercased()
        self.faceValue = faceValue
        self.cost = cost
        self.couponRate = couponRate
        self.purchaseDate = purchaseDate
        self.valueDate = valueDate
        self.maturityDate = maturityDate
        self.expectedRedemptionDate = expectedRedemptionDate
        self.couponFrequencyRaw = couponFrequency.rawValue
        self.marketValue = marketValue
        self.accruedInterest = accruedInterest
        self.receivedInterest = receivedInterest
        self.note = note
        self.updatedAt = .now
        self.createdAt = .now
    }

    var couponFrequency: BondCouponPaymentFrequency {
        get { BondCouponPaymentFrequency(rawValue: couponFrequencyRaw) ?? .unset }
        set { couponFrequencyRaw = newValue.rawValue }
    }

    var valuationNative: Decimal {
        (marketValue ?? (cost > 0 ? cost : faceValue)) + accruedInterest
    }

    var expectedRedemptionDateText: String {
        guard let expectedRedemptionDate else { return "未设置" }
        return MoneyFormat.shortDate(expectedRedemptionDate)
    }

    var maturityDateText: String {
        guard let maturityDate else { return "未设置" }
        return MoneyFormat.shortDate(maturityDate)
    }

    var valueDateText: String {
        guard let valueDate else { return "未设置" }
        return MoneyFormat.shortDate(valueDate)
    }

    var couponRateText: String {
        guard couponRate > 0 else { return "未设置" }
        return MoneyFormat.percent(couponRate)
    }

    /// 到期或预计到账日已到，且仍有持仓面值
    func isSettlementDue(asOf: Date = .now, calendar: Calendar = .current) -> Bool {
        guard faceValue > 0 else { return false }
        let dueDate = expectedRedemptionDate ?? maturityDate
        guard let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) <= calendar.startOfDay(for: asOf)
    }

    /// 列表卡倒计时：有周期性付息则「距离下次派息」；否则优先「距离到期赎回」，再回退「距离到期」。
    func listCountdown(
        asOf: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> BondListCountdown {
        let today = calendar.startOfDay(for: asOf)
        let anchor = calendar.startOfDay(for: valueDate ?? purchaseDate)

        if let nextCoupon = nextCouponPaymentDate(asOf: asOf, calendar: calendar) {
            let lastCoupon = previousCouponPaymentDate(before: nextCoupon, calendar: calendar) ?? anchor
            return Self.makeCountdown(
                label: "距离下次派息",
                from: lastCoupon,
                to: nextCoupon,
                asOf: today,
                calendar: calendar
            )
        }

        if let redemption = expectedRedemptionDate {
            return Self.makeCountdown(
                label: "距离到期赎回",
                from: anchor,
                to: calendar.startOfDay(for: redemption),
                asOf: today,
                calendar: calendar
            )
        }

        if let maturity = maturityDate {
            return Self.makeCountdown(
                label: "距离到期",
                from: anchor,
                to: calendar.startOfDay(for: maturity),
                asOf: today,
                calendar: calendar
            )
        }

        return BondListCountdown(label: "到期日", daysText: "未设置", progress: 0, isOverdue: false)
    }

    /// 下一次派息日（到期一次还本付息 / 未设置付息方式时返回 nil，改用到期逻辑）
    func nextCouponPaymentDate(
        asOf: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date? {
        let months = couponFrequency.periodMonths
        guard months > 0 else { return nil }

        let today = calendar.startOfDay(for: asOf)
        let start = calendar.startOfDay(for: valueDate ?? purchaseDate)
        let hardStop = (maturityDate ?? expectedRedemptionDate).map { calendar.startOfDay(for: $0) }

        var cursor = start
        // 从起息/买入日起按付息周期推进，找到第一个严格晚于今天的派息日
        for _ in 0..<600 {
            guard let next = calendar.date(byAdding: .month, value: months, to: cursor) else { return nil }
            let nextDay = calendar.startOfDay(for: next)
            if let hardStop, nextDay > hardStop { return nil }
            if nextDay > today {
                return nextDay
            }
            cursor = nextDay
        }
        return nil
    }

    private func previousCouponPaymentDate(
        before nextCoupon: Date,
        calendar: Calendar
    ) -> Date? {
        let months = couponFrequency.periodMonths
        guard months > 0 else { return nil }
        return calendar.date(byAdding: .month, value: -months, to: nextCoupon).map {
            calendar.startOfDay(for: $0)
        }
    }

    private static func makeCountdown(
        label: String,
        from start: Date,
        to end: Date,
        asOf today: Date,
        calendar: Calendar
    ) -> BondListCountdown {
        let daysLeft = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        let total = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let progress = min(1, max(0, Double(elapsed) / Double(total)))

        if daysLeft < 0 {
            return BondListCountdown(label: label, daysText: "已到期", progress: 1, isOverdue: true)
        }
        if daysLeft == 0 {
            return BondListCountdown(label: label, daysText: "今日", progress: 1, isOverdue: false)
        }
        return BondListCountdown(
            label: label,
            daysText: "\(daysLeft) 天",
            progress: progress,
            isOverdue: false
        )
    }
}

struct BondListCountdown {
    let label: String
    let daysText: String
    let progress: Double
    let isOverdue: Bool
}

/// 现金 / 其他物件类型（肖像 + 配色）
enum CashOtherKind: String, Codable, CaseIterable, Identifiable {
    case cash
    case redPacket
    case gold
    case jewelry
    case watch
    case collectible
    case digital
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: return "现金"
        case .redPacket: return "红包"
        case .gold: return "黄金"
        case .jewelry: return "饰品"
        case .watch: return "手表"
        case .collectible: return "收藏品"
        case .digital: return "数码"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .cash: return "banknote.fill"
        case .redPacket: return "envelope.fill"
        case .gold: return "circle.hexagongrid.fill"
        case .jewelry: return "sparkles"
        case .watch: return "applewatch"
        case .collectible: return "shippingbox.fill"
        case .digital: return "laptopcomputer"
        case .other: return "cube.fill"
        }
    }

    var namePlaceholder: String {
        switch self {
        case .cash: return "如 零钱包、备用金"
        case .redPacket: return "如 过年红包、压岁钱"
        case .gold: return "如 金条、金豆"
        case .jewelry: return "如 项链、手镯"
        case .watch: return "如 机械表品牌型号"
        case .collectible: return "如 邮票、手办、玉件"
        case .digital: return "如 手机、相机"
        case .other: return "物件名称"
        }
    }

    /// 阳光清爽软底
    var softHex: UInt32 {
        switch self {
        case .cash: return 0xEAF2F8
        case .redPacket: return 0xF8E8E6
        case .gold: return 0xF6F0E4
        case .jewelry: return 0xF3EAF4
        case .watch: return 0xEEF0F5
        case .collectible: return 0xE8F2EC
        case .digital: return 0xEAEFF8
        case .other: return 0xF0F2ED
        }
    }

    var strongHex: UInt32 {
        switch self {
        case .cash: return 0x3D7EB5
        case .redPacket: return 0xC45B4E
        case .gold: return 0xC2943A
        case .jewelry: return 0x9B6FA8
        case .watch: return 0x5A6578
        case .collectible: return 0x4A8F6E
        case .digital: return 0x5B6FBF
        case .other: return 0x6B756E
        }
    }

    static func infer(from name: String) -> CashOtherKind {
        let n = name.lowercased()
        if n.contains("红包") || n.contains("压岁") { return .redPacket }
        if n.contains("手表") || n.contains("腕表") || n.contains("watch") { return .watch }
        if n.contains("黄金") || n.contains("金条") || n.contains("金豆") || n.contains("金砖") { return .gold }
        if n.contains("金饰") || n.contains("饰品") || n.contains("项链") || n.contains("手镯")
            || n.contains("戒指") || n.contains("耳环") { return .jewelry }
        if n.contains("收藏") || n.contains("藏品") || n.contains("文玩") || n.contains("邮票")
            || n.contains("钱币") || n.contains("手办") || n.contains("玉") { return .collectible }
        if n.contains("现金") || n.contains("钱包") || n.contains("零钱") || n.contains("纸币")
            || n.contains("备用金") { return .cash }
        if n.contains("手机") || n.contains("电脑") || n.contains("平板") || n.contains("数码")
            || n.contains("相机") { return .digital }
        return .other
    }
}

/// 现金 / 其他资产（手动）
@Model
final class CashOtherAsset {
    @Attribute(.unique) var id: UUID
    var name: String
    var balance: Decimal
    var currency: String
    var note: String
    /// 物件类型 raw（现金 / 红包 / 黄金等）；空则按名称推断
    var kindRaw: String = ""
    var updatedAt: Date
    var createdAt: Date

    var kind: CashOtherKind {
        get {
            if let stored = CashOtherKind(rawValue: kindRaw), !kindRaw.isEmpty {
                return stored
            }
            return CashOtherKind.infer(from: name)
        }
        set { kindRaw = newValue.rawValue }
    }

    init(
        name: String,
        balance: Decimal,
        currency: String = "CNY",
        note: String = "",
        kind: CashOtherKind = .other
    ) {
        self.id = UUID()
        self.name = name
        self.balance = balance
        self.currency = currency.uppercased()
        self.note = note
        self.kindRaw = kind.rawValue
        self.updatedAt = .now
        self.createdAt = .now
    }
}

/// 负债（手动，只减净资产）
@Model
final class LiabilityRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var balance: Decimal
    var currency: String
    var note: String
    var updatedAt: Date
    var createdAt: Date

    init(
        name: String,
        balance: Decimal,
        currency: String = "CNY",
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.balance = balance
        self.currency = currency.uppercased()
        self.note = note
        self.updatedAt = .now
        self.createdAt = .now
    }
}

/// 手动资产本金/利息流水（存入本金不算收益）
@Model
final class ManualCapitalEvent {
    @Attribute(.unique) var id: UUID
    /// 关联手动资产 UUID 字符串
    var assetID: String
    var assetClassRaw: String
    var kindRaw: String
    var amount: Decimal
    var currency: String
    var eventDate: Date
    var note: String
    var createdAt: Date

    init(
        assetID: UUID,
        assetClass: AssetClass,
        kind: ManualCapitalEventKind,
        amount: Decimal,
        currency: String,
        eventDate: Date = .now,
        note: String = ""
    ) {
        self.id = UUID()
        self.assetID = assetID.uuidString
        self.assetClassRaw = assetClass.rawValue
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currency = currency.uppercased()
        self.eventDate = eventDate
        self.note = note
        self.createdAt = .now
    }

    var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .cashOther }
        set { assetClassRaw = newValue.rawValue }
    }

    var kind: ManualCapitalEventKind {
        get { ManualCapitalEventKind(rawValue: kindRaw) ?? .deposit }
        set { kindRaw = newValue.rawValue }
    }
}
