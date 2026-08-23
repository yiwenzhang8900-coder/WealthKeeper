import SwiftUI

/// 持仓概览 / 指标区的单个度量
struct HoldingOverviewMetric: Identifiable {
    let id: String
    let label: String
    let value: String
    /// 主数值下方的辅助说明（如到期日下的剩余期限）
    var subtitle: String? = nil
    /// 非 nil 时用涨跌色（A 股习惯：红涨绿跌）
    var amountForTint: Decimal? = nil
    var isPlaceholder: Bool = false

    init(
        _ label: String,
        _ value: String,
        subtitle: String? = nil,
        amountForTint: Decimal? = nil,
        isPlaceholder: Bool = false
    ) {
        self.id = label
        self.label = label
        self.value = value
        self.subtitle = subtitle
        self.amountForTint = amountForTint
        self.isPlaceholder = isPlaceholder
    }
}

/// 双列网格概览：嵌入 List Section，与流水/交易记录分区等宽
struct HoldingOverviewGridCard: View {
    @Environment(\.wkTheme) private var theme

    var title: String
    var titleTrailing: String? = nil
    var metrics: [HoldingOverviewMetric]
    /// 更紧凑的行距（债券持仓概览等）
    var compact: Bool = false

    private var rows: [[HoldingOverviewMetric]] {
        stride(from: 0, to: metrics.count, by: 2).map { start in
            Array(metrics[start..<min(start + 2, metrics.count)])
        }
    }

    private var rowSpacing: CGFloat { compact ? 10 : 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                if let titleTrailing, !titleTrailing.isEmpty {
                    Text(titleTrailing)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        metricCell(row[0])
                        if row.count > 1 {
                            metricCell(row[1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 2 : 4)
    }

    private func metricCell(_ metric: HoldingOverviewMetric) -> some View {
        let color: Color = {
            if let amount = metric.amountForTint {
                return theme.marketPnL(amount)
            }
            if metric.isPlaceholder {
                return theme.secondaryText
            }
            return theme.primaryText
        }()

        return VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Text(metric.value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let subtitle = metric.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// 概览行：与下方交易/流水记录分区同宽（系统 insetGrouped 卡片宽）
    func wkOverviewListRow() -> some View {
        modifier(WKOverviewListRowModifier())
    }

    /// 类目列表卡片行：透明背景、无分隔线、无右侧箭头
    func wkCategoryCardRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
    }
}

private struct WKOverviewListRowModifier: ViewModifier {
    @Environment(\.wkTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(theme.cardBackground)
            .listRowSeparator(.hidden)
    }
}

/// 概览下方快捷操作（存入/取出、买入/卖出/分红等）
struct HoldingQuickActionBar: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let tint: Color
        let action: () -> Void

        init(id: String, title: String, systemImage: String, tint: Color, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.tint = tint
            self.action = action
        }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(item.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.tint.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

extension BondHolding {
    /// 不含预计利息的当前估值（手动市值，缺省回退成本或面值）
    var currentValuation: Decimal {
        marketValue ?? (cost > 0 ? cost : faceValue)
    }

    var netPnLNative: Decimal {
        currentValuation - (cost > 0 ? cost : faceValue)
    }

    var returnRate: Decimal {
        let basis = cost > 0 ? cost : faceValue
        guard basis > 0 else { return 0 }
        return netPnLNative / basis
    }

    /// 剩余期限文案
    func remainingTermDescription(
        asOf: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        Self.remainingTermText(maturityDate: maturityDate, asOf: asOf, calendar: calendar)
    }

    static func remainingTermText(
        maturityDate: Date?,
        asOf: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        guard let maturityDate else { return "未设置" }
        let start = calendar.startOfDay(for: asOf)
        let end = calendar.startOfDay(for: maturityDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        if days < 0 { return "已到期" }
        if days == 0 { return "今日到期" }
        if days < 30 { return "\(days)天" }
        let years = days / 365
        let remDays = days % 365
        let months = remDays / 30
        if years >= 1 {
            if months == 0 { return "约\(years)年" }
            return "约\(years)年\(months)个月"
        }
        if months >= 1 {
            return "约\(months)个月"
        }
        return "\(days)天"
    }
}

extension BankDepositAccount {
    func remainingTermDescription(asOf: Date = .now) -> String {
        BondHolding.remainingTermText(maturityDate: maturityDate, asOf: asOf)
    }
}

extension FXSavingsAccount {
    func remainingTermDescription(asOf: Date = .now) -> String {
        BondHolding.remainingTermText(maturityDate: maturityDate, asOf: asOf)
    }
}
