import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query(sort: \Instrument.symbol) private var instruments: [Instrument]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \TransactionRecord.tradeDate, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var deposits: [BankDepositAccount]
    @Query private var fxSavings: [FXSavingsAccount]
    @Query private var bonds: [BondHolding]
    @Query private var cashOthers: [CashOtherAsset]
    @Query private var liabilities: [LiabilityRecord]
    @Query private var capitalEvents: [ManualCapitalEvent]
    @Query private var lifestyleEntries: [LifestyleEntry]

    @State private var marketService = MarketDataService()
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var quoteUpdateFailed = false

    private var settings: AppSettings {
        settingsList.first ?? AppSettings()
    }

    private var useMock: Bool {
        settings.useMockMarketData
    }

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

    private var tradingSummary: PortfolioSummary { wealth.equityAndFund }

    private var todayReturnCNY: Decimal {
        Decimal(tradingSummary.finalDayPnLBase)
    }

    private var hasStaleQuotes: Bool {
        tradingSummary.positions.contains { $0.isStale || $0.quoteStatus == .stale }
    }

    /// 正资产五类（含 0 行，便于点进去添加）；不含外币/生活结余/负债
    private var allocationRows: [AssetAllocationSlice] {
        let order: [AssetClass] = [.bankDeposit, .bond, .fund, .equity, .cashOther]
        return order.map { cls in
            if let existing = wealth.allocation.first(where: { $0.assetClass == cls }) {
                return existing
            }
            return AssetAllocationSlice(assetClass: cls, valueCNY: 0, weight: 0)
        }
    }

    /// 资产配置分母：正资产合计（与占比一致）
    private var allocationTotalCNY: Decimal {
        allocationRows.reduce(0) { $0 + $1.valueCNY }
    }

    private var lifestyleNetCNY: Decimal {
        lifestyleEntries.reduce(Decimal(0)) {
            $0 + $1.signedAmount * settings.rateToCNY(for: $1.currency)
        }
    }

    private var missingFXCodes: [String] {
        var codes = Set<String>()
        for i in instruments where !settings.hasKnownRate(for: i.currency) {
            codes.insert(i.currency.uppercased())
        }
        for a in fxSavings where !settings.hasKnownRate(for: a.currency) {
            codes.insert(a.currency.uppercased())
        }
        for a in deposits where !settings.hasKnownRate(for: a.currency) {
            codes.insert(a.currency.uppercased())
        }
        for a in bonds where !settings.hasKnownRate(for: a.currency) {
            codes.insert(a.currency.uppercased())
        }
        for a in cashOthers where !settings.hasKnownRate(for: a.currency) {
            codes.insert(a.currency.uppercased())
        }
        for a in liabilities where !settings.hasKnownRate(for: a.currency) {
            codes.insert(a.currency.uppercased())
        }
        codes.remove("CNY")
        return codes.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if !missingFXCodes.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("缺少汇率：\(missingFXCodes.joined(separator: "、"))")
                                .font(.subheadline.weight(.semibold))
                            Text("这些币种暂时按 1:1 折算人民币，总资产可能不准。请点左上角刷新拉取汇率，或到「设置 → 汇率」查看。")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(theme.warning.opacity(0.12))
                    }
                }

                if quoteUpdateFailed || (hasStaleQuotes && !useMock && !instruments.isEmpty) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("行情暂未更新")
                                .font(.subheadline.weight(.semibold))
                            Text(useMock ? "当前为 Mock 模式。" : "公开行情接口失败或缓存已过期，可重试；失败时可手填价格。")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                            Button("重试刷新") {
                                Task { await refresh() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshing)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(theme.cardBackground)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("总资产")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                        Text(MoneyFormat.amount(wealth.totalAssetsCNY, currency: "CNY"))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.primaryText)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("净资产")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                                Text(MoneyFormat.compact(wealth.netWorthCNY))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(theme.primaryText)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("负债")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                                Text(MoneyFormat.compact(wealth.totalLiabilitiesCNY))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(theme.warning)
                            }
                        }

                        NavigationLink {
                            ReturnBreakdownView(pnl: wealth.pnl, todayReturnCNY: todayReturnCNY)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("今日收益")
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                    Text(MoneyFormat.compact(todayReturnCNY, sign: true))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(theme.marketPnL(todayReturnCNY))
                                }

                                Spacer(minLength: 12)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("累计收益")
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                    Text(MoneyFormat.compact(wealth.pnl.totalReturnCNY, sign: true))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(theme.marketPnL(wealth.pnl.totalReturnCNY))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                    }
                    .padding(.vertical, 2)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(theme.cardBackground)
                }

                Section {
                    AssetAllocationCard(
                        totalCNY: allocationTotalCNY,
                        rows: allocationRows
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 2, trailing: 16))
                    .listRowBackground(theme.cardBackground)

                    ForEach(allocationRows) { slice in
                        let active = slice.valueCNY > 0
                        NavigationLink {
                            destination(for: slice.assetClass)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(AssetAllocationPalette.color(for: slice.assetClass))
                                    .frame(width: 8, height: 8)
                                    .opacity(active ? 1 : 0.35)
                                Text(slice.assetClass.displayName)
                                    .foregroundStyle(active ? theme.primaryText : theme.secondaryText)
                                Spacer()
                                Text(MoneyFormat.compact(slice.valueCNY))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(active ? theme.primaryText : theme.secondaryText.opacity(0.7))
                                Text(String(format: "%.1f%%", DecimalMath.double(slice.weight) * 100))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(AssetAllocationPalette.color(for: slice.assetClass))
                                    .opacity(active ? 1 : 0.4)
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .font(.subheadline)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(theme.cardBackground)
                    }
                } header: {
                    Text("资产类别占比")
                }

                Section {
                    NavigationLink {
                        LifestyleLedgerView()
                    } label: {
                        HStack {
                            Text("生活结余")
                            Spacer()
                            Text(MoneyFormat.compact(lifestyleNetCNY, sign: true))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(lifestyleNetCNY >= 0 ? theme.primaryText : theme.warning)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(theme.cardBackground)
                } header: {
                    Text("生活")
                }
            }
            .listSectionSpacing(10)
            .scrollIndicators(.hidden)
            .wkPageChrome()
            .navigationTitle("WealthKeeper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .alert("刷新结果", isPresented: Binding(
                get: { refreshMessage != nil },
                set: { if !$0 { refreshMessage = nil } }
            )) {
                Button("好", role: .cancel) { refreshMessage = nil }
                if quoteUpdateFailed {
                    Button("重试") {
                        refreshMessage = nil
                        Task { await refresh() }
                    }
                }
            } message: {
                Text(refreshMessage ?? "")
            }
        }
        .background {
            theme.pageBackground.ignoresSafeArea(edges: .all)
        }
    }

    @ViewBuilder
    private func destination(for assetClass: AssetClass) -> some View {
        switch assetClass {
        case .bankDeposit:
            BankDepositsView()
        case .bond:
            BondHoldingsManageView()
        case .fxSavings:
            FXSavingsManageView()
        case .cashOther:
            CashOtherManageView()
        case .equity:
            EquityManageView()
        case .fund:
            FundManageView()
        case .lifestyle:
            LifestyleLedgerView()
        case .liability:
            ManualAssetsView()
        }
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        PortfolioEngine.rebuildPositions(transactions: transactions, context: context)

        let settings = settingsList.first ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()

        let result = await marketService.refresh(
            instruments: instruments,
            settings: settings,
            context: context
        )
        PortfolioEngine.rebuildPositions(transactions: Array(transactions), context: context)

        if result.failures.isEmpty {
            quoteUpdateFailed = false
            refreshMessage = "成功更新 \(result.success) 个标的"
            if !settings.fxSource.isEmpty {
                refreshMessage = (refreshMessage ?? "") + "\n汇率来源 \(settings.fxSource)"
            }
        } else {
            quoteUpdateFailed = true
            let detail = result.failures.prefix(3).map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            refreshMessage = "行情暂未更新\n成功 \(result.success) 个，失败 \(result.failures.count) 个\n\(detail)"
        }
    }
}

// MARK: - 资产配置卡片（紧凑堆叠条，无大饼图）

private enum AssetAllocationPalette {
    static func color(for assetClass: AssetClass) -> Color {
        switch assetClass {
        case .bankDeposit: return Color(red: 0.36, green: 0.56, blue: 0.82)
        case .bond: return Color(red: 0.58, green: 0.48, blue: 0.72)
        case .fund: return Color(red: 0.30, green: 0.62, blue: 0.58)
        case .equity: return Color(red: 0.86, green: 0.48, blue: 0.42)
        case .fxSavings: return Color(red: 0.92, green: 0.62, blue: 0.32)
        case .cashOther: return Color(red: 0.55, green: 0.60, blue: 0.66)
        case .lifestyle, .liability: return Color.secondary
        }
    }
}

private struct AssetAllocationCard: View {
    @Environment(\.wkTheme) private var theme
    let totalCNY: Decimal
    let rows: [AssetAllocationSlice]

    private var activeRows: [AssetAllocationSlice] {
        rows.filter { $0.weight > 0 && $0.valueCNY > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("总资产")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(MoneyFormat.compact(totalCNY))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(theme.primaryText)
            }

            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: 1.5) {
                    if activeRows.isEmpty {
                        Capsule()
                            .fill(theme.secondaryCardBackground)
                    } else {
                        ForEach(activeRows) { slice in
                            let w = max(3, width * CGFloat(DecimalMath.double(slice.weight)))
                            Capsule()
                                .fill(AssetAllocationPalette.color(for: slice.assetClass))
                                .frame(width: w)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityLabel("资产配置比例条")
        }
        .padding(.vertical, 2)
    }
}
