import Foundation

enum Market: String, Codable, CaseIterable, Identifiable {
    case cnA = "CN_A"
    case hk = "HK"
    case us = "US"
    case cnFund = "CN_FUND"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cnA: return "A股"
        case .hk: return "港股"
        case .us: return "美股"
        case .cnFund: return "基金"
        }
    }

    /// 行政区域旗帜（中国 / 香港特区 / 美国）
    var regionFlag: String {
        switch self {
        case .cnA, .cnFund: return "🇨🇳"
        case .hk: return "🇭🇰"
        case .us: return "🇺🇸"
        }
    }

    var defaultCurrency: String {
        switch self {
        case .cnA, .cnFund: return "CNY"
        case .hk: return "HKD"
        case .us: return "USD"
        }
    }
}

enum InstrumentType: String, Codable, CaseIterable, Identifiable {
    case stock
    case etf
    case fund

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stock: return "股票"
        case .etf: return "ETF"
        case .fund: return "场外基金"
        }
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case buy
    case sell
    /// 现金分红
    case dividend
    /// 红利再投资（基金份额增加，现金等价计入分红收益）
    case dividendReinvest
    /// 送股 / 转增
    case bonusShare
    case fee
    case split

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .buy: return "买入"
        case .sell: return "卖出"
        case .dividend: return "现金分红"
        case .dividendReinvest: return "红利再投资"
        case .bonusShare: return "送股"
        case .fee: return "手续费"
        case .split: return "拆合股"
        }
    }

    /// 分红类（现金或再投资）
    var isDividendEvent: Bool {
        self == .dividend || self == .dividendReinvest
    }

    /// 重建持仓时同一天的处理顺序：先调仓，再公司行为，再现金分红/费用
    var ledgerRank: Int {
        switch self {
        case .buy: return 0
        case .sell: return 1
        case .split: return 2
        case .bonusShare: return 3
        case .dividendReinvest: return 4
        case .dividend: return 5
        case .fee: return 6
        }
    }
}

enum CorporateActionKind: String, Codable {
    case dividend
    case split
    case bonusShare
}

/// 基金分红结算方式
enum DividendSettlement: String, Codable, CaseIterable, Identifiable {
    case cash
    case reinvest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: return "现金分红"
        case .reinvest: return "红利再投资"
        }
    }
}
