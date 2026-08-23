import Foundation
import SwiftData

enum LifestyleFlowKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }
}

enum LifestyleCategory: String, Codable, CaseIterable, Identifiable {
    // 支出
    case shopping
    case dining
    case travel
    case transport
    case housing
    case entertainment
    case medical
    case education
    case daily
    case social
    case otherExpense
    // 收入
    case salary
    case bonus
    case gift
    case refund
    case sideJob
    case otherIncome

    var id: String { rawValue }

    var flowKind: LifestyleFlowKind {
        switch self {
        case .salary, .bonus, .gift, .refund, .sideJob, .otherIncome:
            return .income
        default:
            return .expense
        }
    }

    var displayName: String {
        switch self {
        case .shopping: return "购物"
        case .dining: return "餐饮"
        case .travel: return "旅行"
        case .transport: return "交通"
        case .housing: return "居住"
        case .entertainment: return "娱乐"
        case .medical: return "医疗"
        case .education: return "学习"
        case .daily: return "日用"
        case .social: return "人情"
        case .otherExpense: return "其他支出"
        case .salary: return "工资"
        case .bonus: return "奖金"
        case .gift: return "红包礼物"
        case .refund: return "退款"
        case .sideJob: return "兼职副业"
        case .otherIncome: return "其他收入"
        }
    }

    var systemImage: String {
        switch self {
        case .shopping: return "bag.fill"
        case .dining: return "fork.knife"
        case .travel: return "airplane"
        case .transport: return "bus.fill"
        case .housing: return "house.fill"
        case .entertainment: return "gamecontroller.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .daily: return "cart.fill"
        case .social: return "heart.fill"
        case .otherExpense: return "ellipsis.circle.fill"
        case .salary: return "banknote.fill"
        case .bonus: return "gift.fill"
        case .gift: return "envelope.fill"
        case .refund: return "arrow.uturn.backward.circle.fill"
        case .sideJob: return "laptopcomputer"
        case .otherIncome: return "plus.circle.fill"
        }
    }

    static var expenseCases: [LifestyleCategory] {
        allCases.filter { $0.flowKind == .expense }
    }

    static var incomeCases: [LifestyleCategory] {
        allCases.filter { $0.flowKind == .income }
    }
}

/// 生活记账流水（收入增加结余，支出减少结余；结余计入总资产）
@Model
final class LifestyleEntry {
    @Attribute(.unique) var id: UUID
    var flowKindRaw: String
    var categoryRaw: String
    var amount: Decimal
    var currency: String
    var entryDate: Date
    var note: String
    var updatedAt: Date
    var createdAt: Date

    init(
        flowKind: LifestyleFlowKind,
        category: LifestyleCategory,
        amount: Decimal,
        currency: String = "CNY",
        entryDate: Date = .now,
        note: String = ""
    ) {
        self.id = UUID()
        self.flowKindRaw = flowKind.rawValue
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.currency = currency.uppercased()
        self.entryDate = entryDate
        self.note = note
        self.updatedAt = .now
        self.createdAt = .now
    }

    var flowKind: LifestyleFlowKind {
        get { LifestyleFlowKind(rawValue: flowKindRaw) ?? .expense }
        set { flowKindRaw = newValue.rawValue }
    }

    var category: LifestyleCategory {
        get { LifestyleCategory(rawValue: categoryRaw) ?? .otherExpense }
        set { categoryRaw = newValue.rawValue }
    }

    /// 对生活结余的符号贡献：收入 +，支出 −
    var signedAmount: Decimal {
        flowKind == .income ? amount : -amount
    }
}
