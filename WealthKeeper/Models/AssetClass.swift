import Foundation

/// 个人财富资产类别（占比与汇总用）
enum AssetClass: String, Codable, CaseIterable, Identifiable {
    case bankDeposit
    case bond
    case fund
    case equity
    case fxSavings
    case cashOther
    case lifestyle
    case liability

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bankDeposit: return "银行存款"
        case .bond: return "债券"
        case .fund: return "基金"
        case .equity: return "股票"
        case .fxSavings: return "外币"
        case .cashOther: return "现金/其他"
        case .lifestyle: return "生活结余"
        case .liability: return "负债"
        }
    }

    /// 是否计入总资产（负债不计）
    var countsTowardTotalAssets: Bool {
        self != .liability
    }
}

enum ManualCapitalEventKind: String, Codable, CaseIterable, Identifiable {
    case deposit
    case withdraw
    case adjustPrincipal
    case interestReceived
    /// 债券到期赎回（清仓）
    case maturityRedeem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deposit: return "存入本金"
        case .withdraw: return "取出本金"
        case .adjustPrincipal: return "本金调整"
        case .interestReceived: return "利息到账"
        case .maturityRedeem: return "到期赎回"
        }
    }

    /// 是否计入「收益」（本金存取不算收益）
    var countsAsReturn: Bool {
        self == .interestReceived
    }
}

/// 银行存款 / 理财子类
enum BankDepositKind: String, Codable, CaseIterable, Identifiable {
    case demand
    case fixed
    case wealth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .demand: return "活期存款"
        case .fixed: return "定期存款"
        case .wealth: return "银行理财"
        }
    }

    /// 列表/标题用短名
    var shortName: String {
        switch self {
        case .demand: return "活期"
        case .fixed: return "定期"
        case .wealth: return "理财"
        }
    }

    /// 活期 ↔ 定期互转用；理财不适用
    var opposite: BankDepositKind {
        switch self {
        case .demand: return .fixed
        case .fixed: return .demand
        case .wealth: return .demand
        }
    }
}

/// 银行理财产品形态（常见分类）
enum BankWealthStyle: String, Codable, CaseIterable, Identifiable {
    case netValue
    case closed
    case cashManagement

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netValue: return "净值型"
        case .closed: return "封闭式"
        case .cashManagement: return "现金管理"
        }
    }
}

/// 银行理财风险等级 R1–R5
enum BankWealthRiskLevel: String, Codable, CaseIterable, Identifiable {
    case r1, r2, r3, r4, r5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .r1: return "R1 低风险"
        case .r2: return "R2 中低风险"
        case .r3: return "R3 中风险"
        case .r4: return "R4 中高风险"
        case .r5: return "R5 高风险"
        }
    }

    var shortName: String { rawValue.uppercased() }
}

/// 债券付息方式
enum BondCouponPaymentFrequency: String, Codable, CaseIterable, Identifiable {
    case unset
    case onceAtMaturity
    case annual
    case semiAnnual
    case quarterly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unset: return "未设置"
        case .onceAtMaturity: return "到期一次还本付息"
        case .annual: return "按年付息"
        case .semiAnnual: return "半年付息"
        case .quarterly: return "按季付息"
        case .monthly: return "按月付息"
        }
    }

    /// 列表标签短名
    var shortDisplayName: String {
        switch self {
        case .unset: return "债券"
        case .onceAtMaturity: return "到期付息"
        case .annual: return "按年付息"
        case .semiAnnual: return "半年付息"
        case .quarterly: return "按季付息"
        case .monthly: return "按月付息"
        }
    }

    /// 付息周期月数；无法按期派息时为 0
    var periodMonths: Int {
        switch self {
        case .unset, .onceAtMaturity: return 0
        case .annual: return 12
        case .semiAnnual: return 6
        case .quarterly: return 3
        case .monthly: return 1
        }
    }
}
