import SwiftUI
import SwiftData

// MARK: - 债券

struct BondHoldingsManageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query(sort: \BondHolding.updatedAt, order: .reverse) private var bonds: [BondHolding]
    @Query private var settingsList: [AppSettings]
    @State private var editor: ManualEditorSession?
    @State private var pendingClearID: UUID?
    @State private var confirmClearBond = false
    @State private var bondSettlementSession: BondSettlementSession?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    /// 仍有面值或成本的持仓；已清仓记录保留在库中但不占列表。
    private var activeBonds: [BondHolding] {
        bonds.filter { $0.faceValue > 0 || $0.cost > 0 }
    }

    private var categoryTotalCNY: Decimal {
        activeBonds.reduce(Decimal(0)) { sum, item in
            sum + item.valuationNative * settings.rateToCNY(for: item.currency)
        }
    }

    var body: some View {
        List {
            if activeBonds.isEmpty {
                Section {
                    categoryEmptyBlock(message: "暂无债券持仓", actionTitle: "添加债券") {
                        editor = .create(.bond, depositKind: .demand)
                    }
                    .wkCategoryCardRow()
                }
            } else {
                Section {
                    ForEach(activeBonds, id: \.id) { item in
                        NavigationLink {
                            BondHoldingDetailView(bondID: item.id)
                        } label: {
                            bondCard(item)
                        }
                        .wkCategoryCardRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingClearID = item.id
                                confirmClearBond = true
                            } label: {
                                Label("清空持仓", systemImage: "trash.fill")
                            }
                            .tint(.red)
                            Button {
                                editor = .editBond(item.id)
                            } label: {
                                Label("修改", systemImage: "pencil")
                            }
                            .tint(theme.accent)
                        }
                    }
                } header: {
                    Text("债券")
                }
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle("债券")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .create(.bond, depositKind: .demand) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editor) { session in
            ManualAssetEditorView(session: session)
        }
        .sheet(item: $bondSettlementSession) { session in
            BondSettlementConfirmSheet(bondID: session.bondID)
        }
        .alert("清空持仓？", isPresented: $confirmClearBond) {
            Button("卖出清仓", role: .destructive) {
                if let id = pendingClearID,
                   let item = bonds.first(where: { $0.id == id }) {
                    PositionClearService.clearBondHolding(item, mode: .sell, context: context)
                }
                pendingClearID = nil
            }
            Button("到期赎回") {
                if let id = pendingClearID,
                   let item = bonds.first(where: { $0.id == id }) {
                    PositionClearService.clearBondHolding(item, mode: .maturityRedeem, context: context)
                }
                pendingClearID = nil
            }
            Button("取消", role: .cancel) { pendingClearID = nil }
        } message: {
            Text("不会删除债券与历史流水，仅新增一笔卖出或到期赎回记录。")
        }
        .onAppear {
            presentBondSettlementPromptIfNeeded()
        }
    }

    private func presentBondSettlementPromptIfNeeded() {
        guard bondSettlementSession == nil else { return }
        let due = activeBonds.first {
            $0.isSettlementDue() && !BondSettlementPromptStore.hasPrompted($0.id)
        }
        guard let due else { return }
        bondSettlementSession = BondSettlementSession(bondID: due.id)
    }

    private func bondCard(_ item: BondHolding) -> some View {
        let rate = settings.rateToCNY(for: item.currency)
        let basis = item.cost > 0 ? item.cost : item.faceValue
        let pnlCNY = (item.valuationNative - basis) * rate
        let totalReturnCNY = pnlCNY + item.receivedInterest * rate
        let valueCNY = item.valuationNative * rate
        let weight: Decimal = categoryTotalCNY > 0 ? valueCNY / categoryTotalCNY : 0
        return BondHoldingListCard(
            item: item,
            costCNY: basis * rate,
            receivedInterestCNY: item.receivedInterest * rate,
            totalReturnCNY: totalReturnCNY,
            accentIndex: abs(item.id.hashValue),
            weight: weight,
            showsCouponHero: false,
            showsCouponLabel: false,
            showsFooter: true
        )
    }
}

/// 债券列表卡：对齐「持仓明细」截图结构，字段映射本 App 债券数据。
private struct BondHoldingListCard: View {
    @Environment(\.wkTheme) private var theme

    let item: BondHolding
    let costCNY: Decimal
    let receivedInterestCNY: Decimal
    let totalReturnCNY: Decimal
    let accentIndex: Int
    var weight: Decimal = 0
    /// 列表不显示右上角票面利率；详情可显示
    var showsCouponHero: Bool = true
    /// 详情页右上角票面利率上方显示小字标签
    var showsCouponLabel: Bool = false
    /// 列表显示组合占比；详情隐藏底部灰条
    var showsFooter: Bool = true

    private var accent: BondCardAccent {
        BondCardAccent.palette(at: accentIndex, isNight: theme.isNight)
    }

    private var hasCoupon: Bool { item.couponRate > 0 }

    private var couponPercentText: String {
        let value = DecimalMath.double(item.couponRate * 100)
        return String(format: "%.2f", value)
    }

    private var tagText: String {
        item.couponFrequency.shortDisplayName
    }

    private var weightPercent: Double {
        DecimalMath.double(max(0, min(weight, 1))) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            metricsBlock
            if showsFooter {
                weightFooter
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
        )
        .shadow(
            color: theme.isNight ? .clear : Color.black.opacity(0.04),
            radius: 10,
            y: 3
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.soft)
                Image(systemName: item.name.contains("国债") ? "building.columns.fill" : "briefcase.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent.strong)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(tagText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.secondaryCardBackground)
                        )

                    Text("面值 ¥\(MoneyFormat.compact(item.faceValue))")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if showsCouponHero, hasCoupon {
                VStack(alignment: .trailing, spacing: 2) {
                    if showsCouponLabel {
                        Text("票面利率")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(couponPercentText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accent.strong)
                        Text("%")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent.strong)
                    }
                }
                .accessibilityLabel("票面利率 \(item.couponRateText)")
            }
        }
    }

    private var metricsBlock: some View {
        HStack(spacing: 0) {
            metricColumn(label: "投入本金", value: MoneyFormat.compact(costCNY), tint: theme.primaryText)
            metricColumn(
                label: "已收利息",
                value: MoneyFormat.compact(receivedInterestCNY),
                tint: theme.primaryText
            )
            metricColumn(
                label: "总收益",
                value: MoneyFormat.compact(totalReturnCNY, sign: true),
                tint: accent.strong,
                showTrend: totalReturnCNY != 0
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.soft.opacity(theme.isNight ? 0.85 : 1))
        )
    }

    private var weightFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                Text("组合占比")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                Text(String(format: "%.1f%%", weightPercent))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.separator.opacity(theme.isNight ? 0.8 : 0.65))
                    Capsule()
                        .fill(accent.strong)
                        .frame(width: max(4, geo.size.width * CGFloat(weightPercent / 100)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.secondaryCardBackground.opacity(theme.isNight ? 0.7 : 0.85))
        )
    }

    private func metricColumn(
        label: String,
        value: String,
        tint: Color,
        showTrend: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 2) {
                if showTrend {
                    Image(systemName: totalReturnCNY >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BondCardAccent {
    let soft: Color
    let strong: Color

    static func palette(at index: Int, isNight: Bool) -> BondCardAccent {
        // 阳光清爽：雾蓝 / 薄荷 / 暖沙 / 浅紫灰，与银行存款色块气质一致
        let sunny: [(soft: UInt32, strong: UInt32)] = [
            (0xE8EEF8, 0x5B6FBF), // 雾蓝紫
            (0xE4F3EF, 0x2F9B8A), // 薄荷青
            (0xF3EEE6, 0xC47A2C), // 暖沙
            (0xEAF2F8, 0x3487D8), // 系统雾蓝
            (0xF0EEF6, 0x6E6AA8), // 浅紫
            (0xEEF5F0, 0x3D8F6A), // 叶绿
        ]
        let pair = sunny[abs(index) % sunny.count]
        if isNight {
            return BondCardAccent(
                soft: Color(hex: pair.strong).opacity(0.22),
                strong: Color(hex: pair.strong).opacity(0.95)
            )
        }
        return BondCardAccent(
            soft: Color(hex: pair.soft),
            strong: Color(hex: pair.strong)
        )
    }
}

/// 详情页持仓概览：与列表卡同色系的双列指标块
private struct BondDetailOverviewCard: View {
    @Environment(\.wkTheme) private var theme

    let metrics: [HoldingOverviewMetric]
    let accent: BondCardAccent

    private var rows: [[HoldingOverviewMetric]] {
        stride(from: 0, to: metrics.count, by: 2).map { start in
            Array(metrics[start..<min(start + 2, metrics.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(theme.separator.opacity(0.7))
                        .frame(height: 0.5)
                        .padding(.vertical, 10)
                }
                HStack(alignment: .top, spacing: 16) {
                    overviewCell(row[0])
                    if row.count > 1 {
                        overviewCell(row[1])
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.soft.opacity(theme.isNight ? 0.85 : 1))
        )
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
        )
    }

    private func overviewCell(_ metric: HoldingOverviewMetric) -> some View {
        let color: Color = {
            if let amount = metric.amountForTint {
                return amount >= 0 ? accent.strong : theme.loss
            }
            if metric.isPlaceholder {
                return theme.secondaryText
            }
            return theme.primaryText
        }()

        return VStack(alignment: .leading, spacing: 4) {
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            Text(metric.value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
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

private struct BondDetailActionsCard: View {
    @Environment(\.wkTheme) private var theme

    let onBuy: () -> Void
    let onSell: () -> Void
    let onSettle: () -> Void
    var settleTitle: String = "到期赎回"
    var settleSystemImage: String = "arrow.uturn.backward.circle.fill"
    var settleTint: Color? = nil

    var body: some View {
        HoldingQuickActionBar(items: [
            .init(id: "buy", title: "买入", systemImage: "plus.circle.fill", tint: theme.gain, action: onBuy),
            .init(id: "sell", title: "卖出", systemImage: "minus.circle.fill", tint: theme.loss, action: onSell),
            .init(
                id: "settle",
                title: settleTitle,
                systemImage: settleSystemImage,
                tint: settleTint ?? theme.warning,
                action: onSettle
            ),
        ])
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
        )
    }
}

struct BondHoldingDetailView: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.modelContext) private var context
    let bondID: UUID

    @Query private var bonds: [BondHolding]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ManualCapitalEvent.eventDate, order: .reverse) private var events: [ManualCapitalEvent]
    @State private var editor: ManualEditorSession?
    @State private var bondTradeSession: BondTradeSession?
    @State private var eventFilter: ManualEventFilter = .all
    @State private var editEventID: UUID?
    @State private var pendingDeleteEventID: UUID?
    @State private var confirmDeleteEvent = false
    @State private var bondSettlementSession: BondSettlementSession?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var item: BondHolding? {
        bonds.first { $0.id == bondID }
    }

    private var relatedEvents: [ManualCapitalEvent] {
        let id = bondID.uuidString
        let all = events.filter { $0.assetID == id && $0.assetClass == .bond }
        return all.filter { eventFilter.matches($0.kind) }
    }

    private var accent: BondCardAccent {
        BondCardAccent.palette(at: abs(bondID.hashValue), isNight: theme.isNight)
    }

    var body: some View {
        Group {
            if let item {
                let rate = settings.rateToCNY(for: item.currency)
                let basis = item.cost > 0 ? item.cost : item.faceValue
                let pnlCNY = (item.valuationNative - basis) * rate
                let totalReturnCNY = pnlCNY + item.receivedInterest * rate

                List {
                    Section {
                        BondHoldingListCard(
                            item: item,
                            costCNY: basis * rate,
                            receivedInterestCNY: item.receivedInterest * rate,
                            totalReturnCNY: totalReturnCNY,
                            accentIndex: abs(item.id.hashValue),
                            weight: 0,
                            showsCouponHero: true,
                            showsCouponLabel: true,
                            showsFooter: false
                        )
                        .wkCategoryCardRow()
                        .id("\(item.updatedAt.timeIntervalSince1970)-\(item.cost)-\(item.faceValue)-\(item.currentValuation)-\(relatedEvents.count)")
                    }

                    Section {
                        BondDetailOverviewCard(
                            metrics: bondOverviewMetrics(item),
                            accent: accent
                        )
                        .wkCategoryCardRow()
                    } header: {
                        Text("持仓概览")
                    }

                    Section {
                        BondDetailActionsCard(
                            onBuy: {
                                bondTradeSession = BondTradeSession(bondID: item.id, isBuy: true)
                            },
                            onSell: {
                                bondTradeSession = BondTradeSession(bondID: item.id, isBuy: false)
                            },
                            onSettle: {
                                bondSettlementSession = BondSettlementSession(bondID: item.id)
                            }
                        )
                        .wkCategoryCardRow()
                    }

                    if item.isSettlementDue() {
                        Section {
                            Button {
                                bondSettlementSession = BondSettlementSession(bondID: item.id)
                            } label: {
                                Label("到期赎回", systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(theme.warning)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(theme.warning.opacity(0.14))
                                    )
                            }
                            .buttonStyle(.plain)
                            .wkCategoryCardRow()
                        } footer: {
                            Text("填写实际到账日期与兑付收益。预计到账日：\(item.expectedRedemptionDateText)。")
                        }
                    }

                    Section {
                        Picker("筛选", selection: $eventFilter) {
                            ForEach(ManualEventFilter.allCases) { filter in
                                Text(filter.title(inbound: "买入", outbound: "卖出")).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)

                        if relatedEvents.isEmpty {
                            Text("暂无符合条件的流水")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(theme.cardBackground)
                                )
                                .wkCategoryCardRow()
                        } else {
                            ForEach(relatedEvents, id: \.id) { ev in
                                NavigationLink {
                                    BondCapitalEventDetailView(eventID: ev.id)
                                } label: {
                                    ManualEventCardRow(
                                        event: ev,
                                        assetName: item.name,
                                        accent: manualEventAccent(for: ev.kind, theme: theme)
                                    )
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(theme.cardBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
                                    )
                                }
                                .wkCategoryCardRow()
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteEventID = ev.id
                                        confirmDeleteEvent = true
                                    } label: {
                                        Label("删除", systemImage: "trash.fill")
                                    }
                                    .tint(.red)
                                    Button {
                                        editEventID = ev.id
                                    } label: {
                                        Label("修改", systemImage: "pencil")
                                    }
                                    .tint(theme.accent)
                                }
                            }
                        }
                    } header: {
                        Text("流水记录")
                    } footer: {
                        Text("点按进入详情。")
                    }

                    if !item.note.isEmpty {
                        Section {
                            Text(item.note)
                                .foregroundStyle(theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(theme.cardBackground)
                                )
                                .wkCategoryCardRow()
                        } header: {
                            Text("备注")
                        }
                    }
                }
                .listStyle(.plain)
                .wkPageChrome()
            } else {
                ContentUnavailableView("债券不存在", systemImage: "tray")
            }
        }
        .navigationTitle("持仓详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editEventID) { id in
            BondCapitalEventDetailView(eventID: id)
        }
        .sheet(item: $editor, onDismiss: {
            if let item = bonds.first(where: { $0.id == bondID }) {
                item.updatedAt = .now
                try? context.save()
            }
        }) { session in
            ManualAssetEditorView(session: session)
        }
        .sheet(item: $bondTradeSession) { session in
            BondTradeSheet(bondID: session.bondID, isBuy: session.isBuy)
        }
        .sheet(item: $bondSettlementSession) { session in
            BondSettlementConfirmSheet(bondID: session.bondID)
        }
        .alert("删除这笔交易？", isPresented: $confirmDeleteEvent) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteEventID,
                   let event = events.first(where: { $0.id == id }) {
                    deleteEvent(event)
                }
                pendingDeleteEventID = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteEventID = nil
            }
        } message: {
            Text("删除后将撤销该笔对债券成本的影响，此操作不可撤销。")
        }
        .onAppear {
            if let item, item.isSettlementDue(), !BondSettlementPromptStore.hasPrompted(item.id) {
                bondSettlementSession = BondSettlementSession(bondID: item.id)
            }
        }
    }

    private func bondOverviewMetrics(_ item: BondHolding) -> [HoldingOverviewMetric] {
        let pnl = item.netPnLNative
        let costBasis = item.cost > 0 ? item.cost : item.faceValue
        let maturity = maturityOverviewDisplay(for: item)
        return [
            HoldingOverviewMetric("持有面值", MoneyFormat.compact(item.faceValue)),
            HoldingOverviewMetric("持仓成本", MoneyFormat.compact(costBasis)),
            HoldingOverviewMetric("当前估值", MoneyFormat.compact(item.currentValuation)),
            HoldingOverviewMetric("累计收益", MoneyFormat.compact(pnl, sign: true), amountForTint: pnl),
            HoldingOverviewMetric("收益率", MoneyFormat.percent(item.returnRate), amountForTint: pnl),
            HoldingOverviewMetric("最近买入日期", MoneyFormat.shortDate(latestBuyDate(for: item))),
            HoldingOverviewMetric(
                "到期日",
                maturity.value,
                subtitle: maturity.subtitle
            ),
        ]
    }

    /// 最近一次买入同一债券的日期（流水优先，否则用持仓上的买入日）
    private func latestBuyDate(for item: BondHolding) -> Date {
        let buys = events.filter {
            $0.assetID == item.id.uuidString
                && $0.assetClass == .bond
                && ($0.kind == .deposit || $0.kind == .adjustPrincipal)
        }
        return buys.map(\.eventDate).max() ?? item.purchaseDate
    }

    private func maturityOverviewDisplay(for item: BondHolding) -> (value: String, subtitle: String?) {
        guard let maturityDate = item.maturityDate else {
            return ("未设置", nil)
        }
        let dateText: String = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy年M月d日"
            return formatter.string(from: maturityDate)
        }()
        let remaining = item.remainingTermDescription()
        switch remaining {
        case "未设置":
            return ("未设置", nil)
        case "已到期":
            return (dateText, "已到期")
        case "今日到期":
            return (dateText, "今日到期")
        default:
            return (dateText, "剩余\(remaining)")
        }
    }

    private func deleteEvent(_ event: ManualCapitalEvent) {
        guard let item else { return }
        switch event.kind {
        case .deposit, .adjustPrincipal:
            item.cost = max(0, item.cost - event.amount)
        case .withdraw, .maturityRedeem:
            item.cost += event.amount
        case .interestReceived:
            item.receivedInterest = max(0, item.receivedInterest - event.amount)
        }
        item.updatedAt = .now
        context.delete(event)
        try? context.save()
    }
}

struct BondSettlementSession: Identifiable {
    let id: UUID
    let bondID: UUID

    init(bondID: UUID) {
        self.id = bondID
        self.bondID = bondID
    }
}

struct BondTradeSession: Identifiable {
    let id = UUID()
    let bondID: UUID
    let isBuy: Bool
}

/// 债券买入 / 卖出精简录入
struct BondTradeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var bonds: [BondHolding]

    let bondID: UUID
    let isBuy: Bool

    @State private var faceText = ""
    @State private var amountText = ""
    @State private var couponInterestText = ""
    @State private var feeText = ""
    @State private var tradeDate = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    private var item: BondHolding? {
        bonds.first { $0.id == bondID }
    }

    private var title: String { isBuy ? "买入" : "卖出" }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        LabeledContent("产品", value: item.name)
                        LabeledContent("当前面值", value: MoneyFormat.compact(item.faceValue))
                    }
                    .listRowBackground(theme.cardBackground)

                    Section {
                        LabeledContent("面值") {
                            DecimalTextField(placeholder: "必填", text: $faceText)
                                .frame(height: 36)
                        }
                        LabeledContent("成交金额") {
                            DecimalTextField(placeholder: "必填", text: $amountText)
                                .frame(height: 36)
                        }
                        LabeledContent("票面利息") {
                            DecimalTextField(placeholder: "可选", text: $couponInterestText)
                                .frame(height: 36)
                        }
                        LabeledContent("手续费") {
                            DecimalTextField(placeholder: "可选", text: $feeText)
                                .frame(height: 36)
                        }
                        DatePicker("交易时间", selection: $tradeDate, displayedComponents: [.date, .hourAndMinute])
                    } header: {
                        Text(title)
                    }
                    .listRowBackground(theme.cardBackground)

                    Section("备注") {
                        CJKTextField(placeholder: "可选", text: $note)
                            .frame(height: 40)
                    }
                    .listRowBackground(theme.cardBackground)

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(theme.destructive)
                        }
                    }
                } else {
                    ContentUnavailableView("债券不存在", systemImage: "tray")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.pageBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(item == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let item else { return }
        guard let face = DecimalMath.parse(faceText), face > 0 else {
            errorMessage = "请填写有效面值"
            return
        }
        guard let amount = DecimalMath.parse(amountText), amount > 0 else {
            errorMessage = "请填写有效成交金额"
            return
        }
        let interest = DecimalMath.parse(couponInterestText) ?? 0
        let fee = DecimalMath.parse(feeText) ?? 0
        guard interest >= 0, fee >= 0 else {
            errorMessage = "利息与手续费不能为负"
            return
        }

        let noteTrimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var eventNote = isBuy ? "买入" : "卖出"
        if fee > 0 { eventNote += " · 手续费 \(MoneyFormat.compact(fee))" }
        if !noteTrimmed.isEmpty { eventNote += " · \(noteTrimmed)" }

        if isBuy {
            item.faceValue += face
            item.cost += amount + fee
            item.purchaseDate = tradeDate
            if let marketValue = item.marketValue {
                item.marketValue = marketValue + amount + fee
            }
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bond,
                kind: .deposit,
                amount: amount + fee,
                currency: item.currency,
                eventDate: tradeDate,
                note: eventNote
            ))
        } else {
            guard face <= item.faceValue else {
                errorMessage = "卖出面值不能大于当前持有面值"
                return
            }
            let costReduce: Decimal = {
                guard item.faceValue > 0, item.cost > 0 else { return min(amount, item.cost) }
                let ratio = face / item.faceValue
                return min(item.cost, (item.cost * ratio).rounded(scale: 2))
            }()
            item.faceValue -= face
            item.cost = max(0, item.cost - costReduce)
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bond,
                kind: .withdraw,
                amount: amount,
                currency: item.currency,
                eventDate: tradeDate,
                note: eventNote
            ))
        }

        if interest > 0 {
            item.receivedInterest += interest
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bond,
                kind: .interestReceived,
                amount: interest,
                currency: item.currency,
                eventDate: tradeDate,
                note: isBuy ? "买入票面利息" : "卖出票面利息"
            ))
        }

        item.updatedAt = .now
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

struct BondSettlementConfirmSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var bonds: [BondHolding]

    let bondID: UUID

    @State private var actualDate = Date()
    @State private var incomeText = ""
    @State private var redeemFaceText = ""
    @State private var redeemCostText = ""
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var item: BondHolding? {
        bonds.first { $0.id == bondID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        LabeledContent("产品", value: item.name)
                        LabeledContent("到期日", value: item.maturityDateText)
                        LabeledContent("预计到账日", value: item.expectedRedemptionDateText)
                        LabeledContent("持有面值", value: MoneyFormat.compact(item.faceValue))
                    }
                    Section {
                        DatePicker("实际到账日期", selection: $actualDate, displayedComponents: .date)
                        LabeledContent("本次兑付收益") {
                            DecimalTextField(placeholder: "无收益填 0", text: $incomeText)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("赎回面值") {
                            DecimalTextField(placeholder: "可不赎回填 0", text: $redeemFaceText)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("冲减成本") {
                            DecimalTextField(placeholder: "可不填", text: $redeemCostText)
                                .frame(minHeight: 36)
                        }
                    } header: {
                        Text("到期赎回")
                    } footer: {
                        Text("至少填写兑付收益或赎回面值之一。确认后生成「兑付收益到账」和/或「到期赎回」流水。")
                    }
                } else {
                    ContentUnavailableView("债券不存在", systemImage: "tray")
                }
            }
            .navigationTitle("到期赎回")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不赎回") {
                        BondSettlementPromptStore.markPrompted(bondID)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { confirm() }
                        .disabled(item == nil)
                }
            }
            .alert("无法确认", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { loadIfNeeded() }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let item else { return }
        actualDate = item.expectedRedemptionDate ?? item.maturityDate ?? .now
        redeemFaceText = DecimalMath.plainString(item.faceValue, fractionDigits: 2)
        redeemCostText = item.cost > 0 ? DecimalMath.plainString(item.cost, fractionDigits: 2) : ""
        if item.accruedInterest > 0 {
            incomeText = DecimalMath.plainString(item.accruedInterest, fractionDigits: 2)
        }
    }

    private func confirm() {
        guard let item else { return }
        let income = DecimalMath.parse(incomeText.isEmpty ? "0" : incomeText) ?? 0
        let face = DecimalMath.parse(redeemFaceText.isEmpty ? "0" : redeemFaceText) ?? 0
        let cost = DecimalMath.parse(redeemCostText.isEmpty ? "0" : redeemCostText) ?? 0
        guard income >= 0, face >= 0, cost >= 0 else {
            errorMessage = "金额不能为负"
            return
        }
        guard income > 0 || face > 0 || cost > 0 else {
            errorMessage = "请填写兑付收益或赎回面值"
            return
        }
        guard face <= item.faceValue else {
            errorMessage = "赎回面值不能大于当前持有面值"
            return
        }
        guard cost <= item.cost else {
            errorMessage = "冲减成本不能大于当前成本"
            return
        }
        guard BondSettlementService.confirmArrival(
            item,
            actualDate: actualDate,
            income: income,
            redeemFace: face,
            redeemCost: cost,
            context: context
        ) else {
            errorMessage = "保存失败，请重试"
            return
        }
        dismiss()
    }
}

private func currencyRegionFlag(_ currency: String) -> String {
    switch currency.uppercased() {
    case "HKD": return "🇭🇰"
    case "USD": return "🇺🇸"
    default: return "🇨🇳"
    }
}

// MARK: - 外币

struct FXSavingsManageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Environment(\.wealthSummary) private var wealthSummary
    @Query(sort: \FXSavingsAccount.updatedAt, order: .reverse) private var items: [FXSavingsAccount]
    @Query private var settingsList: [AppSettings]
    @State private var editor: ManualEditorSession?
    @State private var pendingDeleteID: UUID?
    @State private var confirmDeleteFX = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var fxRateNote: String {
        var parts: [String] = []
        if let usd = settings.rateToCNYMap["USD"] {
            parts.append(MoneyFormat.fxLine(code: "USD", rateToCNY: usd))
        }
        if let hkd = settings.rateToCNYMap["HKD"] {
            parts.append(MoneyFormat.fxLine(code: "HKD", rateToCNY: hkd))
        }
        let source = settings.fxSource.isEmpty ? "—" : settings.fxSource
        let time = settings.lastFXRefresh.map { MoneyFormat.dateTime($0) } ?? "尚未刷新"
        if parts.isEmpty {
            return "汇率来源 \(source) · \(time)"
        }
        return "\(parts.joined(separator: " · "))\n汇率来源 \(source) · \(time)"
    }

    var body: some View {
        List {
            Section {
                Text(fxRateNote)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if items.isEmpty {
                Section {
                    categoryEmptyBlock(message: "暂无外币资产", actionTitle: "添加外币") {
                        editor = .create(.fxSavings, depositKind: .demand)
                    }
                    .wkCategoryCardRow()
                }
            } else {
                Section {
                    ForEach(items, id: \.id) { item in
                        NavigationLink {
                            FXHoldingDetailView(accountID: item.id)
                        } label: {
                            fxCard(item)
                        }
                        .wkCategoryCardRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteID = item.id
                                confirmDeleteFX = true
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }
                            .tint(.red)
                            Button {
                                editor = .editFX(item.id)
                            } label: {
                                Label("修改", systemImage: "pencil")
                            }
                            .tint(theme.accent)
                        }
                    }
                } header: {
                    Text("外币")
                }
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle("外币")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .create(.fxSavings, depositKind: .demand) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editor) { session in
            ManualAssetEditorView(session: session)
        }
        .alert("删除该外币账户？", isPresented: $confirmDeleteFX) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID,
                   let item = items.first(where: { $0.id == id }) {
                    deleteFX(item)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("将删除该外币账户及其相关流水，此操作不可撤销。")
        }
    }

    private func fxCard(_ item: FXSavingsAccount) -> some View {
        let rate = settings.rateToCNY(for: item.currency)
        let valueCNY = item.marketValueNative * rate
        let interestCNY = (item.receivedInterest + item.accruedInterest) * rate
        let weight = wealthSummary?.allocationWeight(forValueCNY: valueCNY) ?? 0
        return CategoryHoldingCard(
            title: item.name,
            topTrailing: "利率 \(MoneyFormat.compact(item.annualRate * 100))%",
            flag: currencyRegionFlag(item.currency),
            metaParts: [
                item.currency,
                MoneyFormat.compact(item.balance),
                MoneyFormat.fxLine(code: item.currency, rateToCNY: rate)
            ],
            weight: weight,
            column1: ("已收利息", "¥\(MoneyFormat.compact(item.receivedInterest * rate))"),
            column2: ("余额", "¥\(MoneyFormat.compact(item.balance * rate))"),
            column3: (
                "总收益",
                "¥\(MoneyFormat.compact(interestCNY, sign: true))",
                interestCNY
            )
        )
    }

    private func deleteFX(_ item: FXSavingsAccount) {
        let id = item.id.uuidString
        ((try? context.fetch(FetchDescriptor<ManualCapitalEvent>())) ?? [])
            .filter { $0.assetID == id }.forEach(context.delete)
        context.delete(item)
        try? context.save()
    }
}

// MARK: - 现金/其他

private struct CashOtherAmountSession: Identifiable {
    enum Mode { case setBalance }
    let id = UUID()
    let assetID: UUID
    let mode: Mode
}

struct CashOtherManageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query(sort: \CashOtherAsset.updatedAt, order: .reverse) private var items: [CashOtherAsset]
    @Query private var settingsList: [AppSettings]
    @State private var editor: ManualEditorSession?
    @State private var amountSession: CashOtherAmountSession?
    @State private var pendingDeleteID: UUID?
    @State private var confirmDeleteCash = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    /// 同类物件归组展示，每件仍独占一行
    private var groupedItems: [(kind: CashOtherKind, items: [CashOtherAsset])] {
        let order = CashOtherKind.allCases
        let buckets = Dictionary(grouping: items) { $0.kind }
        return order.compactMap { kind in
            guard let list = buckets[kind], !list.isEmpty else { return nil }
            return (kind, list)
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                Section {
                    categoryEmptyBlock(message: "暂无物件或现金记录", actionTitle: "添加物件") {
                        editor = .create(.cashOther, depositKind: .demand)
                    }
                    .wkCategoryCardRow()
                }
            } else {
                ForEach(groupedItems, id: \.kind) { group in
                    Section {
                        ForEach(group.items, id: \.id) { item in
                            CashOtherItemCard(
                                item: item,
                                kind: item.kind,
                                rateToCNY: settings.rateToCNY(for: item.currency),
                                onEditAmount: {
                                    amountSession = CashOtherAmountSession(assetID: item.id, mode: .setBalance)
                                }
                            )
                            .wkCategoryCardRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeleteID = item.id
                                    confirmDeleteCash = true
                                } label: {
                                    Label("删除", systemImage: "trash.fill")
                                }
                                .tint(.red)
                                Button {
                                    editor = .editCash(item.id)
                                } label: {
                                    Label("修改资料", systemImage: "pencil")
                                }
                                .tint(theme.accent)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: group.kind.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(group.kind.title)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle("现金/其他")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .create(.cashOther, depositKind: .demand) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editor) { session in
            ManualAssetEditorView(session: session)
        }
        .sheet(item: $amountSession) { session in
            CashOtherAmountSheet(session: session)
        }
        .alert("删除该记录？", isPresented: $confirmDeleteCash) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID,
                   let item = items.first(where: { $0.id == id }) {
                    deleteCash(item)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("将删除该现金/其他资产及其相关流水，此操作不可撤销。")
        }
    }

    private func deleteCash(_ item: CashOtherAsset) {
        let id = item.id.uuidString
        ((try? context.fetch(FetchDescriptor<ManualCapitalEvent>())) ?? [])
            .filter { $0.assetID == id }.forEach(context.delete)
        context.delete(item)
        try? context.save()
    }
}

/// 单行物件卡：肖像 + 名称/类型 + 金额 + 改金额
private struct CashOtherItemCard: View {
    @Environment(\.wkTheme) private var theme

    let item: CashOtherAsset
    let kind: CashOtherKind
    let rateToCNY: Decimal
    let onEditAmount: () -> Void

    private var hasAmount: Bool { item.balance > 0 }
    private var isForeign: Bool { item.currency.uppercased() != "CNY" }

    private var soft: Color {
        theme.isNight ? Color(hex: kind.strongHex).opacity(0.22) : Color(hex: kind.softHex)
    }

    private var strong: Color {
        Color(hex: kind.strongHex).opacity(theme.isNight ? 0.95 : 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(soft)
                Image(systemName: kind.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(strong)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(kind.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(strong)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(soft)
                        )
                    Text(item.currency)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    if !item.note.isEmpty {
                        Text("· \(item.note)")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                if hasAmount, isForeign {
                    Text("市值 ¥\(MoneyFormat.compact(item.balance * rateToCNY))")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if hasAmount {
                    Text(MoneyFormat.compact(item.balance))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("未估价")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                }

                Button(action: onEditAmount) {
                    Text("改金额")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(strong)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(soft)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.separator.opacity(theme.isNight ? 0.5 : 0.35), lineWidth: 1)
        )
        .shadow(
            color: theme.isNight ? .clear : Color.black.opacity(0.03),
            radius: 8,
            y: 2
        )
    }
}

private struct CashOtherAmountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme

    let session: CashOtherAmountSession

    @Query private var items: [CashOtherAsset]
    @State private var balanceText = ""
    @State private var errorMessage: String?

    private var item: CashOtherAsset? {
        items.first { $0.id == session.assetID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let item {
                        LabeledContent("物件", value: item.name)
                    }
                    LabeledContent("金额") {
                        DecimalTextField(placeholder: "可不填，留空为 0", text: $balanceText)
                            .frame(height: 40)
                    }
                }
                .listRowBackground(theme.cardBackground)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(theme.destructive)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.pageBackground)
            .navigationTitle("改金额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let item else { return }
                balanceText = item.balance > 0
                    ? DecimalMath.plainString(item.balance, fractionDigits: 2)
                    : ""
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let item else {
            errorMessage = "记录不存在"
            return
        }
        let trimmed = balanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount: Decimal
        if trimmed.isEmpty {
            amount = 0
        } else if let parsed = DecimalMath.parse(trimmed), parsed >= 0 {
            amount = parsed
        } else {
            errorMessage = "请填写有效金额"
            return
        }

        let previous = item.balance
        item.balance = amount
        item.updatedAt = .now

        let delta = amount - previous
        if delta != 0 {
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .cashOther,
                kind: .adjustPrincipal,
                amount: abs(delta),
                currency: item.currency,
                note: delta > 0 ? "调增金额" : "调减金额"
            ))
        }
        try? context.save()
        dismiss()
    }
}

struct CashOtherDetailView: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.modelContext) private var context
    let assetID: UUID

    @Query private var items: [CashOtherAsset]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ManualCapitalEvent.eventDate, order: .reverse) private var events: [ManualCapitalEvent]
    @State private var eventFilter: ManualEventFilter = .all
    @State private var editEventID: UUID?
    @State private var pendingDeleteEventID: UUID?
    @State private var confirmDeleteEvent = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var item: CashOtherAsset? {
        items.first { $0.id == assetID }
    }

    private var relatedEvents: [ManualCapitalEvent] {
        let id = assetID.uuidString
        let all = events.filter { $0.assetID == id && $0.assetClass == .cashOther }
        return all.filter { eventFilter.matches($0.kind) }
    }

    var body: some View {
        Group {
            if let item {
                let rate = settings.rateToCNY(for: item.currency)
                List {
                    Section {
                        HStack(spacing: 10) {
                            Text(currencyRegionFlag(item.currency))
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.title3.weight(.semibold))
                                Text("现金/其他 · \(item.currency)")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("持仓概览") {
                        LabeledContent("市值(CNY)") {
                            Text(MoneyFormat.compact(item.balance * rate)).monospacedDigit()
                        }
                        .listRowBackground(theme.cardBackground)
                        LabeledContent("余额") {
                            Text("\(MoneyFormat.compact(item.balance)) \(item.currency)").monospacedDigit()
                        }
                        .listRowBackground(theme.cardBackground)
                        if item.currency != "CNY" {
                            LabeledContent("汇率") {
                                Text(MoneyFormat.fxLine(code: item.currency, rateToCNY: rate))
                                    .font(.caption)
                            }
                            .listRowBackground(theme.cardBackground)
                        }
                        if !item.note.isEmpty {
                            LabeledContent("备注") { Text(item.note) }
                                .listRowBackground(theme.cardBackground)
                        }
                    }

                    Section {
                        Picker("筛选", selection: $eventFilter) {
                            ForEach(ManualEventFilter.allCases) { filter in
                                Text(filter.title(inbound: "存入", outbound: "取出")).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                        if relatedEvents.isEmpty {
                            Text("暂无符合条件的流水")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                        } else {
                            ForEach(relatedEvents, id: \.id) { ev in
                                NavigationLink {
                                    ManualCapitalEventDetailView(eventID: ev.id)
                                } label: {
                                    ManualEventCardRow(
                                        event: ev,
                                        assetName: item.name,
                                        accent: manualEventAccent(for: ev.kind, theme: theme)
                                    )
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteEventID = ev.id
                                        confirmDeleteEvent = true
                                    } label: {
                                        Label("删除", systemImage: "trash.fill")
                                    }
                                    .tint(.red)
                                    Button {
                                        editEventID = ev.id
                                    } label: {
                                        Label("修改", systemImage: "pencil")
                                    }
                                    .tint(theme.accent)
                                }
                            }
                        }
                    } header: {
                        Text("流水记录")
                    } footer: {
                        Text("点按进入详情。")
                    }
                }
                .wkPageChrome()
            } else {
                ContentUnavailableView("记录不存在", systemImage: "tray")
            }
        }
        .navigationTitle("持仓详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editEventID) { id in
            ManualCapitalEventDetailView(eventID: id)
        }
        .alert("删除这笔流水？", isPresented: $confirmDeleteEvent) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteEventID,
                   let event = events.first(where: { $0.id == id }) {
                    deleteEvent(event)
                }
                pendingDeleteEventID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteEventID = nil }
        } message: {
            Text("将撤销该流水对余额的影响，此操作不可撤销。")
        }
    }

    private func deleteEvent(_ event: ManualCapitalEvent) {
        guard let item else { return }
        switch event.kind {
        case .deposit, .adjustPrincipal:
            item.balance = max(0, item.balance - event.amount)
        case .withdraw, .maturityRedeem:
            item.balance += event.amount
        case .interestReceived:
            break
        }
        item.updatedAt = .now
        context.delete(event)
        try? context.save()
    }
}

// MARK: - 类别详情卡片（对齐投资组合卡片样式）

/// 通用持仓卡片：名称 / 副指标 / 元数据+占比 / 三列指标
struct CategoryHoldingCard: View {
    @Environment(\.wkTheme) private var theme

    var title: String
    var topTrailing: String?
    var flag: String
    var metaParts: [String]
    var weight: Decimal
    var column1: (label: String, value: String)
    var column2: (label: String, value: String)
    /// amount 非 nil 时用主题涨跌色；nil 时用一级文字色
    var column3: (label: String, value: String, amount: Decimal?)

    private var weightPercent: Double {
        DecimalMath.double(max(0, min(weight, 1))) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let topTrailing, !topTrailing.isEmpty {
                    Text(topTrailing)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 4) {
                    Text(flag)
                        .font(.caption)
                    Text(metaParts.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(theme.secondaryCardBackground)
                            Capsule()
                                .fill(theme.warning.opacity(0.85))
                                .frame(width: max(4, geo.size.width * CGFloat(weightPercent / 100)))
                        }
                    }
                    .frame(width: 36, height: 4)
                    Text(String(format: "%.1f%%", weightPercent))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .monospacedDigit()
                }
            }

            Divider()
                .background(theme.separator)

            HStack(alignment: .top) {
                metricColumn(label: column1.label, value: column1.value, alignment: .leading, color: theme.primaryText)
                Spacer(minLength: 4)
                metricColumn(label: column2.label, value: column2.value, alignment: .center, color: theme.primaryText)
                Spacer(minLength: 4)
                metricColumn(
                    label: column3.label,
                    value: column3.value,
                    alignment: .trailing,
                    color: column3.amount.map { theme.marketPnL($0) } ?? theme.primaryText
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
    }

    private func metricColumn(label: String, value: String, alignment: HorizontalAlignment, color: Color) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
    }
}

struct SecurityPortfolioCard: View {
    let item: PositionValuation
    /// 当前类目（股票页 / 基金页）内持仓市值合计，用于组合占比
    let categoryTotalCNY: Decimal

    private var weight: Decimal {
        guard categoryTotalCNY > 0, item.quantity > 0 else { return 0 }
        return item.marketValueCNY / categoryTotalCNY
    }

    var body: some View {
        SecurityHoldingListCard(
            item: item,
            weight: weight,
            heroStyle: .hidden,
            footerStyle: .portfolioWeight
        )
    }
}

/// 股票 / 基金列表卡：与债券列表同结构
private struct SecurityHoldingListCard: View {
    @Environment(\.wkTheme) private var theme

    let item: PositionValuation
    let weight: Decimal
    var heroStyle: SecurityHoldingCardHero = .hidden
    var footerStyle: SecurityHoldingCardFooter = .portfolioWeight

    enum SecurityHoldingCardHero {
        /// 列表：不显示右上角
        case hidden
        /// 详情：显示净值 / 收盘价
        case quotePrice
    }

    enum SecurityHoldingCardFooter {
        case portfolioWeight
        case none
    }

    private var accent: BondCardAccent {
        BondCardAccent.palette(at: abs(item.instrumentID.hashValue), isNight: theme.isNight)
    }

    private var isFundLike: Bool {
        item.instrumentType == .fund || item.market == .cnFund
    }

    private var isETF: Bool {
        item.instrumentType == .etf
    }

    private var quantityUnit: String {
        isFundLike ? "份" : "股"
    }

    private var totalReturnCNY: Decimal {
        item.unrealizedPnLCNY + item.realizedPnLCNY
    }

    private var isClosed: Bool {
        item.quantity <= 0
    }

    private var weightPercent: Double {
        DecimalMath.double(max(0, min(weight, 1))) * 100
    }

    private var tagText: String {
        if isClosed { return "已清仓" }
        return item.instrumentType.displayName
    }

    private var iconName: String {
        if isFundLike { return "chart.pie.fill" }
        if isETF { return "square.stack.3d.up.fill" }
        return "chart.line.uptrend.xyaxis"
    }

    /// 详情右上角：基金用「当日净值」，股票用「收盘价」（数值同源 formattedPrice）
    private var heroPriceLabel: String {
        if isFundLike { return "当日净值" }
        return item.priceLabel == "现价" ? "收盘价" : item.priceLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            metricsBlock
            if footerStyle != .none {
                footerBlock
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
        )
        .shadow(
            color: theme.isNight ? .clear : Color.black.opacity(0.04),
            radius: 10,
            y: 3
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.soft)
                Image(systemName: iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent.strong)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name.isEmpty ? item.symbol : item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(tagText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isClosed ? theme.warning : theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.secondaryCardBackground)
                        )

                    Text("\(item.market.regionFlag) \(item.symbol) · \(MoneyFormat.quantity(item.quantity)) \(quantityUnit)")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if heroStyle == .quotePrice {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(heroPriceLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                    Text(item.formattedPrice)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent.strong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var metricsBlock: some View {
        HStack(spacing: 0) {
            metricColumn(
                label: "已收分红",
                value: MoneyFormat.compact(item.dividendsCNY),
                tint: theme.primaryText
            )
            metricColumn(
                label: "成本",
                value: MoneyFormat.compact(item.averageCost, fractionDigits: isFundLike ? 3 : 2),
                tint: theme.primaryText
            )
            metricColumn(
                label: "总收益",
                value: MoneyFormat.compact(totalReturnCNY, sign: true),
                tint: accent.strong,
                showTrend: totalReturnCNY != 0
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.soft.opacity(theme.isNight ? 0.85 : 1))
        )
    }

    private var footerBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(isClosed ? "清仓状态" : "组合占比")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                Text(isClosed ? "已清仓" : String(format: "%.1f%%", weightPercent))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isClosed ? theme.warning : theme.primaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.separator.opacity(theme.isNight ? 0.8 : 0.65))
                    Capsule()
                        .fill(accent.strong)
                        .frame(width: max(isClosed ? 0 : 4, geo.size.width * CGFloat(weightPercent / 100)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.secondaryCardBackground.opacity(theme.isNight ? 0.7 : 0.85))
        )
    }

    private func metricColumn(
        label: String,
        value: String,
        tint: Color,
        showTrend: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 2) {
                if showTrend {
                    Image(systemName: totalReturnCNY >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CategoryDetailScaffold<Content: View>: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.wkTabBarClearance) private var tabBarClearance
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, tabBarClearance, for: .scrollContent)
        .background {
            theme.pageBackground.ignoresSafeArea(edges: .all)
        }
        .toolbarBackground(theme.pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.isNight ? .dark : .light, for: .navigationBar)
    }
}

struct CategorySectionHeader: View {
    @Environment(\.wkTheme) private var theme
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

func categoryEmptyBlock(message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
    CategoryEmptyBlock(message: message, actionTitle: actionTitle, action: action)
}

private struct CategoryEmptyBlock: View {
    @Environment(\.wkTheme) private var theme
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .foregroundStyle(theme.secondaryText)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 股票（证券交易录入）

struct EquityManageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query private var settingsList: [AppSettings]
    @Query private var instruments: [Instrument]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]
    @Query private var deposits: [BankDepositAccount]
    @Query private var fxSavings: [FXSavingsAccount]
    @Query private var bonds: [BondHolding]
    @Query private var cashOthers: [CashOtherAsset]
    @Query private var liabilities: [LiabilityRecord]
    @Query private var capitalEvents: [ManualCapitalEvent]
    @Query private var lifestyleEntries: [LifestyleEntry]
    @Query(sort: \TransactionRecord.tradeDate, order: .reverse) private var transactions: [TransactionRecord]
    @State private var tradeSheet: TransactionPrefill?
    @State private var editingInstrumentID: String?
    @State private var pendingDeleteInstrumentID: String?
    @State private var confirmDeleteHolding = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var useMock: Bool { settings.useMockMarketData }

    private var wealth: WealthSummary {
        WealthSummaryEngine.summarize(
            instruments: instruments,
            positions: positions,
            quotes: quotes,
            settings: settings,
            deposits: deposits,
            fxSavings: fxSavings,
            bonds: bonds,
            cashOthers: cashOthers,
            liabilities: liabilities,
            capitalEvents: capitalEvents,
            lifestyleEntries: lifestyleEntries
        )
    }

    private var equityPositions: [PositionValuation] {
        wealth.equityAndFund.positions.filter { pos in
            pos.market != .cnFund && pos.instrumentType != .fund
        }
    }

    private var stockPositions: [PositionValuation] {
        equityPositions.filter { $0.instrumentType != .etf }
    }

    private var etfPositions: [PositionValuation] {
        equityPositions.filter { $0.instrumentType == .etf }
    }

    /// 已清仓但仍有交易流水的标的（不占资产合计）
    private var closedEquityPositions: [PositionValuation] {
        let activeIDs = Set(equityPositions.map(\.instrumentID))
        return positions.compactMap { pos -> PositionValuation? in
            guard pos.quantity <= 0 else { return nil }
            guard !activeIDs.contains(pos.instrumentID) else { return nil }
            guard transactions.contains(where: { $0.instrumentID == pos.instrumentID }) else { return nil }
            guard let valuation = PortfolioEngine.valuationIncludingClosed(
                instrumentID: pos.instrumentID,
                instruments: instruments,
                positions: positions,
                quotes: quotes,
                settings: settings
            ) else { return nil }
            guard valuation.market != .cnFund, valuation.instrumentType != .fund else { return nil }
            return valuation
        }
        .sorted { $0.symbol < $1.symbol }
    }

    private var categoryTotalCNY: Decimal {
        max(equityPositions.reduce(Decimal(0)) { $0 + $1.marketValueCNY }, 0)
    }

    var body: some View {
        List {
            if equityPositions.isEmpty && closedEquityPositions.isEmpty {
                Section {
                    categoryEmptyBlock(message: "暂无股票持仓", actionTitle: "录入买入") {
                        tradeSheet = TransactionPrefill(kind: .buy)
                    }
                    .wkCategoryCardRow()
                }
            } else {
                equitySection(title: "股票", items: stockPositions, allowClear: true)
                equitySection(title: "ETF", items: etfPositions, allowClear: true)
                equitySection(title: "已清仓", items: closedEquityPositions, allowClear: false)
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle("股票")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    tradeSheet = TransactionPrefill(kind: .buy)
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $tradeSheet) { prefill in
            AddTransactionView(useMockMarketData: useMock, prefill: prefill)
        }
        .sheet(isPresented: Binding(
            get: { editingInstrumentID != nil },
            set: { if !$0 { editingInstrumentID = nil } }
        )) {
            if let id = editingInstrumentID {
                AddTransactionView(
                    useMockMarketData: useMock,
                    presentationTitle: "修改资料",
                    editingInstrumentID: id
                )
            }
        }
        .alert("清空持仓？", isPresented: $confirmDeleteHolding) {
            Button("卖出清仓", role: .destructive) {
                if let id = pendingDeleteInstrumentID {
                    clearHolding(instrumentID: id)
                }
                pendingDeleteInstrumentID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteInstrumentID = nil }
        } message: {
            Text("将新增一笔卖出记录，不会删除标的与历史交易。")
        }
    }

    @ViewBuilder
    private func equitySection(title: String, items: [PositionValuation], allowClear: Bool) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    NavigationLink {
                        SecurityHoldingDetailView(instrumentID: item.instrumentID, mode: .equity)
                    } label: {
                        SecurityPortfolioCard(item: item, categoryTotalCNY: categoryTotalCNY)
                    }
                    .wkCategoryCardRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if allowClear {
                            Button(role: .destructive) {
                                pendingDeleteInstrumentID = item.instrumentID
                                confirmDeleteHolding = true
                            } label: {
                                Label("清空持仓", systemImage: "trash.fill")
                            }
                            .tint(.red)
                        }
                        Button {
                            editingInstrumentID = item.instrumentID
                        } label: {
                            Label("修改", systemImage: "pencil")
                        }
                        .tint(theme.accent)
                    }
                }
            } header: {
                Text(title)
            }
        }
    }

    private func clearHolding(instrumentID: String) {
        guard let item = equityPositions.first(where: { $0.instrumentID == instrumentID }) else { return }
        PositionClearService.clearSecurityHolding(
            instrumentID: instrumentID,
            quantity: item.quantity,
            price: item.marketPrice > 0 ? item.marketPrice : item.averageCost,
            context: context
        )
    }
}

// MARK: - 基金

struct FundManageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query private var settingsList: [AppSettings]
    @Query private var instruments: [Instrument]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]
    @Query private var deposits: [BankDepositAccount]
    @Query private var fxSavings: [FXSavingsAccount]
    @Query private var bonds: [BondHolding]
    @Query private var cashOthers: [CashOtherAsset]
    @Query private var liabilities: [LiabilityRecord]
    @Query private var capitalEvents: [ManualCapitalEvent]
    @Query private var lifestyleEntries: [LifestyleEntry]
    @Query(sort: \TransactionRecord.tradeDate, order: .reverse) private var transactions: [TransactionRecord]
    @State private var tradeSheet: TransactionPrefill?
    @State private var editingInstrumentID: String?
    @State private var pendingDeleteInstrumentID: String?
    @State private var confirmDeleteHolding = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var useMock: Bool { settings.useMockMarketData }

    private var wealth: WealthSummary {
        WealthSummaryEngine.summarize(
            instruments: instruments,
            positions: positions,
            quotes: quotes,
            settings: settings,
            deposits: deposits,
            fxSavings: fxSavings,
            bonds: bonds,
            cashOthers: cashOthers,
            liabilities: liabilities,
            capitalEvents: capitalEvents,
            lifestyleEntries: lifestyleEntries
        )
    }

    private var fundPositions: [PositionValuation] {
        wealth.equityAndFund.positions.filter { pos in
            pos.market == .cnFund || pos.instrumentType == .fund
        }
    }

    private var closedFundPositions: [PositionValuation] {
        let activeIDs = Set(fundPositions.map(\.instrumentID))
        return positions.compactMap { pos -> PositionValuation? in
            guard pos.quantity <= 0 else { return nil }
            guard !activeIDs.contains(pos.instrumentID) else { return nil }
            guard transactions.contains(where: { $0.instrumentID == pos.instrumentID }) else { return nil }
            guard let valuation = PortfolioEngine.valuationIncludingClosed(
                instrumentID: pos.instrumentID,
                instruments: instruments,
                positions: positions,
                quotes: quotes,
                settings: settings
            ) else { return nil }
            guard valuation.market == .cnFund || valuation.instrumentType == .fund else { return nil }
            return valuation
        }
        .sorted { $0.symbol < $1.symbol }
    }

    private var categoryTotalCNY: Decimal {
        max(fundPositions.reduce(Decimal(0)) { $0 + $1.marketValueCNY }, 0)
    }

    var body: some View {
        List {
            if fundPositions.isEmpty && closedFundPositions.isEmpty {
                Section {
                    categoryEmptyBlock(message: "暂无基金", actionTitle: "录入基金") {
                        tradeSheet = TransactionPrefill(kind: .buy, preferredMarket: .cnFund, preferredType: .fund)
                    }
                    .wkCategoryCardRow()
                }
            } else {
                fundSection(title: "基金", items: fundPositions, allowClear: true)
                fundSection(title: "已清仓", items: closedFundPositions, allowClear: false)
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle("基金")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    tradeSheet = TransactionPrefill(kind: .buy, preferredMarket: .cnFund, preferredType: .fund)
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $tradeSheet) { prefill in
            AddTransactionView(useMockMarketData: useMock, prefill: prefill)
        }
        .sheet(isPresented: Binding(
            get: { editingInstrumentID != nil },
            set: { if !$0 { editingInstrumentID = nil } }
        )) {
            if let id = editingInstrumentID {
                AddTransactionView(
                    useMockMarketData: useMock,
                    presentationTitle: "修改资料",
                    editingInstrumentID: id
                )
            }
        }
        .alert("清空持仓？", isPresented: $confirmDeleteHolding) {
            Button("卖出清仓", role: .destructive) {
                if let id = pendingDeleteInstrumentID {
                    clearHolding(instrumentID: id)
                }
                pendingDeleteInstrumentID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteInstrumentID = nil }
        } message: {
            Text("将新增一笔卖出记录，不会删除标的与历史交易。")
        }
    }

    @ViewBuilder
    private func fundSection(title: String, items: [PositionValuation], allowClear: Bool) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    NavigationLink {
                        SecurityHoldingDetailView(instrumentID: item.instrumentID, mode: .fund)
                    } label: {
                        SecurityPortfolioCard(item: item, categoryTotalCNY: categoryTotalCNY)
                    }
                    .wkCategoryCardRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if allowClear {
                            Button(role: .destructive) {
                                pendingDeleteInstrumentID = item.instrumentID
                                confirmDeleteHolding = true
                            } label: {
                                Label("清空持仓", systemImage: "trash.fill")
                            }
                            .tint(.red)
                        }
                        Button {
                            editingInstrumentID = item.instrumentID
                        } label: {
                            Label("修改", systemImage: "pencil")
                        }
                        .tint(theme.accent)
                    }
                }
            } header: {
                Text(title)
            }
        }
    }

    private func clearHolding(instrumentID: String) {
        guard let item = fundPositions.first(where: { $0.instrumentID == instrumentID }) else { return }
        PositionClearService.clearSecurityHolding(
            instrumentID: instrumentID,
            quantity: item.quantity,
            price: item.marketPrice > 0 ? item.marketPrice : item.averageCost,
            context: context
        )
    }
}

// MARK: - 证券持仓详情

enum SecurityHoldingDetailMode {
    case equity
    case fund
}

struct SecurityHoldingDetailView: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.modelContext) private var context
    let mode: SecurityHoldingDetailMode

    @Query private var settingsList: [AppSettings]
    @Query private var instruments: [Instrument]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]
    @Query(sort: \TransactionRecord.tradeDate, order: .reverse) private var transactions: [TransactionRecord]
    @State private var tradeSheet: TransactionPrefill?
    @State private var instrumentID: String
    @State private var tradeFilter: HoldingTradeFilter = .all
    @State private var editTradeID: UUID?
    @State private var pendingDeleteTradeID: UUID?
    @State private var confirmDeleteTrade = false

    init(instrumentID: String, mode: SecurityHoldingDetailMode) {
        self.mode = mode
        _instrumentID = State(initialValue: instrumentID)
    }

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var useMock: Bool { settings.useMockMarketData }

    private var item: PositionValuation? {
        PortfolioEngine.valuationIncludingClosed(
            instrumentID: instrumentID,
            instruments: instruments,
            positions: positions,
            quotes: quotes,
            settings: settings
        )
    }

    private var hasTradeHistory: Bool {
        !instrumentTrades.isEmpty
    }

    private var isClosedPosition: Bool {
        guard let item else { return false }
        return item.quantity <= 0
    }

    private var instrumentTrades: [TransactionRecord] {
        let all = transactions.filter { $0.instrumentID == instrumentID }
        switch tradeFilter {
        case .all:
            return all
        case .buy:
            return all.filter { $0.kind == .buy }
        case .sell:
            return all.filter { $0.kind == .sell }
        case .dividend:
            return all.filter { $0.kind.isDividendEvent || $0.kind == .bonusShare }
        }
    }

    var body: some View {
        Group {
            if let item, instruments.contains(where: { $0.id == instrumentID }) || hasTradeHistory {
                let accent = BondCardAccent.palette(at: abs(item.instrumentID.hashValue), isNight: theme.isNight)

                List {
                    Section {
                        SecurityHoldingListCard(
                            item: item,
                            weight: 0,
                            heroStyle: .quotePrice,
                            footerStyle: .none
                        )
                        .wkCategoryCardRow()
                        .id("\(item.quantity)-\(item.totalCost)-\(item.marketValueNative)-\(item.dividendsCNY)-\(instrumentTrades.count)")
                    }

                    Section {
                        BondDetailOverviewCard(
                            metrics: securityOverviewMetrics(item),
                            accent: accent
                        )
                        .wkCategoryCardRow()
                    } header: {
                        Text(isClosedPosition ? "清仓后概览" : "持仓概览")
                    }

                    Section {
                        if !isClosedPosition {
                            BondDetailActionsCard(
                                onBuy: { tradeSheet = TransactionPrefill(from: item, kind: .buy) },
                                onSell: { tradeSheet = TransactionPrefill(from: item, kind: .sell) },
                                onSettle: { tradeSheet = TransactionPrefill(from: item, kind: .dividend) },
                                settleTitle: "分红",
                                settleSystemImage: "gift.fill",
                                settleTint: theme.warning
                            )
                            .wkCategoryCardRow()
                        } else {
                            HoldingQuickActionBar(items: [
                                .init(
                                    id: "buy",
                                    title: "再次买入",
                                    systemImage: "plus.circle.fill",
                                    tint: theme.gain
                                ) {
                                    tradeSheet = TransactionPrefill(from: item, kind: .buy)
                                },
                            ])
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(theme.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
                            )
                            .wkCategoryCardRow()
                        }
                    }

                    Section {
                        Picker("筛选", selection: $tradeFilter) {
                            ForEach(HoldingTradeFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)

                        if instrumentTrades.isEmpty {
                            Text("暂无符合条件的交易")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(theme.cardBackground)
                                )
                                .wkCategoryCardRow()
                        } else {
                            ForEach(instrumentTrades, id: \.id) { tx in
                                NavigationLink {
                                    TransactionDetailView(transactionID: tx.id)
                                } label: {
                                    HoldingTradeCardRow(
                                        transaction: tx,
                                        symbol: item.symbol,
                                        assetName: item.name.isEmpty ? item.symbol : item.name,
                                        accent: tradeAccent(for: tx.kind)
                                    )
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(theme.cardBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(theme.separator.opacity(theme.isNight ? 0.55 : 0.35), lineWidth: 1)
                                    )
                                }
                                .wkCategoryCardRow()
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteTradeID = tx.id
                                        confirmDeleteTrade = true
                                    } label: {
                                        Label("删除", systemImage: "trash.fill")
                                    }
                                    .tint(.red)
                                    Button {
                                        editTradeID = tx.id
                                    } label: {
                                        Label("修改", systemImage: "pencil")
                                    }
                                    .tint(theme.accent)
                                }
                            }
                        }
                    } header: {
                        Text("交易记录")
                    } footer: {
                        Text(isClosedPosition ? "清仓不会删除历史交易；点按进入详情。" : "点按进入详情。")
                    }
                }
                .listStyle(.plain)
                .wkPageChrome()
            } else {
                ContentUnavailableView("持仓不存在", systemImage: "tray", description: Text("可能尚未录入交易。"))
            }
        }
        .navigationTitle("持仓详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editTradeID) { id in
            TransactionDetailView(transactionID: id)
        }
        .sheet(item: $tradeSheet, onDismiss: {
            try? context.save()
        }) { prefill in
            AddTransactionView(useMockMarketData: useMock, prefill: prefill)
        }
        .alert("删除这笔交易？", isPresented: $confirmDeleteTrade) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteTradeID,
                   let tx = transactions.first(where: { $0.id == id }) {
                    deleteTrade(tx)
                }
                pendingDeleteTradeID = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteTradeID = nil
            }
        } message: {
            Text("删除后将重建持仓，此操作不可撤销。")
        }
    }

    private func securityOverviewMetrics(_ item: PositionValuation) -> [HoldingOverviewMetric] {
        let netPnL = item.marketValueNative - item.totalCost
        let returnRate: Decimal = item.totalCost > 0 ? netPnL / item.totalCost : 0
        let qtyLabel = mode == .fund ? "份额" : "股数"
        return [
            HoldingOverviewMetric(qtyLabel, MoneyFormat.quantity(item.quantity)),
            HoldingOverviewMetric("持仓成本", MoneyFormat.compact(item.averageCost, fractionDigits: mode == .fund ? 3 : 2)),
            HoldingOverviewMetric("总成本", MoneyFormat.compact(item.totalCost)),
            HoldingOverviewMetric("市值", MoneyFormat.compact(item.marketValueNative)),
            HoldingOverviewMetric("净收益", MoneyFormat.compact(netPnL, sign: true), amountForTint: netPnL),
            HoldingOverviewMetric("收益率", MoneyFormat.percent(returnRate), amountForTint: netPnL),
            HoldingOverviewMetric("已收分红", MoneyFormat.compact(item.dividendsCNY)),
        ]
    }

    private func tradeAccent(for kind: TransactionKind) -> Color {
        switch kind {
        case .buy:
            return theme.gain
        case .sell:
            return theme.loss
        case .dividend, .dividendReinvest, .bonusShare:
            return theme.warning
        case .fee, .split:
            return theme.secondaryText
        }
    }

    private func deleteTrade(_ tx: TransactionRecord) {
        context.delete(tx)
        do {
            try context.save()
            PortfolioEngine.rebuildPositions(
                transactions: try context.fetch(FetchDescriptor<TransactionRecord>()),
                context: context
            )
        } catch {
            AppLog.error("delete trade failed: \(error.localizedDescription)")
        }
    }
}

private enum HoldingTradeFilter: String, CaseIterable, Identifiable {
    case all
    case buy
    case sell
    case dividend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .buy: return "买入"
        case .sell: return "卖出"
        case .dividend: return "分红"
        }
    }
}

private struct HoldingTradeCardRow: View {
    @Environment(\.wkTheme) private var theme
    let transaction: TransactionRecord
    let symbol: String
    let assetName: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(accent)
                Text("\(transaction.kind.displayName) \(symbol)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                Text(MoneyFormat.dateTime(transaction.tradeDate))
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }

            LabeledContent("资产") {
                Text(assetName)
                    .foregroundStyle(theme.primaryText)
            }
            .font(.subheadline)

            ForEach(detailLines, id: \.label) { line in
                LabeledContent(line.label) {
                    Text(line.value)
                        .foregroundStyle(line.emphasize ? accent : theme.primaryText)
                        .fontWeight(line.emphasize ? .semibold : .regular)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch transaction.kind {
        case .buy: return "plus.circle.fill"
        case .sell: return "minus.circle.fill"
        case .dividend, .dividendReinvest, .bonusShare: return "gift.fill"
        case .fee: return "yensign.circle.fill"
        case .split: return "arrow.triangle.branch"
        }
    }

    private var detailLines: [(label: String, value: String, emphasize: Bool)] {
        switch transaction.kind {
        case .buy, .sell:
            var lines: [(String, String, Bool)] = [
                ("单价", MoneyFormat.compact(transaction.price), true),
                ("股数", "\(MoneyFormat.quantity(transaction.quantity)) 股", false),
            ]
            if transaction.fee > 0 {
                lines.append(("佣金", MoneyFormat.compact(transaction.fee), false))
            }
            let total = transaction.kind == .buy
                ? transaction.quantity * transaction.price + transaction.fee
                : transaction.quantity * transaction.price - transaction.fee
            lines.append(("金额", MoneyFormat.compact(total), true))
            return lines
        case .dividend:
            let amount = transaction.cashAmount > 0
                ? transaction.cashAmount
                : transaction.effectiveSharesOnRecord * transaction.price
            return [("现金分红", MoneyFormat.compact(amount), true)]
        case .dividendReinvest:
            let amount = transaction.cashAmount > 0
                ? transaction.cashAmount
                : transaction.effectiveSharesOnRecord * transaction.price
            return [
                ("再投资份额", MoneyFormat.quantity(transaction.quantity), false),
                ("分红等价", MoneyFormat.compact(amount), true),
            ]
        case .bonusShare:
            return [("送股数量", MoneyFormat.quantity(transaction.quantity), true)]
        case .fee:
            let amount = transaction.cashAmount > 0 ? transaction.cashAmount : transaction.fee
            return [("费用", MoneyFormat.compact(amount), true)]
        case .split:
            return [("拆合股比例", MoneyFormat.compact(transaction.splitRatio), true)]
        }
    }
}

// MARK: - 手动资产流水（银行存款 / 债券 / 外币 / 现金）

enum ManualEventFilter: String, CaseIterable, Identifiable {
    case all
    case inbound
    case outbound
    case interest

    var id: String { rawValue }

    func title(inbound: String, outbound: String) -> String {
        switch self {
        case .all: return "全部"
        case .inbound: return inbound
        case .outbound: return outbound
        case .interest: return "利息"
        }
    }

    func matches(_ kind: ManualCapitalEventKind) -> Bool {
        switch self {
        case .all: return true
        case .inbound: return kind == .deposit || kind == .adjustPrincipal
        case .outbound: return kind == .withdraw || kind == .maturityRedeem
        case .interest: return kind == .interestReceived
        }
    }
}

struct ManualEventCardRow: View {
    @Environment(\.wkTheme) private var theme
    let event: ManualCapitalEvent
    let assetName: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(accent)
                Text(event.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                Text(MoneyFormat.dateTime(event.eventDate))
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }

            LabeledContent("资产") {
                Text(assetName)
                    .foregroundStyle(theme.primaryText)
            }
            .font(.subheadline)

            LabeledContent("金额") {
                Text("\(MoneyFormat.compact(event.amount)) \(event.currency)")
                    .foregroundStyle(accent)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)

            if !event.note.isEmpty {
                Text(event.note)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch event.kind {
        case .deposit, .adjustPrincipal: return "plus.circle.fill"
        case .withdraw, .maturityRedeem: return "minus.circle.fill"
        case .interestReceived: return "gift.fill"
        }
    }
}

/// 债券流水详情：布局对齐股票/基金「交易详情」（只改本笔流水，名称/币种只读）。
struct BondCapitalEventDetailView: View {
    let eventID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var events: [ManualCapitalEvent]
    @Query private var bonds: [BondHolding]

    @State private var kind: ManualCapitalEventKind = .deposit
    @State private var eventDate: Date = .now
    @State private var amountText = ""
    @State private var noteText = ""
    @State private var didLoad = false
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    @State private var showSavedAlert = false

    private var event: ManualCapitalEvent? {
        events.first { $0.id == eventID }
    }

    private var bond: BondHolding? {
        guard let event else { return nil }
        return bonds.first { $0.id.uuidString == event.assetID }
    }

    var body: some View {
        Group {
            if let event {
                Form {
                    Section {
                        HStack(spacing: 10) {
                            Text(currencyRegionFlag(event.currency))
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bond?.name ?? "债券")
                                    .font(.title3.weight(.semibold))
                                Text("债券 · \(event.currency)")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("交易信息") {
                        Picker("类型", selection: $kind) {
                            ForEach(ManualCapitalEventKind.allCases) { item in
                                Text(bondKindTitle(item)).tag(item)
                            }
                        }
                        DatePicker("交易日", selection: $eventDate, displayedComponents: .date)
                        if let bond {
                            LabeledContent("名称") { Text(bond.name) }
                        }
                        LabeledContent("币种") { Text(event.currency) }
                    }

                    Section("金额明细（可修改）") {
                        LabeledContent(amountLabel) {
                            DecimalTextField(placeholder: "金额", text: $amountText)
                                .frame(minHeight: 36)
                        }
                        if let amount = DecimalMath.parse(amountText), amount > 0 {
                            LabeledContent("合计") {
                                Text("\(MoneyFormat.compact(amount)) \(event.currency)")
                                    .monospacedDigit()
                            }
                        }
                    }

                    Section("备注") {
                        CJKTextField(placeholder: "可选", text: $noteText)
                            .frame(height: 40)
                    }

                    Section("系统信息") {
                        LabeledContent("录入时间") {
                            Text(MoneyFormat.dateTime(event.createdAt))
                        }
                    }

                    Section {
                        Button("删除此交易", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
                .wkPageChrome()
            } else {
                ContentUnavailableView("流水不存在", systemImage: "tray")
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveEdits() }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .alert("无法保存", isPresented: $showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("已保存", isPresented: $showSavedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("交易已更新，债券成本已同步。")
        }
        .alert("删除这笔交易？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteCurrent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将撤销该笔对债券成本的影响，此操作不可撤销。")
        }
    }

    private var amountLabel: String {
        switch kind {
        case .deposit, .adjustPrincipal: return "买入金额"
        case .withdraw: return "卖出金额"
        case .maturityRedeem: return "赎回金额"
        case .interestReceived: return "利息金额"
        }
    }

    private func bondKindTitle(_ kind: ManualCapitalEventKind) -> String {
        switch kind {
        case .deposit: return "买入增持"
        case .withdraw: return "卖出减持"
        case .maturityRedeem: return "到期赎回"
        case .adjustPrincipal: return "本金调整"
        case .interestReceived: return "利息到账"
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let event else { return }
        didLoad = true
        kind = event.kind
        eventDate = event.eventDate
        amountText = DecimalMath.plainString(event.amount, fractionDigits: 4)
        noteText = event.note
    }

    private func saveEdits() {
        guard let event else { return }
        guard let amount = DecimalMath.parse(amountText), amount > 0 else {
            errorMessage = "请填写有效金额"
            showErrorAlert = true
            return
        }

        applyBondCostDelta(
            assetID: event.assetID,
            reverseKind: event.kind,
            reverseAmount: event.amount,
            applyKind: kind,
            applyAmount: amount
        )

        event.kind = kind
        event.eventDate = eventDate
        event.amount = amount
        event.note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try context.save()
            showSavedAlert = true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func deleteCurrent() {
        guard let event else { return }
        applyBondCostDelta(
            assetID: event.assetID,
            reverseKind: event.kind,
            reverseAmount: event.amount,
            applyKind: nil,
            applyAmount: nil
        )
        context.delete(event)
        do {
            try context.save()
            dismiss()
        } catch {
            AppLog.error("delete bond event failed: \(error.localizedDescription)")
        }
    }

    private func applyBondCostDelta(
        assetID: String,
        reverseKind: ManualCapitalEventKind,
        reverseAmount: Decimal,
        applyKind: ManualCapitalEventKind?,
        applyAmount: Decimal?
    ) {
        guard let item = bonds.first(where: { $0.id.uuidString == assetID }) else { return }
        let reverse = bondSignedCost(kind: reverseKind, amount: reverseAmount)
        let apply = applyKind.flatMap { k in
            applyAmount.map { bondSignedCost(kind: k, amount: $0) }
        } ?? (cost: Decimal(0), received: Decimal(0))
        item.cost = max(0, item.cost - reverse.cost + apply.cost)
        item.receivedInterest = max(0, item.receivedInterest - reverse.received + apply.received)
        item.updatedAt = .now
    }

    private func bondSignedCost(kind: ManualCapitalEventKind, amount: Decimal) -> (cost: Decimal, received: Decimal) {
        switch kind {
        case .deposit, .adjustPrincipal:
            return (amount, 0)
        case .withdraw, .maturityRedeem:
            return (-amount, 0)
        case .interestReceived:
            return (0, amount)
        }
    }
}

struct ManualCapitalEventDetailView: View {
    let eventID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var events: [ManualCapitalEvent]
    @Query private var deposits: [BankDepositAccount]
    @Query private var bonds: [BondHolding]
    @Query private var fxAccounts: [FXSavingsAccount]
    @Query private var cashItems: [CashOtherAsset]

    // 本笔流水
    @State private var kind: ManualCapitalEventKind = .deposit
    @State private var eventDate: Date = .now
    @State private var amountText = ""
    @State private var eventNoteText = ""

    // 账户资料（与「修改资料」一致，名称/币种只读）
    @State private var assetName = ""
    @State private var currency = "CNY"
    @State private var balanceText = ""
    @State private var rateText = ""
    @State private var accruedText = ""
    @State private var receivedText = ""
    @State private var faceText = ""
    @State private var costText = ""
    @State private var couponText = ""
    @State private var marketValueText = ""
    @State private var valueDate = Date()
    @State private var hasValueDate = false
    @State private var maturityDate = Date()
    @State private var hasMaturity = false
    @State private var depositKind: BankDepositKind = .demand
    @State private var wealthStyle: BankWealthStyle = .netValue
    @State private var assetNoteText = ""
    @State private var autoReceivedInterest = false
    @State private var isWritingReceived = false
    @State private var autoAccruedInterest = false
    @State private var isWritingAccrued = false

    @State private var didLoad = false
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    @State private var showSavedAlert = false

    private var event: ManualCapitalEvent? {
        events.first { $0.id == eventID }
    }

    private var assetClass: AssetClass {
        event?.assetClass ?? .cashOther
    }

    var body: some View {
        Group {
            if let event {
                Form {
                    Section("基本信息") {
                        LabeledContent("名称") { Text(assetName) }
                        LabeledContent("币种") { Text(currency) }
                    }

                    Section("本笔流水") {
                        Picker("流水类型", selection: $kind) {
                            ForEach(ManualCapitalEventKind.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        DatePicker("流水日期", selection: $eventDate, displayedComponents: .date)
                        LabeledContent("流水金额") {
                            DecimalTextField(placeholder: "金额", text: $amountText)
                                .frame(minHeight: 36)
                        }
                        CJKTextField(placeholder: "流水备注（可选）", text: $eventNoteText)
                            .frame(height: 40)
                    }

                    if assetClass == .bankDeposit || assetClass == .fxSavings || assetClass == .cashOther {
                        Section("账户金额") {
                            LabeledContent(assetClass == .cashOther ? "余额/金额" : "余额") {
                                DecimalTextField(placeholder: "可修改", text: $balanceText)
                                    .frame(minHeight: 36)
                            }
                        }
                    }

                    if assetClass == .bankDeposit {
                        Section {
                            LabeledContent("类型") {
                                Text(depositKind.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("存款类型")
                        } footer: {
                            Text("活期、定期与理财分属不同账户，此处不可切换。请到银行存款列表分别添加。")
                        }
                    }

                    if assetClass == .bankDeposit || assetClass == .fxSavings {
                        Section {
                            LabeledContent(assetClass == .bankDeposit && depositKind == .wealth
                                           ? "年化/基准%"
                                           : "年利率%") {
                                DecimalTextField(placeholder: "如 1.5", text: $rateText)
                                    .frame(minHeight: 36)
                            }
                            Toggle("起息日", isOn: $hasValueDate)
                            if hasValueDate {
                                DatePicker("起息日", selection: $valueDate, displayedComponents: .date)
                            }
                            if assetClass == .bankDeposit
                                && (depositKind == .fixed || (depositKind == .wealth && wealthStyle == .closed)) {
                                Toggle("到期日", isOn: $hasMaturity)
                                if hasMaturity {
                                    DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                                }
                                LabeledContent(depositKind == .wealth ? "预计收益" : "预计利息") {
                                    DecimalTextField(
                                        placeholder: autoAccruedInterest ? "自动估算" : "可修改",
                                        text: $accruedText
                                    )
                                    .frame(minHeight: 36)
                                }
                                LabeledContent(depositKind == .wealth ? "已兑付收益" : "已到账利息") {
                                    DecimalTextField(placeholder: "到期或到账后填写", text: $receivedText)
                                        .frame(minHeight: 36)
                                }
                            } else {
                                LabeledContent("已到账利息") {
                                    DecimalTextField(placeholder: "可修改", text: $receivedText)
                                        .frame(minHeight: 36)
                                }
                                LabeledContent("预计利息") {
                                    DecimalTextField(placeholder: "可修改", text: $accruedText)
                                        .frame(minHeight: 36)
                                }
                                if assetClass == .fxSavings {
                                    Toggle("到期日", isOn: $hasMaturity)
                                    if hasMaturity {
                                        DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                                    }
                                }
                            }
                        } header: {
                            Text(assetClass == .bankDeposit && depositKind == .wealth ? "理财信息" : "利率与日期")
                        } footer: {
                            if assetClass == .bankDeposit
                                && (depositKind == .fixed || (depositKind == .wealth && wealthStyle == .closed)) {
                                Text("预计利息/收益按「本金×年利率×存期天数/365」自动估算，可手改。净值型理财请到银行理财编辑页更新净值。")
                            }
                        }
                    }

                    if assetClass == .bond {
                        Section("债券") {
                            LabeledContent("持有面值") {
                                DecimalTextField(placeholder: "必填", text: $faceText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("成本（可选）") {
                                DecimalTextField(placeholder: "可不填", text: $costText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("票面利率%（可选）") {
                                DecimalTextField(placeholder: "可不填", text: $couponText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("最新估值（可选）") {
                                DecimalTextField(placeholder: "可不填", text: $marketValueText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("预计利息（可选）") {
                                DecimalTextField(placeholder: "可不填", text: $accruedText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("已到账利息（可选）") {
                                DecimalTextField(placeholder: "可不填", text: $receivedText)
                                    .frame(minHeight: 36)
                            }
                            Toggle("到期日", isOn: $hasMaturity)
                            if hasMaturity {
                                DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                            }
                        }
                    }

                    Section("账户备注") {
                        CJKTextField(placeholder: "可选", text: $assetNoteText)
                            .frame(height: 40)
                    }

                    Section {
                        Button("删除此流水", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } footer: {
                        Text("名称与币种不可改（类似股票代码）。其余账户资料与本笔流水均可修改；保存时以本页填写为准。")
                    }
                }
                .wkPageChrome()
            } else {
                ContentUnavailableView("流水不存在", systemImage: "tray")
            }
        }
        .navigationTitle("流水详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveEdits() }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: rateText) { _, _ in recalculateInterestFieldsIfNeeded() }
        .onChange(of: balanceText) { _, _ in recalculateInterestFieldsIfNeeded() }
        .onChange(of: hasValueDate) { _, _ in recalculateInterestFieldsIfNeeded() }
        .onChange(of: valueDate) { _, _ in recalculateInterestFieldsIfNeeded() }
        .onChange(of: hasMaturity) { _, _ in recalculateAccruedInterestIfNeeded() }
        .onChange(of: maturityDate) { _, _ in recalculateAccruedInterestIfNeeded() }
        .onChange(of: receivedText) { _, _ in
            if !isWritingReceived { autoReceivedInterest = false }
        }
        .onChange(of: accruedText) { _, _ in
            if !isWritingAccrued { autoAccruedInterest = false }
        }
        .alert("无法保存", isPresented: $showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("已保存", isPresented: $showSavedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("账户资料与流水已更新。")
        }
        .alert("删除这笔流水？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteCurrent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将撤销该流水对账户余额的影响，账户其余资料保留。")
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let event else { return }
        didLoad = true
        kind = event.kind
        eventDate = event.eventDate
        amountText = DecimalMath.plainString(event.amount, fractionDigits: 4)
        eventNoteText = event.note
        currency = event.currency

        switch event.assetClass {
        case .bankDeposit:
            guard let item = deposits.first(where: { $0.id.uuidString == event.assetID }) else { return }
            assetName = item.name
            currency = item.currency
            balanceText = DecimalMath.plainString(item.balance)
            rateText = DecimalMath.plainString(item.annualRate * 100, fractionDigits: 4)
            accruedText = DecimalMath.plainString(item.displayAccruedInterest)
            receivedText = DecimalMath.plainString(item.receivedInterest)
            depositKind = item.depositKind
            wealthStyle = item.wealthStyle
            assetNoteText = item.note
            if let v = item.valueDate { valueDate = v; hasValueDate = true }
            if let m = item.maturityDate { maturityDate = m; hasMaturity = true }
            if item.depositKind == .fixed || (item.depositKind == .wealth && item.wealthStyle == .closed) {
                autoReceivedInterest = false
                if let est = item.estimatedMaturityInterest() {
                    autoAccruedInterest = item.accruedInterest == 0 || item.accruedInterest == est
                } else {
                    autoAccruedInterest = item.accruedInterest == 0
                }
                recalculateAccruedInterestIfNeeded()
            } else if item.depositKind == .wealth {
                autoAccruedInterest = false
                autoReceivedInterest = false
            } else {
                autoAccruedInterest = false
                autoReceivedInterest = item.receivedInterest == 0
                if autoReceivedInterest {
                    recalculateReceivedInterestIfNeeded()
                }
            }
        case .fxSavings:
            guard let item = fxAccounts.first(where: { $0.id.uuidString == event.assetID }) else { return }
            assetName = item.name
            currency = item.currency
            balanceText = DecimalMath.plainString(item.balance)
            rateText = DecimalMath.plainString(item.annualRate * 100, fractionDigits: 4)
            accruedText = DecimalMath.plainString(item.accruedInterest)
            receivedText = DecimalMath.plainString(item.receivedInterest)
            assetNoteText = item.note
            if let v = item.valueDate { valueDate = v; hasValueDate = true }
            if let m = item.maturityDate { maturityDate = m; hasMaturity = true }
            autoReceivedInterest = item.receivedInterest == 0
        case .bond:
            guard let item = bonds.first(where: { $0.id.uuidString == event.assetID }) else { return }
            assetName = item.name
            currency = item.currency
            faceText = DecimalMath.plainString(item.faceValue)
            costText = DecimalMath.plainString(item.cost)
            couponText = DecimalMath.plainString(item.couponRate * 100, fractionDigits: 4)
            if let mv = item.marketValue { marketValueText = DecimalMath.plainString(mv) }
            accruedText = DecimalMath.plainString(item.accruedInterest)
            receivedText = DecimalMath.plainString(item.receivedInterest)
            assetNoteText = item.note
            if let m = item.maturityDate { maturityDate = m; hasMaturity = true }
        case .cashOther:
            guard let item = cashItems.first(where: { $0.id.uuidString == event.assetID }) else { return }
            assetName = item.name
            currency = item.currency
            balanceText = DecimalMath.plainString(item.balance)
            assetNoteText = item.note
        default:
            break
        }
    }

    private func recalculateInterestFieldsIfNeeded() {
        recalculateReceivedInterestIfNeeded()
        recalculateAccruedInterestIfNeeded()
    }

    private func recalculateReceivedInterestIfNeeded() {
        guard assetClass == .bankDeposit || assetClass == .fxSavings else { return }
        if assetClass == .bankDeposit && (depositKind == .fixed || depositKind == .wealth) { return }
        guard autoReceivedInterest, hasValueDate else { return }
        guard let balance = DecimalMath.parse(balanceText), balance > 0 else { return }
        guard let ratePercent = DecimalMath.parse(rateText), ratePercent > 0 else { return }
        let interest = DecimalMath.simpleInterest(
            principal: balance,
            annualRate: ratePercent / 100,
            from: valueDate
        )
        isWritingReceived = true
        receivedText = DecimalMath.plainString(interest, fractionDigits: 2)
        isWritingReceived = false
    }

    private func recalculateAccruedInterestIfNeeded() {
        let useFormula = assetClass == .bankDeposit && (
            depositKind == .fixed || (depositKind == .wealth && wealthStyle == .closed)
        )
        guard useFormula else { return }
        guard autoAccruedInterest, hasValueDate, hasMaturity else { return }
        guard let balance = DecimalMath.parse(balanceText), balance > 0 else { return }
        guard let ratePercent = DecimalMath.parse(rateText), ratePercent > 0 else { return }
        let interest = DecimalMath.simpleInterest(
            principal: balance,
            annualRate: ratePercent / 100,
            from: valueDate,
            to: maturityDate
        )
        isWritingAccrued = true
        accruedText = DecimalMath.plainString(interest, fractionDigits: 2)
        isWritingAccrued = false
    }

    private func saveEdits() {
        guard let event else { return }
        guard let amount = DecimalMath.parse(amountText), amount > 0 else {
            errorMessage = "请填写有效流水金额"
            showErrorAlert = true
            return
        }

        // 账户资料以表单为准（与「修改资料」一致）；本笔流水单独更新。
        if !saveAssetProfile(for: event) {
            return
        }

        event.kind = kind
        event.eventDate = eventDate
        event.amount = amount
        event.note = eventNoteText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try context.save()
            showSavedAlert = true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    @discardableResult
    private func saveAssetProfile(for event: ManualCapitalEvent) -> Bool {
        let note = assetNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch event.assetClass {
        case .bankDeposit:
            guard let item = deposits.first(where: { $0.id.uuidString == event.assetID }) else {
                errorMessage = "存款账户不存在"; showErrorAlert = true; return false
            }
            guard let balance = DecimalMath.parse(balanceText), balance >= 0 else {
                errorMessage = "请填写有效余额"; showErrorAlert = true; return false
            }
            if depositKind == .fixed, !hasMaturity {
                errorMessage = "定期存款请填写到期日"; showErrorAlert = true; return false
            }
            if depositKind == .fixed, !hasValueDate {
                errorMessage = "定期存款请填写起息日"; showErrorAlert = true; return false
            }
            // 银行理财不强制起息日 / 到期日 / 利率
            item.balance = balance
            item.annualRate = (DecimalMath.parse(rateText) ?? 0) / 100
            var accrued = DecimalMath.parse(accruedText) ?? 0
            let needsFormula = depositKind == .fixed
                || (depositKind == .wealth && wealthStyle == .closed && hasValueDate && hasMaturity)
            if needsFormula, autoAccruedInterest, hasValueDate, hasMaturity,
               let bal = DecimalMath.parse(balanceText), bal > 0,
               let ratePercent = DecimalMath.parse(rateText), ratePercent > 0 {
                accrued = DecimalMath.simpleInterest(
                    principal: bal,
                    annualRate: ratePercent / 100,
                    from: valueDate,
                    to: maturityDate
                )
            }
            item.accruedInterest = accrued
            item.receivedInterest = DecimalMath.parse(receivedText) ?? 0
            // 流水详情里也不允许把活期/定期/理财互相改写成另一条账户。
            let lockedKind = item.depositKind
            item.depositKind = lockedKind
            item.valueDate = hasValueDate ? valueDate : nil
            item.maturityDate = (lockedKind != .demand && hasMaturity) ? maturityDate : nil
            item.note = note
            item.updatedAt = .now
        case .fxSavings:
            guard let item = fxAccounts.first(where: { $0.id.uuidString == event.assetID }) else {
                errorMessage = "外币账户不存在"; showErrorAlert = true; return false
            }
            guard let balance = DecimalMath.parse(balanceText), balance >= 0 else {
                errorMessage = "请填写有效余额"; showErrorAlert = true; return false
            }
            item.balance = balance
            item.annualRate = (DecimalMath.parse(rateText) ?? 0) / 100
            item.accruedInterest = DecimalMath.parse(accruedText) ?? 0
            item.receivedInterest = DecimalMath.parse(receivedText) ?? 0
            item.valueDate = hasValueDate ? valueDate : nil
            item.maturityDate = hasMaturity ? maturityDate : nil
            item.note = note
            item.updatedAt = .now
        case .bond:
            guard let item = bonds.first(where: { $0.id.uuidString == event.assetID }) else {
                errorMessage = "债券不存在"; showErrorAlert = true; return false
            }
            guard let face = DecimalMath.parse(faceText), face > 0 else {
                errorMessage = "请填写有效持有面值"; showErrorAlert = true; return false
            }
            let costTextTrimmed = costText.trimmingCharacters(in: .whitespacesAndNewlines)
            let cost = costTextTrimmed.isEmpty ? face : (DecimalMath.parse(costText) ?? face)
            guard cost >= 0 else {
                errorMessage = "成本不能为负"; showErrorAlert = true; return false
            }
            item.faceValue = face
            item.cost = cost
            item.couponRate = (DecimalMath.parse(couponText) ?? 0) / 100
            item.marketValue = marketValueText.isEmpty ? nil : DecimalMath.parse(marketValueText)
            item.accruedInterest = DecimalMath.parse(accruedText) ?? 0
            item.receivedInterest = DecimalMath.parse(receivedText) ?? 0
            item.maturityDate = hasMaturity ? maturityDate : nil
            item.note = note
            item.updatedAt = .now
        case .cashOther:
            guard let item = cashItems.first(where: { $0.id.uuidString == event.assetID }) else {
                errorMessage = "记录不存在"; showErrorAlert = true; return false
            }
            guard let balance = DecimalMath.parse(balanceText), balance >= 0 else {
                errorMessage = "请填写有效金额"; showErrorAlert = true; return false
            }
            item.balance = balance
            item.note = note
            item.updatedAt = .now
        default:
            break
        }
        return true
    }

    private func deleteCurrent() {
        guard let event else { return }
        applyAssetDelta(
            assetID: event.assetID,
            assetClass: event.assetClass,
            reverseKind: event.kind,
            reverseAmount: event.amount,
            applyKind: nil,
            applyAmount: nil
        )
        context.delete(event)
        do {
            try context.save()
            dismiss()
        } catch {
            AppLog.error("delete manual event failed: \(error.localizedDescription)")
        }
    }

    private func applyAssetDelta(
        assetID: String,
        assetClass: AssetClass,
        reverseKind: ManualCapitalEventKind,
        reverseAmount: Decimal,
        applyKind: ManualCapitalEventKind?,
        applyAmount: Decimal?
    ) {
        let reverse = signedImpact(kind: reverseKind, amount: reverseAmount)
        let apply = applyKind.flatMap { k in
            applyAmount.map { signedImpact(kind: k, amount: $0) }
        } ?? (balance: Decimal(0), received: Decimal(0), cost: Decimal(0))

        let balanceDelta = -reverse.balance + apply.balance
        let receivedDelta = -reverse.received + apply.received
        let costDelta = -reverse.cost + apply.cost

        switch assetClass {
        case .bankDeposit:
            if let item = deposits.first(where: { $0.id.uuidString == assetID }) {
                item.balance = max(0, item.balance + balanceDelta)
                item.receivedInterest = max(0, item.receivedInterest + receivedDelta)
                item.updatedAt = .now
            }
        case .fxSavings:
            if let item = fxAccounts.first(where: { $0.id.uuidString == assetID }) {
                item.balance = max(0, item.balance + balanceDelta)
                item.receivedInterest = max(0, item.receivedInterest + receivedDelta)
                item.updatedAt = .now
            }
        case .cashOther:
            if let item = cashItems.first(where: { $0.id.uuidString == assetID }) {
                item.balance = max(0, item.balance + balanceDelta)
                item.updatedAt = .now
            }
        case .bond:
            if let item = bonds.first(where: { $0.id.uuidString == assetID }) {
                item.cost = max(0, item.cost + costDelta)
                item.receivedInterest = max(0, item.receivedInterest + receivedDelta)
                item.updatedAt = .now
            }
        default:
            break
        }
    }

    private func signedImpact(kind: ManualCapitalEventKind, amount: Decimal) -> (balance: Decimal, received: Decimal, cost: Decimal) {
        switch kind {
        case .deposit, .adjustPrincipal:
            return (amount, 0, amount)
        case .withdraw, .maturityRedeem:
            return (-amount, 0, -amount)
        case .interestReceived:
            return (0, amount, 0)
        }
    }
}

func manualEventAccent(for kind: ManualCapitalEventKind, theme: ThemeTokens) -> Color {
    switch kind {
    case .deposit, .adjustPrincipal: return theme.gain
    case .withdraw, .maturityRedeem: return theme.loss
    case .interestReceived: return theme.warning
    }
}

// MARK: - 外币详情

struct FXHoldingDetailView: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.modelContext) private var context
    let accountID: UUID

    @Query private var items: [FXSavingsAccount]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ManualCapitalEvent.eventDate, order: .reverse) private var events: [ManualCapitalEvent]
    @State private var editor: ManualEditorSession?
    @State private var initialFlow: ManualFlowKind = .none
    @State private var eventFilter: ManualEventFilter = .all
    @State private var editEventID: UUID?
    @State private var pendingDeleteEventID: UUID?
    @State private var confirmDeleteEvent = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var item: FXSavingsAccount? {
        items.first { $0.id == accountID }
    }

    private var relatedEvents: [ManualCapitalEvent] {
        let id = accountID.uuidString
        let all = events.filter { $0.assetID == id && $0.assetClass == .fxSavings }
        return all.filter { eventFilter.matches($0.kind) }
    }

    var body: some View {
        Group {
            if let item {
                let rate = settings.rateToCNY(for: item.currency)
                List {
                    Section {
                        HStack(spacing: 10) {
                            Text(currencyRegionFlag(item.currency))
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.title3.weight(.semibold))
                                Text("外币储蓄 · \(item.currency)")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        HoldingOverviewGridCard(
                            title: "存款概览",
                            titleTrailing: item.currency,
                            metrics: fxDepositOverviewMetrics(item, rateToCNY: rate)
                        )
                        .wkOverviewListRow()
                        .id("\(item.updatedAt.timeIntervalSince1970)-\(item.balance)-\(item.accruedInterest)-\(item.receivedInterest)-\(relatedEvents.count)")
                    }

                    Section {
                        HoldingQuickActionBar(items: [
                            .init(id: "in", title: "汇入", systemImage: "plus.circle.fill", tint: theme.gain) {
                                initialFlow = .inbound
                                editor = .editFX(item.id)
                            },
                            .init(id: "out", title: "汇出", systemImage: "minus.circle.fill", tint: theme.loss) {
                                initialFlow = .outbound
                                editor = .editFX(item.id)
                            },
                        ])
                        .wkOverviewListRow()
                    }

                    Section {
                        Picker("筛选", selection: $eventFilter) {
                            ForEach(ManualEventFilter.allCases) { filter in
                                Text(filter.title(inbound: "汇入", outbound: "汇出")).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                        if relatedEvents.isEmpty {
                            Text("暂无符合条件的流水")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                        } else {
                            ForEach(relatedEvents, id: \.id) { ev in
                                NavigationLink {
                                    ManualCapitalEventDetailView(eventID: ev.id)
                                } label: {
                                    ManualEventCardRow(
                                        event: ev,
                                        assetName: item.name,
                                        accent: manualEventAccent(for: ev.kind, theme: theme)
                                    )
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteEventID = ev.id
                                        confirmDeleteEvent = true
                                    } label: {
                                        Label("删除", systemImage: "trash.fill")
                                    }
                                    .tint(.red)
                                    Button {
                                        editEventID = ev.id
                                    } label: {
                                        Label("修改", systemImage: "pencil")
                                    }
                                    .tint(theme.accent)
                                }
                            }
                        }
                    } header: {
                        Text("流水记录")
                    } footer: {
                        Text("点按进入详情。")
                    }

                    if !item.note.isEmpty {
                        Section("备注") {
                            Text(item.note)
                        }
                    }
                }
                .wkPageChrome()
            } else {
                ContentUnavailableView("外币账户不存在", systemImage: "tray")
            }
        }
        .navigationTitle("外币详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editEventID) { id in
            ManualCapitalEventDetailView(eventID: id)
        }
        .sheet(item: $editor, onDismiss: {
            if let item {
                item.updatedAt = .now
                try? context.save()
            }
        }) { session in
            ManualAssetEditorView(session: session, initialFlow: initialFlow)
        }
        .alert("删除这笔流水？", isPresented: $confirmDeleteEvent) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteEventID,
                   let event = events.first(where: { $0.id == id }) {
                    deleteEvent(event)
                }
                pendingDeleteEventID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteEventID = nil }
        } message: {
            Text("将撤销该流水对账户余额的影响，此操作不可撤销。")
        }
    }

    private func deleteEvent(_ event: ManualCapitalEvent) {
        guard let item else { return }
        switch event.kind {
        case .deposit, .adjustPrincipal:
            item.balance = max(0, item.balance - event.amount)
        case .withdraw, .maturityRedeem:
            item.balance += event.amount
        case .interestReceived:
            item.receivedInterest = max(0, item.receivedInterest - event.amount)
        }
        item.updatedAt = .now
        context.delete(event)
        try? context.save()
    }

    private func fxDepositOverviewMetrics(_ item: FXSavingsAccount, rateToCNY: Decimal) -> [HoldingOverviewMetric] {
        var metrics: [HoldingOverviewMetric] = [
            HoldingOverviewMetric("余额", MoneyFormat.compact(item.balance)),
            HoldingOverviewMetric("含预计利息", MoneyFormat.compact(item.marketValueNative)),
            HoldingOverviewMetric("市值(CNY)", MoneyFormat.compact(item.marketValueNative * rateToCNY)),
            HoldingOverviewMetric("汇率", MoneyFormat.fxLine(code: item.currency, rateToCNY: rateToCNY)),
            HoldingOverviewMetric("年利率", MoneyFormat.percent(item.annualRate)),
            HoldingOverviewMetric("预计利息", MoneyFormat.compact(item.accruedInterest)),
            HoldingOverviewMetric("已到账利息", MoneyFormat.compact(item.receivedInterest)),
            HoldingOverviewMetric(
                "起息日",
                item.valueDate.map { MoneyFormat.shortDate($0) } ?? "—"
            ),
        ]
        if item.maturityDate != nil {
            metrics.append(
                HoldingOverviewMetric(
                    "到期日",
                    item.maturityDate.map { MoneyFormat.shortDate($0) } ?? "—"
                )
            )
            metrics.append(HoldingOverviewMetric("剩余期限", item.remainingTermDescription()))
        }
        return metrics
    }
}

// MARK: - 持仓行 / 交易预填

struct TransactionPrefill: Identifiable {
    let id = UUID()
    var market: Market
    var assetType: InstrumentType
    var symbol: String
    var name: String
    var currency: String
    var kind: TransactionKind
    var filledFromSearch: Bool
    var quantityText: String
    var priceText: String

    init(
        kind: TransactionKind = .buy,
        preferredMarket: Market = .cnA,
        preferredType: InstrumentType = .stock
    ) {
        self.market = preferredMarket
        self.assetType = preferredType
        self.symbol = ""
        self.name = ""
        self.currency = preferredMarket.defaultCurrency
        self.kind = kind
        self.filledFromSearch = false
        self.quantityText = ""
        self.priceText = ""
    }

    init(from item: PositionValuation, kind: TransactionKind) {
        self.market = item.market
        self.assetType = item.instrumentType
        self.symbol = item.symbol
        self.name = item.name
        self.currency = item.currency
        self.kind = kind
        self.filledFromSearch = !item.symbol.isEmpty
        self.quantityText = (kind == .sell)
            ? DecimalMath.plainString(item.quantity, fractionDigits: 4)
            : ""
        self.priceText = ""
    }
}

private struct SecurityHoldingRow: View {
    let item: PositionValuation

    private var detailLine: String {
        var detail = "数量 \(MoneyFormat.quantity(item.quantity)) · \(item.priceLabel) \(item.formattedPrice) \(item.currency)"
        if let date = item.marketDate, !date.isEmpty {
            detail += " · \(date)"
        }
        return detail
    }

    var body: some View {
        HoldingListRow(
            flag: item.market.regionFlag,
            title: item.name.isEmpty ? item.symbol : item.name,
            valueCNY: item.marketValueCNY,
            lines: [
                "\(item.market.displayName) · \(item.symbol)",
                detailLine
            ]
        )
    }
}

/// 持仓列表统一行：旗帜 | 名称+明细左对齐 | 右侧市值
struct HoldingListRow: View {
    let flag: String
    let title: String
    let valueCNY: Decimal
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(flag)
                .font(.title3)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MoneyFormat.compact(valueCNY))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 编辑器会话（新建或修改）
enum ManualEditorSession: Identifiable {
    /// `instanceID` 保证每次打开新建表单都是独立会话，避免状态串用。
    case create(
        ManualEditorKind,
        depositKind: BankDepositKind,
        presetName: String? = nil,
        instanceID: UUID = UUID()
    )
    case editDeposit(UUID)
    case editBond(UUID)
    case editFX(UUID)
    case editCash(UUID)
    case editLiability(UUID)

    var id: String {
        switch self {
        case .create(_, _, _, let instanceID): return "create-\(instanceID.uuidString)"
        case .editDeposit(let id): return "dep-\(id)"
        case .editBond(let id): return "bond-\(id)"
        case .editFX(let id): return "fx-\(id)"
        case .editCash(let id): return "cash-\(id)"
        case .editLiability(let id): return "liab-\(id)"
        }
    }
}
