import SwiftUI
import SwiftData

/// 银行存款：先按银行，再进入该行下的活期 / 定期 / 理财。
struct BankDepositsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Environment(\.wealthSummary) private var wealthSummary
    @Query(sort: \BankDepositAccount.updatedAt, order: .reverse) private var deposits: [BankDepositAccount]
    @Query private var settingsList: [AppSettings]

    @State private var showAddBankSheet = false
    @State private var navigateToBank: String?
    @State private var registeredBanks: [String] = BankNameStore.all()
    @State private var pendingDeleteBank: String?
    @State private var confirmDeleteBank = false

    private var settings: AppSettings {
        settingsList.first ?? AppSettings()
    }

    private var bankNames: [String] {
        let fromDeposits = Set(deposits.map(\.name))
        let merged = fromDeposits.union(registeredBanks)
        return merged.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            if !bankNames.isEmpty {
                Section("银行") {
                    ForEach(bankNames, id: \.self) { bank in
                        NavigationLink {
                            BankDepositBankAccountsView(bankName: bank)
                        } label: {
                            bankSummaryCard(bankName: bank)
                        }
                        .wkCategoryCardRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteBank = bank
                                confirmDeleteBank = true
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle("银行存款")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddBankSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "building.columns.fill")
                        Image(systemName: "plus")
                    }
                }
                .accessibilityLabel("添加银行")
            }
        }
        .navigationDestination(item: $navigateToBank) { bank in
            BankDepositBankAccountsView(bankName: bank)
        }
        .sheet(isPresented: $showAddBankSheet) {
            BankDepositAddBankNameSheet { name, abbreviation in
                BankNameStore.add(name, abbreviation: abbreviation)
                registeredBanks = BankNameStore.all()
                showAddBankSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigateToBank = name
                }
            }
        }
        .alert("删除该银行？", isPresented: $confirmDeleteBank) {
            Button("删除", role: .destructive) {
                if let bank = pendingDeleteBank {
                    deleteBank(bank)
                }
                pendingDeleteBank = nil
            }
            Button("取消", role: .cancel) { pendingDeleteBank = nil }
        } message: {
            Text("将删除该银行下的全部存款、理财及相关流水，此操作不可撤销。")
        }
        .onAppear {
            registeredBanks = BankNameStore.all()
        }
    }

    private func deleteBank(_ bankName: String) {
        let items = deposits.filter { $0.name == bankName }
        let events = (try? context.fetch(FetchDescriptor<ManualCapitalEvent>())) ?? []
        for item in items {
            let assetID = item.id.uuidString
            events.filter { $0.assetID == assetID }.forEach(context.delete)
            context.delete(item)
        }
        BankNameStore.remove(bankName)
        registeredBanks = BankNameStore.all()
        try? context.save()
    }

    private func bankSummaryCard(bankName: String) -> some View {
        let items = deposits.filter { $0.name == bankName }
        // 与银行详情页类目一致：活期全部；定期/理财仅展示有余额的条目
        let demand = items.filter { $0.depositKind == .demand }
        let fixed = items.filter { $0.depositKind == .fixed && $0.balance > 0 }
        let wealth = items.filter { $0.depositKind == .wealth && $0.balance > 0 }
        let demandCNY = demand.reduce(Decimal(0)) {
            $0 + $1.marketValueNative * settings.rateToCNY(for: $1.currency)
        }
        let fixedCNY = fixed.reduce(Decimal(0)) {
            $0 + $1.marketValueNative * settings.rateToCNY(for: $1.currency)
        }
        let wealthCNY = wealth.reduce(Decimal(0)) {
            $0 + $1.marketValueNative * settings.rateToCNY(for: $1.currency)
        }
        let valueCNY = demandCNY + fixedCNY + wealthCNY
        let weight = wealthSummary?.allocationWeight(forValueCNY: valueCNY) ?? 0
        return BankSummaryCard(
            bankName: bankName,
            isEmpty: items.isEmpty,
            weight: weight,
            demandCount: demand.count,
            fixedCount: fixed.count,
            wealthCount: wealth.count,
            demandAmount: demand.isEmpty ? "—" : "¥\(MoneyFormat.compact(demandCNY))",
            fixedAmount: fixed.isEmpty ? "—" : "¥\(MoneyFormat.compact(fixedCNY))",
            wealthAmount: wealth.isEmpty ? "—" : "¥\(MoneyFormat.compact(wealthCNY))"
        )
    }
}

/// 银行品牌标识：英文字母简称 + 品牌色。
private enum BankBrandMark {
    struct Style {
        let shortLabel: String
        let color: Color
    }

    static func style(for bankName: String) -> Style {
        let name = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = BankAbbreviationCatalog.displayCode(for: name)
        return Style(shortLabel: code, color: brandColor(for: name, code: code))
    }

    private static func brandColor(for name: String, code: String) -> Color {
        let colorRules: [(keywords: [String], hex: UInt32)] = [
            (["汇丰", "HSBC"], 0xDB0011),
            (["渣打"], 0x0072AA),
            (["花旗"], 0x003B70),
            (["恒生"], 0xD7000F),
            (["东亚"], 0xE60012),
            (["星展"], 0xFF3300),
            (["众安", "ZA"], 0x00A0E9),
            (["微众"], 0x07C160),
            (["网商"], 0x1677FF),
            (["招商", "CMB"], 0xE31C23),
            (["工商", "ICBC"], 0xC41230),
            (["建设", "CCB"], 0x003B70),
            (["农业", "ABC"], 0x008C45),
            (["中国银行", "BOC", "中行"], 0xA71E32),
            (["交通", "BOCOM"], 0x003B70),
            (["邮储", "PSBC"], 0x007A3D),
            (["浦发", "SPDB"], 0x004B87),
            (["兴业", "CIB"], 0x004B87),
            (["民生", "CMBC"], 0x005BAC),
            (["光大", "CEB"], 0x6B2D5B),
            (["平安", "PAB"], 0xEA5504),
            (["广发", "CGB"], 0xC41230),
            (["中信", "CITIC"], 0xD7000F),
            (["华夏", "HXB"], 0xE60012),
            (["北京银行", "BOB"], 0xC8102E),
            (["上海银行", "BOS"], 0x003B70),
            (["宁波", "NBCB"], 0xE60012),
            (["江苏银行", "JSB"], 0x004B87),
            (["南京", "NJCB"], 0xE31C23),
        ]
        let hay = name + " " + code
        for rule in colorRules {
            if rule.keywords.contains(where: { hay.localizedCaseInsensitiveContains($0) }) {
                return Color(hex: rule.hex)
            }
        }
        let palette: [UInt32] = [0x3487D8, 0x2F9B6A, 0xC47A2C, 0x6B7FD7, 0xC35D4D, 0x405D78]
        let idx = abs(name.hashValue) % palette.count
        return Color(hex: palette[idx])
    }
}

/// 银行存款列表专用卡片：品牌标 + 活期/定期/理财色块
private struct BankSummaryCard: View {
    @Environment(\.wkTheme) private var theme

    let bankName: String
    let isEmpty: Bool
    let weight: Decimal
    let demandCount: Int
    let fixedCount: Int
    let wealthCount: Int
    let demandAmount: String
    let fixedAmount: String
    let wealthAmount: String

    private var brand: BankBrandMark.Style { BankBrandMark.style(for: bankName) }

    private var weightPercent: Double {
        DecimalMath.double(max(0, min(weight, 1))) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(brand.color.opacity(theme.isNight ? 0.28 : 0.14))
                    Text(brand.shortLabel)
                        .font(.system(size: brand.shortLabel.count > 4 ? 9 : (brand.shortLabel.count > 3 ? 11 : 13), weight: .bold, design: .rounded))
                        .foregroundStyle(theme.isNight ? brand.color.opacity(0.95) : brand.color)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bankName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isEmpty {
                    Text("待添加")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(theme.secondaryCardBackground)
                                Capsule()
                                    .fill(theme.warning.opacity(theme.isNight ? 0.7 : 0.85))
                                    .frame(width: max(4, geo.size.width * CGFloat(weightPercent / 100)))
                            }
                        }
                        .frame(width: 40, height: 4)
                        Text(String(format: "%.1f%%", weightPercent))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: 0) {
                amountColumn(title: "活期·\(demandCount)", amount: demandAmount)
                amountColumn(title: "定期·\(fixedCount)", amount: fixedAmount)
                amountColumn(title: "理财·\(wealthCount)", amount: wealthAmount)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bankAmountBlockTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        theme.isNight
                            ? theme.separator.opacity(0.55)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
    }

    /// 同一银行三块金额同色；不同银行从克制色板轮换，适配日/夜模式。
    private var bankAmountBlockTint: Color {
        let sunnyPalette: [UInt32] = [
            0xEAF2F8, // 雾蓝
            0xEEF5F0, // 薄荷
            0xF5F0EA, // 暖米
            0xF0EEF6, // 浅紫灰
            0xF3F1EC, // 沙灰
            0xECF4F3, // 青灰
        ]
        let nightBases: [UInt32] = [
            0x5B8BB5,
            0x5F9A7C,
            0xA89068,
            0x7A7EB0,
            0x8A8A82,
            0x5E9A96,
        ]
        let idx = abs(bankName.hashValue) % sunnyPalette.count
        if theme.isNight {
            return Color(hex: nightBases[idx]).opacity(0.20)
        }
        return Color(hex: sunnyPalette[idx])
    }

    private func amountColumn(title: String, amount: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(amount)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 填写银行名称；英文简称自动识别，无法确定时可选手改。
private struct BankDepositAddBankNameSheet: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var onConfirm: (_ name: String, _ abbreviation: String?) -> Void

    @State private var name = ""
    @State private var abbreviation = ""
    @State private var abbreviationEditedByUser = false
    @State private var isApplyingSuggestion = false
    @State private var matchHint: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CJKTextField(placeholder: "银行名称，如招商银行、汇丰银行", text: $name)
                        .frame(height: 40)
                        .onChange(of: name) { _, newValue in
                            refreshAbbreviationSuggestion(for: newValue)
                        }
                } header: {
                    Text("银行")
                }

                Section {
                    TextField("如 HSBC、ZA、CMB", text: $abbreviation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: abbreviation) { _, _ in
                            if !isApplyingSuggestion {
                                abbreviationEditedByUser = true
                            }
                        }
                    if let matchHint {
                        Text(matchHint)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                } header: {
                    Text("英文简称（可选）")
                } footer: {
                    Text("输入银行名后会自动识别官方简称；若未命中可手动填写，也可留空。")
                }

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
            .navigationTitle("添加银行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { confirm() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func refreshAbbreviationSuggestion(for rawName: String) {
        guard !abbreviationEditedByUser else {
            matchHint = nil
            return
        }
        isApplyingSuggestion = true
        defer { isApplyingSuggestion = false }
        if let match = BankAbbreviationCatalog.match(for: rawName) {
            abbreviation = match.code
            matchHint = match.isOfficial ? "已识别官方简称" : "已根据名称中的字母生成候选"
        } else {
            abbreviation = ""
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            matchHint = trimmed.isEmpty ? nil : "未能自动识别，可手动填写简称"
        }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请填写银行名称"
            return
        }
        let abbr = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        onConfirm(trimmed, abbr.isEmpty ? nil : abbr)
        dismiss()
    }
}

/// 添加定期 / 理财（不含活期；由右上角加号菜单触发）
private enum BankDepositAddKind: String, CaseIterable, Identifiable {
    case fixed
    case wealth

    var id: String { rawValue }

    var kind: BankDepositKind {
        switch self {
        case .fixed: return .fixed
        case .wealth: return .wealth
        }
    }

    var title: String {
        switch self {
        case .fixed: return "定期存款"
        case .wealth: return "银行理财"
        }
    }

    var systemImage: String {
        switch self {
        case .fixed: return "calendar.badge.clock"
        case .wealth: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// 活期：存入 / 取出 / 改余额（精简表单）
private struct BankDemandCashSession: Identifiable {
    enum Mode {
        case deposit
        case withdraw
        case setBalance
    }

    let id = UUID()
    let depositID: UUID
    let mode: Mode
}

/// 某一银行下的活期 / 定期 / 理财列表
struct BankDepositBankAccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    let bankName: String

    @Query(sort: \BankDepositAccount.updatedAt, order: .reverse) private var deposits: [BankDepositAccount]
    @Query private var settingsList: [AppSettings]

    @State private var editor: ManualEditorSession?
    @State private var demandCashSession: BankDemandCashSession?
    @State private var wealthFlowSession: BankWealthFlowSession?
    @State private var pendingDeleteID: UUID?
    @State private var confirmDeleteAccount = false
    @State private var maturityPromptID: UUID?
    @State private var confirmMaturityTransfer = false
    @State private var earlyWithdrawID: UUID?
    @State private var confirmEarlyWithdraw = false
    @State private var wealthSettlementSession: BankWealthSettlementSession?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var bankDeposits: [BankDepositAccount] {
        deposits.filter { $0.name == bankName }
    }

    private var demandDeposits: [BankDepositAccount] {
        bankDeposits.filter { $0.depositKind == .demand }
    }

    /// 有余额的定期，按起息日（缺省创建时间）从新到旧
    private var fixedDeposits: [BankDepositAccount] {
        bankDeposits
            .filter { $0.depositKind == .fixed && $0.balance > 0 }
            .sorted {
                let lhs = $0.valueDate ?? $0.createdAt
                let rhs = $1.valueDate ?? $1.createdAt
                return lhs > rhs
            }
    }

    private var wealthProducts: [BankDepositAccount] {
        bankDeposits
            .filter { $0.depositKind == .wealth && $0.balance > 0 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var maturityPromptItem: BankDepositAccount? {
        guard let maturityPromptID else { return nil }
        return deposits.first { $0.id == maturityPromptID }
    }

    private var earlyWithdrawItem: BankDepositAccount? {
        guard let earlyWithdrawID else { return nil }
        return deposits.first { $0.id == earlyWithdrawID }
    }

    var body: some View {
        List {
            demandBalanceSection
            if !fixedDeposits.isEmpty {
                fixedDepositSection
            }
            if !wealthProducts.isEmpty {
                wealthSection
            }
        }
        .listStyle(.plain)
        .wkPageChrome()
        .navigationTitle(bankName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(BankDepositAddKind.allCases) { item in
                        Button {
                            editor = .create(.bankDeposit, depositKind: item.kind, presetName: bankName)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加存款信息")
            }
        }
        .sheet(item: $editor, onDismiss: {
            syncFixedAccruedInterest()
            presentMaturityPromptIfNeeded()
        }) { session in
            ManualAssetEditorView(session: session)
        }
        .sheet(item: $demandCashSession) { session in
            BankDemandCashSheet(session: session)
        }
        .sheet(item: $wealthFlowSession) { session in
            BankWealthFlowSheet(session: session)
        }
        .alert("删除该银行存款？", isPresented: $confirmDeleteAccount) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID,
                   let item = deposits.first(where: { $0.id == id }) {
                    delete(item)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("将删除该存款及其相关流水，此操作不可撤销。")
        }
        .alert("定期已到期", isPresented: $confirmMaturityTransfer) {
            Button("转入活期") {
                if let item = maturityPromptItem {
                    _ = BankDepositTransferService.transferFixedToDemandFull(
                        item,
                        note: "到期转入活期",
                        context: context
                    )
                    BankDepositMaturityPromptStore.markPrompted(item.id)
                }
                maturityPromptID = nil
            }
            Button("暂不转入", role: .cancel) {
                if let id = maturityPromptID {
                    BankDepositMaturityPromptStore.markPrompted(id)
                }
                maturityPromptID = nil
            }
        } message: {
            if let item = maturityPromptItem {
                Text("「\(item.name)」定期已到期，本息约 \(MoneyFormat.compact(item.balance + item.displayAccruedInterest)) \(item.currency)。是否记入同名活期？")
            } else {
                Text("是否将到期定期转入活期？")
            }
        }
        .alert("提前支取", isPresented: $confirmEarlyWithdraw) {
            Button("支取并转入活期", role: .destructive) {
                if let item = earlyWithdrawItem {
                    _ = BankDepositTransferService.transferFixedToDemandFull(
                        item,
                        note: "提前支取转入活期",
                        context: context
                    )
                }
                earlyWithdrawID = nil
            }
            Button("仅记账取出") {
                if let item = earlyWithdrawItem {
                    demandCashSession = BankDemandCashSession(depositID: item.id, mode: .withdraw)
                }
                earlyWithdrawID = nil
            }
            Button("取消", role: .cancel) {
                earlyWithdrawID = nil
            }
        } message: {
            Text("可将本息记入同名活期；或仅登记取出流水（活期需自行另记）。实际银行提前支取可能损失利息，本 App 仅记账。")
        }
        .sheet(item: $wealthSettlementSession) { session in
            BankWealthSettlementConfirmSheet(depositID: session.depositID)
        }
        .onAppear {
            syncFixedAccruedInterest()
            presentMaturityPromptIfNeeded()
            presentWealthSettlementPromptIfNeeded()
        }
    }

    // MARK: - 活期余额

    private var demandBalanceSection: some View {
        Section {
            if demandDeposits.isEmpty {
                demandCard(
                    balance: 0,
                    currency: "CNY",
                    depositID: nil
                )
            } else {
                ForEach(demandDeposits, id: \.id) { item in
                    demandCard(
                        balance: item.balance,
                        currency: item.currency,
                        depositID: item.id
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeDeleteButton(for: item)
                        swipeEditButton(for: item)
                    }
                }
            }
        } header: {
            Text("活期余额")
        }
    }

    private func demandCard(balance: Decimal, currency: String, depositID: UUID?) -> some View {
        BankDemandBalanceCard(
            balance: balance,
            currency: currency,
            rateToCNY: settings.rateToCNY(for: currency),
            onDeposit: {
                openDemandCash(mode: .deposit, existingID: depositID, currency: currency)
            },
            onWithdraw: {
                openDemandCash(mode: .withdraw, existingID: depositID, currency: currency)
            },
            onEditBalance: {
                openDemandCash(mode: .setBalance, existingID: depositID, currency: currency)
            }
        )
        .wkCategoryCardRow()
    }

    private func openDemandCash(mode: BankDemandCashSession.Mode, existingID: UUID?, currency: String) {
        let account: BankDepositAccount
        if let existingID,
           let found = deposits.first(where: { $0.id == existingID }) {
            account = found
        } else {
            account = BankDepositTransferService.ensureDemandAccount(
                bankName: bankName,
                currency: currency,
                context: context
            )
        }
        demandCashSession = BankDemandCashSession(depositID: account.id, mode: mode)
    }

    // MARK: - 定期存款

    private var fixedDepositSection: some View {
        Section {
            BankFixedTotalCard(
                items: fixedDeposits,
                rateToCNY: { settings.rateToCNY(for: $0) }
            )
            .wkCategoryCardRow()

            ForEach(fixedDeposits, id: \.id) { item in
                BankFixedDepositCard(
                    item: item,
                    onEarlyWithdraw: {
                        earlyWithdrawID = item.id
                        confirmEarlyWithdraw = true
                    }
                )
                .wkCategoryCardRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeDeleteButton(for: item)
                    swipeEditButton(for: item)
                }
            }
        } header: {
            Text("定期存款")
        }
    }

    // MARK: - 银行理财

    private var wealthSection: some View {
        Section {
            ForEach(wealthProducts, id: \.id) { item in
                BankWealthProductCard(
                    item: item,
                    rateToCNY: settings.rateToCNY(for: item.currency),
                    onBuy: {
                        wealthFlowSession = BankWealthFlowSession(depositID: item.id, mode: .buy)
                    },
                    onRedeem: {
                        wealthFlowSession = BankWealthFlowSession(depositID: item.id, mode: .redeem)
                    }
                )
                .wkCategoryCardRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeDeleteButton(for: item)
                    swipeEditButton(for: item)
                }
            }
        } header: {
            Text("银行理财")
        }
    }

    @ViewBuilder
    private func swipeDeleteButton(for item: BankDepositAccount) -> some View {
        Button(role: .destructive) {
            pendingDeleteID = item.id
            confirmDeleteAccount = true
        } label: {
            Label("删除", systemImage: "trash.fill")
        }
        .tint(.red)
    }

    @ViewBuilder
    private func swipeEditButton(for item: BankDepositAccount) -> some View {
        Button {
            if item.depositKind == .demand {
                demandCashSession = BankDemandCashSession(depositID: item.id, mode: .setBalance)
            } else {
                editor = .editDeposit(item.id)
            }
        } label: {
            Label("修改", systemImage: "pencil")
        }
        .tint(theme.accent)
    }

    private func delete(_ item: BankDepositAccount) {
        let assetID = item.id.uuidString
        let events = (try? context.fetch(FetchDescriptor<ManualCapitalEvent>())) ?? []
        events.filter { $0.assetID == assetID }.forEach(context.delete)
        context.delete(item)
        try? context.save()
    }

    private func syncFixedAccruedInterest() {
        var changed = false
        for item in bankDeposits where item.depositKind == .fixed {
            guard let estimated = item.estimatedMaturityInterest() else { continue }
            guard item.accruedInterest != estimated else { continue }
            item.accruedInterest = estimated
            item.updatedAt = .now
            changed = true
        }
        if changed { try? context.save() }
    }

    private func presentMaturityPromptIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now)
        let due = fixedDeposits.first { item in
            guard let maturity = item.maturityDate else { return false }
            guard Calendar.current.startOfDay(for: maturity) <= today else { return false }
            return !BankDepositMaturityPromptStore.hasPrompted(item.id)
        }
        guard let due else { return }
        maturityPromptID = due.id
        confirmMaturityTransfer = true
    }

    private func presentWealthSettlementPromptIfNeeded() {
        guard wealthSettlementSession == nil, !confirmMaturityTransfer else { return }
        let due = wealthProducts.first { item in
            item.isExpectedRedemptionDue() && !BankWealthRedemptionPromptStore.hasPrompted(item.id)
        }
        guard let due else { return }
        wealthSettlementSession = BankWealthSettlementSession(depositID: due.id)
    }
}

// MARK: - 活期存入 / 取出 / 改余额

private struct BankDemandCashSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme

    let session: BankDemandCashSession

    @Query private var deposits: [BankDepositAccount]

    @State private var amountText = ""
    @State private var balanceText = ""
    @State private var currency = "CNY"
    @State private var errorMessage: String?

    private var item: BankDepositAccount? {
        deposits.first { $0.id == session.depositID }
    }

    private var title: String {
        switch session.mode {
        case .deposit: return "存入"
        case .withdraw: return "取出"
        case .setBalance: return "改余额"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if session.mode == .setBalance {
                        LabeledContent("余额") {
                            DecimalTextField(placeholder: "当前余额", text: $balanceText)
                                .frame(height: 40)
                        }
                    } else {
                        LabeledContent(session.mode == .deposit ? "存入金额" : "取出金额") {
                            DecimalTextField(placeholder: "原币金额", text: $amountText)
                                .frame(height: 40)
                        }
                    }
                    Picker("币种", selection: $currency) {
                        Text("CNY").tag("CNY")
                        Text("USD").tag("USD")
                        Text("HKD").tag("HKD")
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
            .navigationTitle(title)
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
                currency = item.currency
                balanceText = DecimalMath.plainString(item.balance, fractionDigits: 2)
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let item else {
            errorMessage = "账户不存在"
            return
        }

        let target = resolveTargetAccount(from: item)

        switch session.mode {
        case .deposit, .withdraw:
            guard let amount = DecimalMath.parse(amountText), amount > 0 else {
                errorMessage = "请填写有效金额"
                return
            }
            if session.mode == .withdraw, target.balance < amount {
                errorMessage = "取出金额不能大于当前余额"
                return
            }
            if session.mode == .deposit {
                target.balance += amount
                context.insert(
                    ManualCapitalEvent(
                        assetID: target.id,
                        assetClass: .bankDeposit,
                        kind: .deposit,
                        amount: amount,
                        currency: target.currency,
                        note: "存入"
                    )
                )
            } else {
                target.balance -= amount
                context.insert(
                    ManualCapitalEvent(
                        assetID: target.id,
                        assetClass: .bankDeposit,
                        kind: .withdraw,
                        amount: amount,
                        currency: target.currency,
                        note: "取出"
                    )
                )
            }
            target.updatedAt = .now
        case .setBalance:
            guard let balance = DecimalMath.parse(balanceText), balance >= 0 else {
                errorMessage = "请填写有效余额"
                return
            }
            let oldBalance = target.balance
            let delta = balance - oldBalance
            target.balance = balance
            target.updatedAt = .now
            if delta != 0 {
                let kind: ManualCapitalEventKind = delta > 0 ? .adjustPrincipal : .withdraw
                context.insert(
                    ManualCapitalEvent(
                        assetID: target.id,
                        assetClass: .bankDeposit,
                        kind: kind,
                        amount: abs(delta),
                        currency: target.currency,
                        note: "改余额"
                    )
                )
            }
        }

        BankNameStore.add(item.name)
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = "保存失败，请重试"
        }
    }

    /// 币种与当前账户不同时，创建或定位该银行下对应币种的活期。
    private func resolveTargetAccount(from item: BankDepositAccount) -> BankDepositAccount {
        let code = currency.uppercased()
        if item.currency.uppercased() == code {
            return item
        }
        return BankDepositTransferService.ensureDemandAccount(
            bankName: item.name,
            currency: code,
            context: context
        )
    }
}

// MARK: - 银行理财买入 / 赎回

private struct BankWealthFlowSession: Identifiable {
    enum Mode {
        case buy
        case redeem
    }

    let id = UUID()
    let depositID: UUID
    let mode: Mode
}

private struct BankWealthFlowSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme

    let session: BankWealthFlowSession

    @Query private var deposits: [BankDepositAccount]

    @State private var amountText = ""
    @State private var eventDate = Date()
    @State private var note = ""
    @State private var transferToDemand = true
    @State private var errorMessage: String?

    private var item: BankDepositAccount? {
        deposits.first { $0.id == session.depositID }
    }

    private var title: String {
        session.mode == .buy ? "买入" : "赎回"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(session.mode == .buy ? "申购金额" : "赎回金额") {
                        DecimalTextField(placeholder: "原币金额", text: $amountText)
                            .frame(height: 40)
                    }
                    DatePicker(
                        session.mode == .buy ? "申购日期" : "赎回日期",
                        selection: $eventDate,
                        displayedComponents: .date
                    )
                    CJKTextField(placeholder: "备注（可选）", text: $note)
                        .frame(height: 40)

                    if session.mode == .redeem {
                        Toggle("转入该行活期余额", isOn: $transferToDemand)
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
            .navigationTitle(title)
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
        }
        .presentationDetents([.height(session.mode == .redeem ? 340 : 300)])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let item else {
            errorMessage = "理财不存在"
            return
        }
        guard let amount = DecimalMath.parse(amountText), amount > 0 else {
            errorMessage = "请填写有效金额"
            return
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        switch session.mode {
        case .buy:
            item.balance += amount
            item.updatedAt = .now
            context.insert(
                ManualCapitalEvent(
                    assetID: item.id,
                    assetClass: .bankDeposit,
                    kind: .deposit,
                    amount: amount,
                    currency: item.currency,
                    eventDate: eventDate,
                    note: trimmedNote.isEmpty ? "申购" : trimmedNote
                )
            )
        case .redeem:
            guard amount <= item.balance else {
                errorMessage = "赎回金额不能大于持仓成本"
                return
            }
            item.balance -= amount
            item.updatedAt = .now
            if item.balance == 0 {
                item.expectedRedemptionDate = nil
            }
            context.insert(
                ManualCapitalEvent(
                    assetID: item.id,
                    assetClass: .bankDeposit,
                    kind: .withdraw,
                    amount: amount,
                    currency: item.currency,
                    eventDate: eventDate,
                    note: trimmedNote.isEmpty ? "赎回" : trimmedNote
                )
            )
            if transferToDemand {
                let demand = BankDepositTransferService.ensureDemandAccount(
                    bankName: item.name,
                    currency: item.currency,
                    context: context
                )
                demand.balance += amount
                demand.updatedAt = .now
                context.insert(
                    ManualCapitalEvent(
                        assetID: demand.id,
                        assetClass: .bankDeposit,
                        kind: .deposit,
                        amount: amount,
                        currency: item.currency,
                        eventDate: eventDate,
                        note: trimmedNote.isEmpty
                            ? "理财赎回转入活期"
                            : "理财赎回转入活期·\(trimmedNote)"
                    )
                )
            }
        }

        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = "保存失败，请重试"
        }
    }
}

private struct BankWealthProductCard: View {
    @Environment(\.wkTheme) private var theme

    let item: BankDepositAccount
    let rateToCNY: Decimal
    let onBuy: () -> Void
    let onRedeem: () -> Void

    private var holdingAmount: Decimal { item.marketValueNative }
    private var cost: Decimal { item.balance }
    private var marketValue: Decimal { item.marketValueNative }
    private var cumulativePnL: Decimal {
        (item.marketValueNative - item.balance) + item.receivedInterest
    }
    private var returnRate: Decimal {
        guard cost > 0 else { return 0 }
        return cumulativePnL / cost
    }

    private var marketValueDisplay: String {
        if item.currency.uppercased() == "CNY" {
            return MoneyFormat.compact(marketValue)
        }
        return "¥\(MoneyFormat.compact(marketValue * rateToCNY))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)

            VStack(spacing: 8) {
                wealthLine("持有金额", "\(MoneyFormat.compact(holdingAmount)) \(item.currency)")
                wealthLine("持仓成本", "\(MoneyFormat.compact(cost)) \(item.currency)")
                wealthLine("当前市值", marketValueDisplay)
                wealthLine(
                    "预计收益",
                    "\(MoneyFormat.compact(item.displayAccruedInterest)) \(item.currency)"
                )
                wealthLine(
                    "累计收益",
                    "\(MoneyFormat.compact(cumulativePnL, sign: true)) \(item.currency)",
                    valueColor: theme.marketPnL(cumulativePnL)
                )
                wealthLine("收益率", MoneyFormat.percent(returnRate), valueColor: theme.marketPnL(cumulativePnL))
                wealthLine("赎回到账日", item.expectedRedemptionDateText)
            }

            HoldingQuickActionBar(items: [
                .init(id: "buy", title: "买入", systemImage: "plus.circle.fill", tint: theme.gain, action: onBuy),
                .init(id: "redeem", title: "赎回", systemImage: "minus.circle.fill", tint: theme.loss, action: onRedeem),
            ])
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
    }

    private func wealthLine(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(valueColor ?? theme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 活期余额卡片

private struct BankDemandBalanceCard: View {
    @Environment(\.wkTheme) private var theme

    let balance: Decimal
    let currency: String
    let rateToCNY: Decimal
    let onDeposit: () -> Void
    let onWithdraw: () -> Void
    let onEditBalance: () -> Void

    private var isForeign: Bool {
        currency.uppercased() != "CNY"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("当前余额")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                Text(currency)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            }

            Text(MoneyFormat.compact(balance))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isForeign {
                VStack(spacing: 6) {
                    HStack {
                        Text("市值")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                        Spacer(minLength: 8)
                        Text("¥\(MoneyFormat.compact(balance * rateToCNY))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                    }
                    HStack {
                        Text("当前汇率")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                        Spacer(minLength: 8)
                        Text(MoneyFormat.fxLine(code: currency, rateToCNY: rateToCNY))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }

            HoldingQuickActionBar(items: [
                .init(id: "in", title: "存入", systemImage: "plus.circle.fill", tint: theme.gain, action: onDeposit),
                .init(id: "out", title: "取出", systemImage: "minus.circle.fill", tint: theme.loss, action: onWithdraw),
                .init(id: "edit", title: "改余额", systemImage: "pencil.circle.fill", tint: theme.accent, action: onEditBalance),
            ])
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
    }
}

// MARK: - 定期合计 / 单笔卡片

private struct BankFixedTotalCard: View {
    @Environment(\.wkTheme) private var theme

    let items: [BankDepositAccount]
    let rateToCNY: (String) -> Decimal

    private var currencies: [String] {
        Array(Set(items.map(\.currency))).sorted()
    }

    private var totalsByCurrency: [(currency: String, principal: Decimal, marketNative: Decimal)] {
        currencies.map { code in
            let group = items.filter { $0.currency == code }
            let principal = group.reduce(Decimal(0)) { $0 + $1.balance }
            let market = group.reduce(Decimal(0)) { $0 + $1.marketValueNative }
            return (code, principal, market)
        }
    }

    private var totalCNY: Decimal {
        totalsByCurrency.reduce(Decimal(0)) { $0 + $1.marketNative * rateToCNY($1.currency) }
    }

    private var hasForeign: Bool {
        currencies.contains { $0.uppercased() != "CNY" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("总金额")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)

            if totalsByCurrency.count == 1, let only = totalsByCurrency.first {
                Text("\(MoneyFormat.compact(only.principal)) \(only.currency)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)

                if hasForeign {
                    fixedMetricRow(label: "市值", value: "¥\(MoneyFormat.compact(totalCNY))")
                    fixedMetricRow(
                        label: "当前汇率",
                        value: MoneyFormat.fxLine(code: only.currency, rateToCNY: rateToCNY(only.currency))
                    )
                }
            } else {
                Text("¥\(MoneyFormat.compact(totalCNY))")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)

                ForEach(totalsByCurrency, id: \.currency) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        fixedMetricRow(
                            label: row.currency,
                            value: MoneyFormat.compact(row.principal)
                        )
                        if row.currency.uppercased() != "CNY" {
                            fixedMetricRow(
                                label: "市值",
                                value: "¥\(MoneyFormat.compact(row.marketNative * rateToCNY(row.currency)))"
                            )
                            fixedMetricRow(
                                label: "当前汇率",
                                value: MoneyFormat.fxLine(code: row.currency, rateToCNY: rateToCNY(row.currency))
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
    }

    private func fixedMetricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.primaryText)
        }
    }
}

private struct BankFixedDepositCard: View {
    @Environment(\.wkTheme) private var theme

    let item: BankDepositAccount
    let onEarlyWithdraw: () -> Void

    private var accruedToDateText: String {
        if let v = item.accruedInterestToDate() {
            return MoneyFormat.compact(v)
        }
        return "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("本金")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                Text("\(MoneyFormat.compact(item.balance)) \(item.currency)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
            }

            VStack(spacing: 8) {
                fixedLine("年利率", MoneyFormat.percent(item.annualRate))
                fixedLine("起息日", MoneyFormat.shortDate(item.valueDate))
                fixedLine("到期日", MoneyFormat.shortDate(item.maturityDate))
                fixedLine("预计利息", MoneyFormat.compact(item.displayAccruedInterest))
                fixedLine("当前应计利息", accruedToDateText)
                fixedLine("定期存期", item.depositTermDescription())
                fixedLine("剩余期限", item.remainingTermDescription())
            }

            Button(action: onEarlyWithdraw) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("提前支取")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(theme.loss)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.loss.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.cardBackground)
        )
    }

    private func fixedLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct BankDepositDetailView: View {
    @Environment(\.wkTheme) private var theme
    @Environment(\.modelContext) private var context
    let depositID: UUID

    @Query private var deposits: [BankDepositAccount]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ManualCapitalEvent.eventDate, order: .reverse) private var events: [ManualCapitalEvent]
    @State private var editor: ManualEditorSession?
    @State private var initialFlow: ManualFlowKind = .none
    @State private var eventFilter: ManualEventFilter = .all
    @State private var editEventID: UUID?
    @State private var pendingDeleteEventID: UUID?
    @State private var confirmDeleteEvent = false
    @State private var confirmMaturityTransfer = false
    @State private var confirmEarlyWithdrawTransfer = false
    @State private var peerTransferSession: BankDepositPeerTransferSession?
    @State private var wealthSettlementSession: BankWealthSettlementSession?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var item: BankDepositAccount? {
        deposits.first { $0.id == depositID }
    }

    private var relatedEvents: [ManualCapitalEvent] {
        let id = depositID.uuidString
        let all = events.filter { $0.assetID == id && $0.assetClass == .bankDeposit }
        return all.filter { eventFilter.matches($0.kind) }
    }

    private var isMaturedFixed: Bool {
        guard let item, item.depositKind == .fixed, item.balance > 0,
              let maturity = item.maturityDate else { return false }
        return Calendar.current.startOfDay(for: maturity) <= Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        Group {
            if let item {
                let rate = settings.rateToCNY(for: item.currency)
                List {
                    Section {
                        HStack(spacing: 10) {
                            Text(depositFlag(for: item.currency))
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayTitle)
                                    .font(.title3.weight(.semibold))
                                Text("\(item.name) · \(item.depositKind.displayName) · \(item.currency)")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                                if item.depositKind == .wealth {
                                    Text("\(item.wealthStyle.displayName) · \(item.riskLevel.displayName)")
                                        .font(.caption2)
                                        .foregroundStyle(theme.secondaryText)
                                    Text("预计到账日 \(item.expectedRedemptionDateText)")
                                        .font(.caption2)
                                        .foregroundStyle(
                                            item.isExpectedRedemptionDue() ? theme.warning : theme.secondaryText
                                        )
                                }
                                if isMaturedFixed {
                                    Text("已到期，可转入活期")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(theme.warning)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(item.depositKind.shortName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(theme.accent.opacity(0.12))
                                )
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(theme.cardBackground)
                    }

                    Section {
                        HoldingOverviewGridCard(
                            title: "\(item.depositKind.shortName)概览",
                            titleTrailing: item.currency == "CNY" ? "¥" : item.currency,
                            metrics: depositOverviewMetrics(item, rateToCNY: rate)
                        )
                        .wkOverviewListRow()
                        .id(depositOverviewID(item))
                    }

                    Section {
                        if item.depositKind == .fixed {
                            HoldingQuickActionBar(items: [
                                .init(id: "toDemand", title: "转入活期", systemImage: "arrow.right.circle.fill", tint: theme.gain) {
                                    peerTransferSession = BankDepositPeerTransferSession(
                                        sourceID: item.id,
                                        direction: .fixedToDemand
                                    )
                                },
                                .init(id: "early", title: "提前支取", systemImage: "arrow.uturn.backward.circle.fill", tint: theme.loss) {
                                    confirmEarlyWithdrawTransfer = true
                                },
                            ])
                            .wkOverviewListRow()
                        } else if item.depositKind == .wealth {
                            HoldingQuickActionBar(items: [
                                .init(id: "in", title: "申购", systemImage: "plus.circle.fill", tint: theme.gain) {
                                    initialFlow = .inbound
                                    editor = .editDeposit(item.id)
                                },
                                .init(id: "out", title: "赎回", systemImage: "minus.circle.fill", tint: theme.loss) {
                                    initialFlow = .outbound
                                    editor = .editDeposit(item.id)
                                },
                            ])
                            .wkOverviewListRow()
                            HoldingQuickActionBar(items: [
                                .init(id: "settle", title: "确认到账", systemImage: "checkmark.circle.fill", tint: theme.warning) {
                                    wealthSettlementSession = BankWealthSettlementSession(depositID: item.id)
                                },
                            ])
                            .wkOverviewListRow()
                        } else {
                            HoldingQuickActionBar(items: [
                                .init(id: "in", title: "存入", systemImage: "plus.circle.fill", tint: theme.gain) {
                                    initialFlow = .inbound
                                    editor = .editDeposit(item.id)
                                },
                                .init(id: "out", title: "取出", systemImage: "minus.circle.fill", tint: theme.loss) {
                                    initialFlow = .outbound
                                    editor = .editDeposit(item.id)
                                },
                            ])
                            .wkOverviewListRow()
                            HoldingQuickActionBar(items: [
                                .init(id: "toFixed", title: "转入定期", systemImage: "arrow.right.circle.fill", tint: theme.accent) {
                                    peerTransferSession = BankDepositPeerTransferSession(
                                        sourceID: item.id,
                                        direction: .demandToFixed
                                    )
                                },
                            ])
                            .wkOverviewListRow()
                        }
                    }

                    if isMaturedFixed {
                        Section {
                            Button {
                                confirmMaturityTransfer = true
                            } label: {
                                Label("到期本息转入活期", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(theme.accent)
                        } footer: {
                            Text("到期可将本金与预计利息一并记入同名活期。")
                        }
                    }

                    if item.depositKind == .wealth, item.isExpectedRedemptionDue() {
                        Section {
                            Button {
                                wealthSettlementSession = BankWealthSettlementSession(depositID: item.id)
                            } label: {
                                Label("确认赎回到账", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(theme.warning)
                        } footer: {
                            Text("预计到账日为 \(item.expectedRedemptionDateText)。确认后填写实际到账日与本次兑付收益。")
                        }
                    }

                    if item.depositKind != .fixed {
                        Section {
                            Picker("筛选", selection: $eventFilter) {
                                ForEach(ManualEventFilter.allCases) { filter in
                                    Text(filter.title(
                                        inbound: item.depositKind == .wealth ? "申购" : "存入",
                                        outbound: item.depositKind == .wealth ? "赎回" : "取出"
                                    )).tag(filter)
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
                                            assetName: item.displayTitle,
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

                    if !item.note.isEmpty {
                        Section("备注") {
                            Text(item.note)
                        }
                    }
                }
                .wkPageChrome()
            } else {
                ContentUnavailableView("存款不存在", systemImage: "tray")
            }
        }
        .navigationTitle(item.map { "\($0.depositKind.shortName)详情" } ?? "存款详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editEventID) { id in
            ManualCapitalEventDetailView(eventID: id)
        }
        .sheet(item: $editor, onDismiss: {
            initialFlow = .none
            if let item { syncAccruedInterest(for: item) }
        }) { session in
            ManualAssetEditorView(session: session, initialFlow: initialFlow)
        }
        .sheet(item: $peerTransferSession) { session in
            BankDepositPeerTransferSheet(session: session)
        }
        .sheet(item: $wealthSettlementSession) { session in
            BankWealthSettlementConfirmSheet(depositID: session.depositID)
        }
        .alert("删除这笔流水？", isPresented: $confirmDeleteEvent) {
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
            Text("将撤销该流水对账户余额的影响，此操作不可撤销。")
        }
        .alert("定期已到期", isPresented: $confirmMaturityTransfer) {
            Button("转入活期") {
                if let item {
                    _ = BankDepositTransferService.transferFixedToDemandFull(
                        item,
                        note: "到期转入活期",
                        context: context
                    )
                    BankDepositMaturityPromptStore.markPrompted(item.id)
                }
            }
            Button("暂不转入", role: .cancel) {
                if let item {
                    BankDepositMaturityPromptStore.markPrompted(item.id)
                }
            }
        } message: {
            if let item {
                Text("本息约 \(MoneyFormat.compact(item.balance + item.displayAccruedInterest)) \(item.currency)。确认记入同名活期？")
            }
        }
        .alert("提前支取", isPresented: $confirmEarlyWithdrawTransfer) {
            Button("支取并转入活期", role: .destructive) {
                if let item {
                    _ = BankDepositTransferService.transferFixedToDemandFull(
                        item,
                        note: "提前支取转入活期",
                        context: context
                    )
                }
            }
            Button("仅记账取出") {
                initialFlow = .outbound
                if let item {
                    editor = .editDeposit(item.id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("可将本息记入同名活期；或仅登记取出流水（活期需自行另记）。实际银行提前支取可能损失利息，本 App 仅记账。")
        }
        .onAppear {
            if isMaturedFixed, let item, !BankDepositMaturityPromptStore.hasPrompted(item.id) {
                confirmMaturityTransfer = true
            } else if let item, item.isExpectedRedemptionDue(),
                      !BankWealthRedemptionPromptStore.hasPrompted(item.id) {
                wealthSettlementSession = BankWealthSettlementSession(depositID: item.id)
            }
        }
    }

    private func depositOverviewID(_ item: BankDepositAccount) -> String {
        "\(item.updatedAt.timeIntervalSince1970)-\(item.balance)-\(item.displayAccruedInterest)-\(item.receivedInterest)-\(item.unitNav)-\(relatedEvents.count)"
    }

    private func syncAccruedInterest(for item: BankDepositAccount) {
        guard let estimated = item.estimatedMaturityInterest() else { return }
        guard item.accruedInterest != estimated else { return }
        item.accruedInterest = estimated
        item.updatedAt = .now
        try? context.save()
    }

    private func deleteEvent(_ event: ManualCapitalEvent) {
        switch event.kind {
        case .deposit, .adjustPrincipal:
            if let item {
                item.balance = max(0, item.balance - event.amount)
                item.updatedAt = .now
            }
        case .withdraw, .maturityRedeem:
            if let item {
                item.balance += event.amount
                item.updatedAt = .now
            }
        case .interestReceived:
            if let item {
                item.receivedInterest = max(0, item.receivedInterest - event.amount)
                item.updatedAt = .now
            }
        }
        context.delete(event)
        if let item {
            syncAccruedInterest(for: item)
        }
        try? context.save()
    }

    private func depositOverviewMetrics(_ item: BankDepositAccount, rateToCNY: Decimal) -> [HoldingOverviewMetric] {
        if item.depositKind == .wealth {
            var metrics: [HoldingOverviewMetric] = [
                HoldingOverviewMetric("投入本金", MoneyFormat.compact(item.balance)),
                HoldingOverviewMetric("当前市值", MoneyFormat.compact(item.marketValueNative)),
                HoldingOverviewMetric("市值(CNY)", MoneyFormat.compact(item.marketValueNative * rateToCNY)),
                HoldingOverviewMetric("产品类型", item.wealthStyle.displayName),
                HoldingOverviewMetric("风险等级", item.riskLevel.displayName),
                HoldingOverviewMetric("预计到账日", item.expectedRedemptionDateText),
                HoldingOverviewMetric("已兑付收益", MoneyFormat.compact(item.receivedInterest)),
            ]
            switch item.wealthStyle {
            case .netValue, .cashManagement:
                metrics.append(HoldingOverviewMetric("单位净值", MoneyFormat.compact(item.unitNav, fractionDigits: 4)))
                metrics.append(HoldingOverviewMetric(
                    "浮动盈亏",
                    MoneyFormat.compact(item.marketValueNative - item.balance, sign: true)
                ))
            case .closed:
                if item.annualRate > 0 {
                    metrics.append(HoldingOverviewMetric("业绩基准", MoneyFormat.percent(item.annualRate)))
                }
                metrics.append(HoldingOverviewMetric("预计收益", MoneyFormat.compact(item.displayAccruedInterest)))
                if item.maturityDate != nil {
                    metrics.append(HoldingOverviewMetric("剩余期限", item.remainingTermDescription()))
                }
            }
            if item.currency != "CNY" {
                metrics.append(
                    HoldingOverviewMetric("汇率", MoneyFormat.fxLine(code: item.currency, rateToCNY: rateToCNY))
                )
            }
            return metrics
        }

        var metrics: [HoldingOverviewMetric] = [
            HoldingOverviewMetric("本金", MoneyFormat.compact(item.balance)),
            HoldingOverviewMetric("含预计利息", MoneyFormat.compact(item.marketValueNative)),
            HoldingOverviewMetric("市值(CNY)", MoneyFormat.compact(item.marketValueNative * rateToCNY)),
            HoldingOverviewMetric("年利率", MoneyFormat.percent(item.annualRate)),
            HoldingOverviewMetric("预计利息", MoneyFormat.compact(item.displayAccruedInterest)),
            HoldingOverviewMetric("已到账利息", MoneyFormat.compact(item.receivedInterest)),
            HoldingOverviewMetric("类型", item.depositKind.displayName),
        ]
        if item.depositKind == .fixed || item.maturityDate != nil {
            metrics.append(HoldingOverviewMetric("剩余期限", item.remainingTermDescription()))
        }
        if item.currency != "CNY" {
            metrics.append(
                HoldingOverviewMetric("汇率", MoneyFormat.fxLine(code: item.currency, rateToCNY: rateToCNY))
            )
        }
        return metrics
    }
}

private func depositFlag(for currency: String) -> String {
    switch currency.uppercased() {
    case "HKD": return "🇭🇰"
    case "USD": return "🇺🇸"
    default: return "🇨🇳"
    }
}

// MARK: - 同银行互转

struct BankDepositPeerTransferSession: Identifiable {
    enum Direction {
        case fixedToDemand
        case demandToFixed
    }

    let id = UUID()
    let sourceID: UUID
    let direction: Direction
}

struct BankDepositPeerTransferSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var deposits: [BankDepositAccount]

    let session: BankDepositPeerTransferSession

    @State private var amountText = ""
    @State private var targetFixedID: UUID?
    @State private var createNewFixed = true
    @State private var rateText = ""
    @State private var hasValueDate = true
    @State private var valueDate = Date()
    @State private var hasMaturity = true
    @State private var maturityDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var errorMessage: String?
    @State private var showError = false

    private var source: BankDepositAccount? {
        deposits.first { $0.id == session.sourceID }
    }

    private var peerFixedAccounts: [BankDepositAccount] {
        guard let source else { return [] }
        return BankDepositTransferService.peerAccounts(of: source, kind: .fixed, context: context)
    }

    private var title: String {
        switch session.direction {
        case .fixedToDemand: return "转入活期"
        case .demandToFixed: return "转入定期"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let source {
                    Section {
                        LabeledContent("银行") { Text(source.name) }
                        LabeledContent("方向") {
                            Text(
                                session.direction == .fixedToDemand
                                ? "定期 → 活期"
                                : "活期 → 定期"
                            )
                        }
                        LabeledContent("可转本金") {
                            Text("\(MoneyFormat.compact(source.balance)) \(source.currency)")
                                .monospacedDigit()
                        }
                    }

                    Section("金额") {
                        LabeledContent("互转金额") {
                            DecimalTextField(placeholder: "本金", text: $amountText)
                                .frame(height: 40)
                        }
                        Button("全部本金") {
                            amountText = DecimalMath.plainString(source.balance)
                        }
                        .font(.subheadline)
                    }

                    if session.direction == .demandToFixed {
                        Section("目标定期") {
                            if peerFixedAccounts.isEmpty {
                                Text("将新建一笔同名定期")
                                    .foregroundStyle(theme.secondaryText)
                            } else {
                                Picker("方式", selection: $createNewFixed) {
                                    Text("新建定期").tag(true)
                                    Text("转入已有定期").tag(false)
                                }
                                .pickerStyle(.segmented)
                                if !createNewFixed {
                                    Picker("定期账户", selection: $targetFixedID) {
                                        ForEach(peerFixedAccounts, id: \.id) { item in
                                            Text("余额 \(MoneyFormat.compact(item.balance)) · 利率 \(MoneyFormat.compact(item.annualRate * 100))%")
                                                .tag(Optional(item.id))
                                        }
                                    }
                                }
                            }
                            if createNewFixed || peerFixedAccounts.isEmpty {
                                LabeledContent("年利率%") {
                                    DecimalTextField(placeholder: "如 1.5", text: $rateText)
                                        .frame(height: 40)
                                }
                                Toggle("起息日", isOn: $hasValueDate)
                                if hasValueDate {
                                    DatePicker("起息日", selection: $valueDate, displayedComponents: .date)
                                }
                                Toggle("到期日", isOn: $hasMaturity)
                                if hasMaturity {
                                    DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                                }
                            }
                        }
                    }

                    Section {
                        Text("仅在本 App 账本中记账，不会向真实银行发起转账。")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                } else {
                    ContentUnavailableView("账户不存在", systemImage: "tray")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认互转") { confirmTransfer() }
                }
            }
            .onAppear {
                if let source {
                    amountText = DecimalMath.plainString(source.balance)
                    if let first = peerFixedAccounts.first {
                        targetFixedID = first.id
                        createNewFixed = false
                    }
                }
            }
            .alert("无法互转", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func confirmTransfer() {
        guard let source else {
            errorMessage = "账户不存在"
            showError = true
            return
        }
        guard let amount = DecimalMath.parse(amountText), amount > 0 else {
            errorMessage = "请填写有效金额"
            showError = true
            return
        }
        guard amount <= source.balance else {
            errorMessage = "互转金额不能大于可转本金"
            showError = true
            return
        }

        switch session.direction {
        case .fixedToDemand:
            guard BankDepositTransferService.transferFixedToDemand(
                source,
                amount: amount,
                note: "定期转入活期",
                context: context
            ) != nil else {
                errorMessage = "转入活期失败"
                showError = true
                return
            }
        case .demandToFixed:
            let target: BankDepositAccount?
            let creating = createNewFixed || peerFixedAccounts.isEmpty
            if creating {
                target = nil
            } else {
                target = peerFixedAccounts.first { $0.id == targetFixedID }
                if target == nil {
                    errorMessage = "请选择目标定期"
                    showError = true
                    return
                }
            }
            let rate = (DecimalMath.parse(rateText) ?? 0) / 100
            guard BankDepositTransferService.transferDemandToFixed(
                source,
                amount: amount,
                targetFixed: target,
                createAnnualRate: rate,
                createValueDate: hasValueDate ? valueDate : nil,
                createMaturityDate: hasMaturity ? maturityDate : nil,
                note: "活期转入定期",
                context: context
            ) != nil else {
                errorMessage = "转入定期失败"
                showError = true
                return
            }
        }
        dismiss()
    }
}

// MARK: - 银行理财赎回到账确认

struct BankWealthSettlementSession: Identifiable {
    let id: UUID
    let depositID: UUID

    init(depositID: UUID) {
        self.id = depositID
        self.depositID = depositID
    }
}

struct BankWealthSettlementConfirmSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var deposits: [BankDepositAccount]

    let depositID: UUID

    @State private var actualDate = Date()
    @State private var incomeText = ""
    @State private var redeemPrincipalText = ""
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var item: BankDepositAccount? {
        deposits.first { $0.id == depositID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        LabeledContent("产品", value: item.displayTitle)
                        LabeledContent("银行", value: item.name)
                        LabeledContent("预计到账日", value: item.expectedRedemptionDateText)
                        LabeledContent("当前本金", value: "\(MoneyFormat.compact(item.balance)) \(item.currency)")
                    }

                    Section {
                        DatePicker("实际到账日期", selection: $actualDate, displayedComponents: .date)
                        LabeledContent("本次兑付收益") {
                            DecimalTextField(placeholder: "无收益填 0", text: $incomeText)
                                .frame(height: 40)
                        }
                        LabeledContent("赎回本金") {
                            DecimalTextField(placeholder: "可不赎回填 0", text: $redeemPrincipalText)
                                .frame(height: 40)
                        }
                    } header: {
                        Text("确认到账")
                    } footer: {
                        Text("至少填写兑付收益或赎回本金之一。确认后会生成「收益到账」和/或「赎回到账」流水，并清除预计到账日。")
                    }
                } else {
                    ContentUnavailableView("理财不存在", systemImage: "tray")
                }
            }
            .navigationTitle("确认赎回到账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂未到账") {
                        BankWealthRedemptionPromptStore.markPrompted(depositID)
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
        actualDate = item.expectedRedemptionDate ?? .now
        redeemPrincipalText = DecimalMath.plainString(item.balance, fractionDigits: 2)
        if item.displayAccruedInterest > 0 {
            incomeText = DecimalMath.plainString(item.displayAccruedInterest, fractionDigits: 2)
        }
    }

    private func confirm() {
        guard let item else { return }
        let income = DecimalMath.parse(incomeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : incomeText) ?? 0
        let principal = DecimalMath.parse(
            redeemPrincipalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : redeemPrincipalText
        ) ?? 0
        guard income >= 0, principal >= 0 else {
            errorMessage = "金额不能为负"
            return
        }
        guard income > 0 || principal > 0 else {
            errorMessage = "请填写本次兑付收益或赎回本金"
            return
        }
        guard principal <= item.balance else {
            errorMessage = "赎回本金不能大于当前投入本金"
            return
        }
        guard BankWealthSettlementService.confirmArrival(
            item,
            actualDate: actualDate,
            income: income,
            redeemPrincipal: principal,
            context: context
        ) else {
            errorMessage = "保存失败，请重试"
            return
        }
        dismiss()
    }
}
