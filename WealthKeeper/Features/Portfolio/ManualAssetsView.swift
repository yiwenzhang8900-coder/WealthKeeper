import SwiftUI
import SwiftData

/// 手动资产 / 负债列表与录入（银行存款、债券、外币储蓄、现金、负债）
struct ManualAssetsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query(sort: \BankDepositAccount.updatedAt, order: .reverse) private var deposits: [BankDepositAccount]
    @Query(sort: \FXSavingsAccount.updatedAt, order: .reverse) private var fxSavings: [FXSavingsAccount]
    @Query(sort: \BondHolding.updatedAt, order: .reverse) private var bonds: [BondHolding]
    @Query(sort: \CashOtherAsset.updatedAt, order: .reverse) private var cashOthers: [CashOtherAsset]
    @Query(sort: \LiabilityRecord.updatedAt, order: .reverse) private var liabilities: [LiabilityRecord]
    @Query private var settingsList: [AppSettings]

    @State private var editor: ManualEditorSession?
    @State private var showFirstSecurityTip = false
    @State private var pendingDeleteLiabilityID: UUID?
    @State private var confirmDeleteLiability = false

    private var settings: AppSettings {
        settingsList.first ?? AppSettings()
    }

    var body: some View {
        List {
            Section("银行存款") {
                NavigationLink {
                    BankDepositsView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("管理活期 / 定期")
                                .font(.headline)
                            Text(deposits.isEmpty ? "添加各银行存单" : "共 \(deposits.count) 笔")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Section("外币") {
                NavigationLink { FXSavingsManageView() } label: {
                    Label(fxSavings.isEmpty ? "添加外币" : "共 \(fxSavings.count) 笔", systemImage: "dollarsign.circle")
                }
            }

            Section("债券") {
                NavigationLink { BondHoldingsManageView() } label: {
                    Label(bonds.isEmpty ? "添加债券" : "共 \(bonds.count) 笔", systemImage: "doc.plaintext")
                }
            }

            Section("现金/其他") {
                NavigationLink { CashOtherManageView() } label: {
                    Label(cashOthers.isEmpty ? "添加现金/其他" : "共 \(cashOthers.count) 笔", systemImage: "banknote")
                }
            }

            Section("负债") {
                if liabilities.isEmpty {
                    Button("添加负债") { editor = .create(.liability, depositKind: .demand) }
                } else {
                    ForEach(liabilities, id: \.id) { item in
                        Button {
                            editor = .editLiability(item.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(MoneyFormat.compact(item.balance)) \(item.currency)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(MoneyFormat.compact(item.balance * settings.rateToCNY(for: item.currency)))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDeleteLiabilityID = item.id
                                confirmDeleteLiability = true
                            } label: { Label("删除", systemImage: "trash.fill") }
                            .tint(.red)
                        }
                    }
                    Button("添加负债") { editor = .create(.liability, depositKind: .demand) }
                }
            }
        }
        .navigationTitle("手动资产")
        .wkPageChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink { BankDepositsView() } label: { Text("银行存款") }
                    Button("外币") { editor = .create(.fxSavings, depositKind: .demand) }
                    Button("债券") { editor = .create(.bond, depositKind: .demand) }
                    Button("现金/其他") { editor = .create(.cashOther, depositKind: .demand) }
                    Button("负债") { editor = .create(.liability, depositKind: .demand) }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editor) { session in
            ManualAssetEditorView(session: session)
        }
        .alert("删除该负债？", isPresented: $confirmDeleteLiability) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteLiabilityID,
                   let item = liabilities.first(where: { $0.id == id }) {
                    context.delete(item)
                    try? context.save()
                }
                pendingDeleteLiabilityID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteLiabilityID = nil }
        } message: {
            Text("删除后不可恢复。")
        }
        .onAppear {
            if !SecurityTipStorage.hasSeenManualAssetsTip {
                showFirstSecurityTip = true
            }
        }
        .alert("安全提示", isPresented: $showFirstSecurityTip) {
            Button("知道了") {
                SecurityTipStorage.markManualAssetsTipSeen()
            }
        } message: {
            Text("本 App 只用于记录资产、查看行情和估算收益，不提供银行或券商账户登录、交易或转账功能。使用过程中无需提供或输入银行密码、券商密码、短信验证码或支付密码，请放心使用。")
        }
    }
}

enum ManualEditorKind: Hashable {
    case bankDeposit, fxSavings, bond, cashOther, liability
}

enum ManualFlowKind: String, Hashable {
    case none
    case inbound
    case outbound
}

struct ManualAssetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme

    let session: ManualEditorSession
    var initialFlow: ManualFlowKind = .none

    @State private var name = ""
    @State private var balanceText = ""
    @State private var currency = "CNY"
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
    @State private var productName = ""
    @State private var wealthStyle: BankWealthStyle = .netValue
    @State private var riskLevel: BankWealthRiskLevel = .r2
    @State private var unitNavText = "1"
    @State private var hasExpectedRedemptionDate = false
    @State private var expectedRedemptionDate = Date()
    /// 赎回时：无预计到账日则需手填实际到账日
    @State private var redeemSettlementDate = Date()
    @State private var redeemIncomeText = ""
    @State private var purchaseDate = Date()
    @State private var couponFrequency: BondCouponPaymentFrequency = .unset
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var recordPrincipalEvent = true
    @State private var didLoad = false
    /// 外币：汇入/汇出；债券：买入增持/卖出减持
    @State private var flowKind: ManualFlowKind = .none
    @State private var flowAmountText = ""
    @State private var flowFaceText = ""
    /// 已到账利息是否由利率+起息日自动估算（手改后不再覆盖；仅活期/外币）
    @State private var autoReceivedInterest = true
    @State private var isWritingReceived = false
    /// 定期预计利息是否自动估算（手改后不再覆盖）
    @State private var autoAccruedInterest = true
    @State private var isWritingAccrued = false
    /// 现金/其他物件类型肖像
    @State private var cashOtherKind: CashOtherKind = .cash

    init(session: ManualEditorSession, initialFlow: ManualFlowKind = .none) {
        self.session = session
        self.initialFlow = initialFlow
    }

    init(kind: ManualEditorKind, defaultDepositKind: BankDepositKind = .demand) {
        self.session = .create(kind, depositKind: defaultDepositKind)
    }

    private var kind: ManualEditorKind {
        switch session {
        case .create(let k, _, _, _): return k
        case .editDeposit: return .bankDeposit
        case .editBond: return .bond
        case .editFX: return .fxSavings
        case .editCash: return .cashOther
        case .editLiability: return .liability
        }
    }

    private var isEditing: Bool {
        if case .create = session { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .cashOther {
                    Section {
                        CashOtherKindPortraitPicker(selection: $cashOtherKind)
                    } header: {
                        Text("选择类型")
                    } footer: {
                        Text("点选肖像后填写名称与金额；金额可不填。")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section("基本信息") {
                    CJKTextField(
                        placeholder: kind == .bankDeposit
                            ? "银行名称，如招商银行"
                            : (kind == .cashOther ? cashOtherKind.namePlaceholder : "名称"),
                        text: $name
                    )
                    .frame(height: 40)
                    if kind == .bankDeposit && depositKind == .wealth {
                        CJKTextField(
                            placeholder: "理财产品名称，如朝朝盈",
                            text: $productName
                        )
                        .frame(height: 40)
                    }
                    if kind != .bond {
                        LabeledContent(
                            kind == .liability
                            ? "负债金额"
                            : (kind == .cashOther
                               ? "金额（可选）"
                               : (kind == .bankDeposit && depositKind == .wealth ? "投入本金" : "余额/金额"))
                        ) {
                            DecimalTextField(
                                placeholder: kind == .cashOther ? "可不填" : "可修改",
                                text: $balanceText
                            )
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

                if kind == .bankDeposit {
                    Section("账户类型") {
                        if isEditing {
                            LabeledContent("类型") {
                                Text(depositKind.displayName)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        } else {
                            Picker("类型", selection: $depositKind) {
                                ForEach(BankDepositKind.allCases) { item in
                                    Text(item.shortName).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: depositKind) { _, newValue in
                                switch newValue {
                                case .fixed:
                                    hasMaturity = true
                                    hasValueDate = true
                                    autoAccruedInterest = true
                                    autoReceivedInterest = false
                                    recalculateAccruedInterestIfNeeded()
                                case .wealth:
                                    hasMaturity = wealthStyle == .closed
                                    hasValueDate = wealthStyle == .closed
                                    autoAccruedInterest = true
                                    autoReceivedInterest = false
                                    if unitNavText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        unitNavText = ""
                                    }
                                    recalculateAccruedInterestIfNeeded()
                                case .demand:
                                    autoReceivedInterest = true
                                    recalculateReceivedInterestIfNeeded()
                                }
                            }
                        }
                    }
                    .listRowBackground(theme.cardBackground)
                }

                if kind == .bankDeposit && depositKind == .wealth {
                    Section {
                        Picker("产品形态", selection: $wealthStyle) {
                            ForEach(BankWealthStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .onChange(of: wealthStyle) { _, newValue in
                            switch newValue {
                            case .closed:
                                if !hasExpectedRedemptionDate {
                                    hasExpectedRedemptionDate = true
                                }
                                autoAccruedInterest = true
                                autoReceivedInterest = false
                                recalculateAccruedInterestIfNeeded()
                            case .netValue, .cashManagement:
                                autoAccruedInterest = true
                                autoReceivedInterest = false
                                recalculateAccruedInterestIfNeeded()
                            }
                        }
                        Picker("风险等级", selection: $riskLevel) {
                            ForEach(BankWealthRiskLevel.allCases) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        if wealthStyle == .netValue || wealthStyle == .cashManagement {
                            LabeledContent("单位净值（可选）") {
                                DecimalTextField(placeholder: "可不填，默认 1", text: $unitNavText)
                                    .frame(height: 40)
                            }
                        }
                        LabeledContent("年化利率%（可选）") {
                            DecimalTextField(placeholder: "有利率可自动估收益", text: $rateText)
                                .frame(height: 40)
                        }
                        Toggle("起息日（可选）", isOn: $hasValueDate)
                        if hasValueDate {
                            DatePicker("起息日", selection: $valueDate, displayedComponents: .date)
                        }
                        Toggle("到期日（可选）", isOn: $hasMaturity)
                        if hasMaturity {
                            DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                        }
                        Toggle("预计赎回到账日", isOn: $hasExpectedRedemptionDate)
                        if hasExpectedRedemptionDate {
                            DatePicker("预计到账日", selection: $expectedRedemptionDate, displayedComponents: .date)
                        }
                        LabeledContent("预计收益（可选）") {
                            DecimalTextField(
                                placeholder: autoAccruedInterest ? "有利率时自动估算，可改" : "可手动填写",
                                text: $accruedText
                            )
                            .frame(height: 40)
                        }
                        LabeledContent("已兑付收益") {
                            DecimalTextField(placeholder: "兑付后填写", text: $receivedText)
                                .frame(height: 40)
                        }
                    } header: {
                        Text("理财信息")
                    }
                    .listRowBackground(theme.cardBackground)
                } else if kind == .bankDeposit || kind == .fxSavings {
                    Section {
                        LabeledContent("年利率%") {
                            DecimalTextField(placeholder: "如 1.5", text: $rateText)
                                .frame(height: 40)
                        }
                        Toggle("起息日", isOn: $hasValueDate)
                        if hasValueDate {
                            DatePicker("起息日", selection: $valueDate, displayedComponents: .date)
                        }
                        if kind == .bankDeposit && depositKind == .fixed {
                            Toggle("到期日", isOn: $hasMaturity)
                            if hasMaturity {
                                DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                            }
                            LabeledContent("预计利息") {
                                DecimalTextField(
                                    placeholder: autoAccruedInterest ? "自动估算" : "可修改",
                                    text: $accruedText
                                )
                                .frame(height: 40)
                            }
                            LabeledContent("已到账利息") {
                                DecimalTextField(placeholder: "到期或到账后填写", text: $receivedText)
                                    .frame(height: 40)
                            }
                        } else {
                            LabeledContent("已到账利息") {
                                DecimalTextField(placeholder: autoReceivedInterest ? "自动估算" : "可修改", text: $receivedText)
                                    .frame(height: 40)
                            }
                            LabeledContent("预计利息") {
                                DecimalTextField(placeholder: "可修改", text: $accruedText)
                                    .frame(height: 40)
                            }
                            if kind == .fxSavings {
                                Toggle("到期日", isOn: $hasMaturity)
                                if hasMaturity {
                                    DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                                }
                            }
                        }
                    } header: {
                        Text("利率与日期")
                    }
                    .listRowBackground(theme.cardBackground)
                }

                if kind == .bond {
                    Section("必填") {
                        LabeledContent("持有面值") {
                            DecimalTextField(placeholder: "必填", text: $faceText)
                                .frame(height: 40)
                        }
                        DatePicker("买入日期", selection: $purchaseDate, displayedComponents: .date)
                    }
                    .listRowBackground(theme.cardBackground)

                    Section("可选") {
                        Toggle("起息日", isOn: $hasValueDate)
                        if hasValueDate {
                            DatePicker("起息日", selection: $valueDate, displayedComponents: .date)
                        }
                        Toggle("到期日", isOn: $hasMaturity)
                        if hasMaturity {
                            DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                        }
                        Toggle("预计赎回到账日", isOn: $hasExpectedRedemptionDate)
                        if hasExpectedRedemptionDate {
                            DatePicker("预计到账日", selection: $expectedRedemptionDate, displayedComponents: .date)
                        }
                        LabeledContent("票面利率%") {
                            DecimalTextField(placeholder: "可选", text: $couponText)
                                .frame(height: 40)
                        }
                        Picker("付息方式", selection: $couponFrequency) {
                            ForEach(BondCouponPaymentFrequency.allCases) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }
                        LabeledContent("成本") {
                            DecimalTextField(placeholder: "可选，默认按面值", text: $costText)
                                .frame(height: 40)
                        }
                        LabeledContent("最新估值") {
                            DecimalTextField(placeholder: "可选", text: $marketValueText)
                                .frame(height: 40)
                        }
                        LabeledContent("预计利息") {
                            DecimalTextField(placeholder: "可选", text: $accruedText)
                                .frame(height: 40)
                        }
                        LabeledContent("已到账利息") {
                            DecimalTextField(placeholder: "可选", text: $receivedText)
                                .frame(height: 40)
                        }
                    }
                    .listRowBackground(theme.cardBackground)
                }

                if isEditing && (kind == .fxSavings || kind == .bankDeposit) {
                    Section {
                        Picker("资金变动", selection: $flowKind) {
                            Text("不变动").tag(ManualFlowKind.none)
                            Text(bankFlowInboundTitle).tag(ManualFlowKind.inbound)
                            Text(bankFlowOutboundTitle).tag(ManualFlowKind.outbound)
                        }
                        .pickerStyle(.segmented)
                        if flowKind != .none {
                            LabeledContent(flowKind == .inbound
                                           ? "\(bankFlowInboundTitle)金额"
                                           : "\(bankFlowOutboundTitle)金额") {
                                DecimalTextField(placeholder: "原币金额", text: $flowAmountText)
                                    .frame(height: 40)
                            }
                        }
                        if kind == .bankDeposit, depositKind == .wealth, flowKind == .outbound {
                            DatePicker("到账日期", selection: $redeemSettlementDate, displayedComponents: .date)
                            LabeledContent("本次兑付收益") {
                                DecimalTextField(placeholder: "无收益填 0", text: $redeemIncomeText)
                                    .frame(height: 40)
                            }
                        }
                    } header: {
                        Text(kind == .bankDeposit
                             ? (depositKind == .wealth ? "申购 / 赎回" : "存入 / 取出")
                             : "汇入 / 汇出")
                    }
                    .listRowBackground(theme.cardBackground)
                }

                if !isEditing && (kind == .bankDeposit || kind == .fxSavings || kind == .cashOther || kind == .bond) {
                    Section {
                        Toggle("同时记入本金流水", isOn: $recordPrincipalEvent)
                    }
                    .listRowBackground(theme.cardBackground)
                }

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
            .onAppear { loadIfNeeded() }
            .onChange(of: rateText) { _, _ in recalculateInterestFieldsIfNeeded() }
            .onChange(of: balanceText) { _, _ in recalculateInterestFieldsIfNeeded() }
            .onChange(of: hasValueDate) { _, _ in recalculateInterestFieldsIfNeeded() }
            .onChange(of: valueDate) { _, _ in recalculateInterestFieldsIfNeeded() }
            .onChange(of: hasMaturity) { _, _ in recalculateAccruedInterestIfNeeded() }
            .onChange(of: maturityDate) { _, _ in recalculateAccruedInterestIfNeeded() }
            .onChange(of: hasExpectedRedemptionDate) { _, _ in recalculateAccruedInterestIfNeeded() }
            .onChange(of: expectedRedemptionDate) { _, _ in recalculateAccruedInterestIfNeeded() }
            .onChange(of: receivedText) { _, _ in
                if !isWritingReceived {
                    autoReceivedInterest = false
                }
            }
            .onChange(of: accruedText) { _, _ in
                if !isWritingAccrued {
                    autoAccruedInterest = false
                }
            }
        }
    }

    private var bankFlowInboundTitle: String {
        if kind == .bankDeposit && depositKind == .wealth { return "申购" }
        return kind == .bankDeposit ? "存入" : "汇入"
    }

    private var bankFlowOutboundTitle: String {
        if kind == .bankDeposit && depositKind == .wealth { return "赎回" }
        return kind == .bankDeposit ? "取出" : "汇出"
    }

    private func calculatedReceivedInterest() -> Decimal? {
        guard kind == .bankDeposit || kind == .fxSavings else { return nil }
        // 定期 / 封闭理财利息通常到期才到账，不按持有天数自动填「已到账」
        if kind == .bankDeposit && (depositKind == .fixed || depositKind == .wealth) { return nil }
        guard hasValueDate else { return nil }
        guard let balance = DecimalMath.parse(balanceText), balance > 0 else { return nil }
        guard let ratePercent = DecimalMath.parse(rateText), ratePercent > 0 else { return nil }
        return DecimalMath.simpleInterest(
            principal: balance,
            annualRate: ratePercent / 100,
            from: valueDate
        )
    }

    private func calculatedAccruedInterest() -> Decimal? {
        if kind == .bankDeposit && depositKind == .fixed {
            guard hasValueDate, hasMaturity else { return nil }
            guard let balance = DecimalMath.parse(balanceText), balance > 0 else { return nil }
            guard let ratePercent = DecimalMath.parse(rateText), ratePercent > 0 else { return nil }
            return DecimalMath.simpleInterest(
                principal: balance,
                annualRate: ratePercent / 100,
                from: valueDate,
                to: maturityDate
            )
        }
        if kind == .bankDeposit && depositKind == .wealth {
            guard let balance = DecimalMath.parse(balanceText), balance > 0 else { return nil }
            guard let ratePercent = DecimalMath.parse(rateText), ratePercent > 0 else { return nil }
            let annualRate = ratePercent / 100
            if hasValueDate {
                let endDate: Date = {
                    if hasMaturity { return maturityDate }
                    if hasExpectedRedemptionDate { return expectedRedemptionDate }
                    return .now
                }()
                return DecimalMath.simpleInterest(
                    principal: balance,
                    annualRate: annualRate,
                    from: valueDate,
                    to: endDate
                )
            }
            // 无起息/到期日时：按一年预计收益估算
            return balance * annualRate
        }
        return nil
    }

    private func recalculateInterestFieldsIfNeeded() {
        recalculateReceivedInterestIfNeeded()
        recalculateAccruedInterestIfNeeded()
    }

    private func recalculateReceivedInterestIfNeeded() {
        guard kind == .bankDeposit || kind == .fxSavings else { return }
        guard autoReceivedInterest else { return }
        guard let interest = calculatedReceivedInterest() else { return }
        isWritingReceived = true
        receivedText = DecimalMath.plainString(interest, fractionDigits: 2)
        isWritingReceived = false
    }

    private func recalculateAccruedInterestIfNeeded() {
        let useFormula = kind == .bankDeposit && (
            depositKind == .fixed || depositKind == .wealth
        )
        guard useFormula else { return }
        guard autoAccruedInterest else { return }
        guard let interest = calculatedAccruedInterest() else { return }
        isWritingAccrued = true
        accruedText = DecimalMath.plainString(interest, fractionDigits: 2)
        isWritingAccrued = false
    }

    private var title: String {
        let prefix = isEditing ? "修改" : "添加"
        switch kind {
        case .bankDeposit:
            return "\(prefix)\(depositKind.displayName)"
        case .fxSavings: return "\(prefix)外币"
        case .bond: return "\(prefix)债券"
        case .cashOther: return "\(prefix)现金/其他"
        case .liability: return "\(prefix)负债"
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        flowKind = initialFlow
        switch session {
        case .create(_, let dk, let presetName, _):
            depositKind = dk
            if let presetName {
                let trimmedPreset = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPreset.isEmpty {
                    name = trimmedPreset
                }
            }
            switch dk {
            case .fixed:
                hasMaturity = true
                hasValueDate = true
                autoAccruedInterest = true
                autoReceivedInterest = false
            case .wealth:
                wealthStyle = .netValue
                riskLevel = .r2
                unitNavText = ""
                hasExpectedRedemptionDate = false
                autoAccruedInterest = true
                autoReceivedInterest = false
                recalculateAccruedInterestIfNeeded()
            case .demand:
                break
            }
            if kind == .fxSavings { currency = "USD" }
            recordPrincipalEvent = true
        case .editDeposit(let id):
            recordPrincipalEvent = false
            let all = (try? context.fetch(FetchDescriptor<BankDepositAccount>())) ?? []
            guard let item = all.first(where: { $0.id == id }) else { return }
            name = item.name
            productName = item.productName
            balanceText = DecimalMath.plainString(item.balance)
            currency = item.currency
            rateText = DecimalMath.plainString(item.annualRate * 100, fractionDigits: 4)
            accruedText = DecimalMath.plainString(item.displayAccruedInterest)
            receivedText = DecimalMath.plainString(item.receivedInterest)
            depositKind = item.depositKind
            wealthStyle = item.wealthStyle
            riskLevel = item.riskLevel
            unitNavText = DecimalMath.plainString(item.unitNav, fractionDigits: 4)
            note = item.note
            if let v = item.valueDate { valueDate = v; hasValueDate = true }
            if let m = item.maturityDate { maturityDate = m; hasMaturity = true }
            if let expected = item.expectedRedemptionDate {
                expectedRedemptionDate = expected
                hasExpectedRedemptionDate = true
                redeemSettlementDate = expected
            } else {
                hasExpectedRedemptionDate = false
                redeemSettlementDate = .now
            }
            if item.depositKind == .fixed || item.depositKind == .wealth {
                autoReceivedInterest = false
                if let est = item.estimatedMaturityInterest() ?? calculatedAccruedInterest() {
                    autoAccruedInterest = item.accruedInterest == 0 || item.accruedInterest == est
                } else {
                    autoAccruedInterest = item.accruedInterest == 0
                }
                recalculateAccruedInterestIfNeeded()
            } else {
                autoAccruedInterest = false
                autoReceivedInterest = item.receivedInterest == 0
                if autoReceivedInterest {
                    recalculateReceivedInterestIfNeeded()
                }
            }
        case .editBond(let id):
            recordPrincipalEvent = false
            let all = (try? context.fetch(FetchDescriptor<BondHolding>())) ?? []
            guard let item = all.first(where: { $0.id == id }) else { return }
            name = item.name
            currency = item.currency
            faceText = DecimalMath.plainString(item.faceValue)
            costText = item.cost > 0 ? DecimalMath.plainString(item.cost) : ""
            couponText = item.couponRate > 0 ? DecimalMath.plainString(item.couponRate * 100, fractionDigits: 4) : ""
            if let mv = item.marketValue { marketValueText = DecimalMath.plainString(mv) }
            accruedText = item.accruedInterest > 0 ? DecimalMath.plainString(item.accruedInterest) : ""
            receivedText = item.receivedInterest > 0 ? DecimalMath.plainString(item.receivedInterest) : ""
            purchaseDate = item.purchaseDate
            couponFrequency = item.couponFrequency
            note = item.note
            if let v = item.valueDate { valueDate = v; hasValueDate = true }
            if let m = item.maturityDate { maturityDate = m; hasMaturity = true }
            if let expected = item.expectedRedemptionDate {
                expectedRedemptionDate = expected
                hasExpectedRedemptionDate = true
            }
        case .editFX(let id):
            recordPrincipalEvent = false
            let all = (try? context.fetch(FetchDescriptor<FXSavingsAccount>())) ?? []
            guard let item = all.first(where: { $0.id == id }) else { return }
            name = item.name
            balanceText = DecimalMath.plainString(item.balance)
            currency = item.currency
            rateText = DecimalMath.plainString(item.annualRate * 100, fractionDigits: 4)
            accruedText = DecimalMath.plainString(item.accruedInterest)
            receivedText = DecimalMath.plainString(item.receivedInterest)
            note = item.note
            if let v = item.valueDate { valueDate = v; hasValueDate = true }
            if let m = item.maturityDate { maturityDate = m; hasMaturity = true }
            autoReceivedInterest = item.receivedInterest == 0
            if autoReceivedInterest {
                recalculateReceivedInterestIfNeeded()
            }
        case .editCash(let id):
            recordPrincipalEvent = false
            let all = (try? context.fetch(FetchDescriptor<CashOtherAsset>())) ?? []
            guard let item = all.first(where: { $0.id == id }) else { return }
            name = item.name
            balanceText = item.balance > 0 ? "\(item.balance)" : ""
            currency = item.currency
            note = item.note
            cashOtherKind = item.kind
        case .editLiability(let id):
            recordPrincipalEvent = false
            let all = (try? context.fetch(FetchDescriptor<LiabilityRecord>())) ?? []
            guard let item = all.first(where: { $0.id == id }) else { return }
            name = item.name
            balanceText = "\(item.balance)"
            currency = item.currency
            note = item.note
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind != .cashOther {
            guard !trimmed.isEmpty else {
                errorMessage = "请填写名称"
                return
            }
        }

        func dec(_ text: String, allowEmpty: Bool = true) -> Decimal? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return allowEmpty ? 0 : nil }
            return DecimalMath.parse(t)
        }

        do {
            switch kind {
            case .bankDeposit:
                BankNameStore.add(trimmed)
                guard var balance = dec(balanceText, allowEmpty: false), balance >= 0 else {
                    errorMessage = "请填写有效余额"; return
                }
                if depositKind == .fixed, !hasMaturity {
                    errorMessage = "定期存款请填写到期日"; return
                }
                if depositKind == .fixed, !hasValueDate {
                    errorMessage = "定期存款请填写起息日"; return
                }
                // 银行理财：起息日、到期日、利率均不强制。
                let annual = (dec(rateText) ?? 0) / 100
                var accrued = dec(accruedText) ?? 0
                var received = dec(receivedText) ?? 0
                // 单位净值：不填默认为 1（勿用 dec()，空串会被当成 0）
                let unitNav: Decimal = {
                    let raw = unitNavText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty, let parsed = DecimalMath.parse(raw), parsed > 0 else {
                        return 1
                    }
                    return parsed
                }()
                let maturity = hasMaturity ? maturityDate : nil
                let value = hasValueDate ? valueDate : nil
                let canAutoAccrue = depositKind == .fixed || depositKind == .wealth
                if canAutoAccrue, autoAccruedInterest, let estimated = calculatedAccruedInterest() {
                    accrued = estimated
                }
                var flowEvent: (ManualCapitalEventKind, Decimal, Date, String)?
                var incomeEvent: (Decimal, Date)?
                if isEditing, flowKind != .none {
                    guard let flowAmt = dec(flowAmountText, allowEmpty: false), flowAmt > 0 else {
                        errorMessage = depositKind == .wealth
                            ? "请填写有效申购/赎回金额"
                            : "请填写有效存入/取出金额"
                        return
                    }
                    switch flowKind {
                    case .inbound:
                        balance += flowAmt
                        flowEvent = (.deposit, flowAmt, .now, depositKind == .wealth ? "申购" : "存入")
                    case .outbound:
                        guard balance >= flowAmt else {
                            errorMessage = depositKind == .wealth
                                ? "赎回金额不能大于当前投入本金"
                                : "取出金额不能大于当前余额"
                            return
                        }
                        if depositKind == .wealth {
                            let settleDate = redeemSettlementDate
                            let income = dec(redeemIncomeText) ?? 0
                            if income < 0 {
                                errorMessage = "兑付收益不能为负"; return
                            }
                            balance -= flowAmt
                            flowEvent = (.withdraw, flowAmt, settleDate, "赎回到账")
                            if income > 0 {
                                received += income
                                incomeEvent = (income, settleDate)
                            }
                            if balance == 0 {
                                hasExpectedRedemptionDate = false
                            }
                        } else {
                            balance -= flowAmt
                            flowEvent = (.withdraw, flowAmt, .now, "取出")
                        }
                    case .none:
                        break
                    }
                }

                let trimmedProduct = productName.trimmingCharacters(in: .whitespacesAndNewlines)
                let savedExpectedRedeem: Date? = {
                    guard depositKind == .wealth, balance > 0, hasExpectedRedemptionDate else { return nil }
                    return expectedRedemptionDate
                }()

                if case .editDeposit(let id) = session,
                   let item = ((try? context.fetch(FetchDescriptor<BankDepositAccount>())) ?? []).first(where: { $0.id == id }) {
                    item.name = trimmed
                    item.productName = depositKind == .wealth ? trimmedProduct : ""
                    item.balance = balance
                    item.currency = currency
                    item.annualRate = annual
                    item.accruedInterest = accrued
                    item.receivedInterest = received
                    // 编辑时锁定类型，避免「存入」时把定期改成活期覆盖原账户。
                    let lockedKind = item.depositKind
                    item.depositKind = lockedKind
                    item.wealthStyle = wealthStyle
                    item.riskLevel = riskLevel
                    item.unitNav = (lockedKind == .wealth && (wealthStyle == .netValue || wealthStyle == .cashManagement))
                        ? unitNav
                        : 1
                    item.valueDate = value
                    item.maturityDate = (lockedKind == .fixed || lockedKind == .wealth) ? maturity : nil
                    item.expectedRedemptionDate = lockedKind == .wealth ? savedExpectedRedeem : nil
                    item.note = note
                    item.updatedAt = .now
                    if let flowEvent {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .bankDeposit, kind: flowEvent.0,
                            amount: flowEvent.1, currency: currency,
                            eventDate: flowEvent.2, note: flowEvent.3
                        ))
                    }
                    if let incomeEvent {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .bankDeposit, kind: .interestReceived,
                            amount: incomeEvent.0, currency: currency,
                            eventDate: incomeEvent.1, note: "收益到账"
                        ))
                    }
                    if lockedKind == .wealth, flowKind == .outbound {
                        BankWealthRedemptionPromptStore.markPrompted(item.id)
                    } else if lockedKind == .wealth, let expected = savedExpectedRedeem,
                              Calendar.current.startOfDay(for: expected) > Calendar.current.startOfDay(for: .now) {
                        BankWealthRedemptionPromptStore.clearPrompted(item.id)
                    }
                } else {
                    let item = BankDepositAccount(
                        name: trimmed,
                        balance: balance,
                        currency: currency,
                        annualRate: annual,
                        valueDate: value,
                        maturityDate: maturity,
                        expectedRedemptionDate: savedExpectedRedeem,
                        accruedInterest: accrued,
                        receivedInterest: received,
                        depositKind: depositKind,
                        productName: depositKind == .wealth ? trimmedProduct : "",
                        wealthStyle: wealthStyle,
                        riskLevel: riskLevel,
                        unitNav: (depositKind == .wealth && (wealthStyle == .netValue || wealthStyle == .cashManagement))
                            ? unitNav
                            : 1,
                        note: note
                    )
                    context.insert(item)
                    if recordPrincipalEvent, balance > 0 {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .bankDeposit, kind: .deposit,
                            amount: balance, currency: currency,
                            note: "录入时本金"
                        ))
                    }
                }

            case .fxSavings:
                guard currency != "CNY" else { errorMessage = "外币请选择非人民币币种"; return }
                guard var balance = dec(balanceText, allowEmpty: false), balance >= 0 else {
                    errorMessage = "请填写有效余额"; return
                }
                let annual = (dec(rateText) ?? 0) / 100
                let accrued = dec(accruedText) ?? 0
                let received = dec(receivedText) ?? 0
                var flowEvent: (ManualCapitalEventKind, Decimal)?
                if isEditing, flowKind != .none {
                    guard let flowAmt = dec(flowAmountText, allowEmpty: false), flowAmt > 0 else {
                        errorMessage = "请填写有效汇入/汇出金额"; return
                    }
                    switch flowKind {
                    case .inbound:
                        balance += flowAmt
                        flowEvent = (.deposit, flowAmt)
                    case .outbound:
                        guard balance >= flowAmt else {
                            errorMessage = "汇出金额不能大于当前余额"; return
                        }
                        balance -= flowAmt
                        flowEvent = (.withdraw, flowAmt)
                    case .none:
                        break
                    }
                }
                if case .editFX(let id) = session,
                   let item = ((try? context.fetch(FetchDescriptor<FXSavingsAccount>())) ?? []).first(where: { $0.id == id }) {
                    item.name = trimmed
                    item.balance = balance
                    item.currency = currency
                    item.annualRate = annual
                    item.accruedInterest = accrued
                    item.receivedInterest = received
                    item.valueDate = hasValueDate ? valueDate : nil
                    item.maturityDate = hasMaturity ? maturityDate : nil
                    item.note = note
                    item.updatedAt = .now
                    if let flowEvent {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .fxSavings, kind: flowEvent.0,
                            amount: flowEvent.1, currency: currency,
                            note: flowEvent.0 == .deposit ? "汇入" : "汇出"
                        ))
                    }
                } else {
                    let item = FXSavingsAccount(
                        name: trimmed, balance: balance, currency: currency, annualRate: annual,
                        valueDate: hasValueDate ? valueDate : nil,
                        maturityDate: hasMaturity ? maturityDate : nil,
                        accruedInterest: accrued, receivedInterest: received, note: note
                    )
                    context.insert(item)
                    if recordPrincipalEvent, balance > 0 {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .fxSavings, kind: .deposit,
                            amount: balance, currency: currency, note: "录入时本金"
                        ))
                    }
                }

            case .bond:
                guard var face = dec(faceText, allowEmpty: false), face > 0 else {
                    errorMessage = "请填写有效持有面值"; return
                }
                let costInput = costText.trimmingCharacters(in: .whitespacesAndNewlines)
                var cost = costInput.isEmpty ? face : (dec(costText) ?? face)
                if cost < 0 {
                    errorMessage = "成本不能为负"; return
                }
                let coupon = (dec(couponText) ?? 0) / 100
                let mvText = marketValueText.trimmingCharacters(in: .whitespacesAndNewlines)
                let mv = mvText.isEmpty ? nil : DecimalMath.parse(mvText)
                let accrued = dec(accruedText) ?? 0
                let received = dec(receivedText) ?? 0
                let expectedRedeem = hasExpectedRedemptionDate ? expectedRedemptionDate : nil
                var flowEvent: (ManualCapitalEventKind, Decimal)?
                if isEditing, flowKind != .none {
                    guard let flowAmt = dec(flowAmountText, allowEmpty: false), flowAmt > 0 else {
                        errorMessage = "请填写有效买入/卖出金额"; return
                    }
                    let faceDelta = dec(flowFaceText) ?? 0
                    switch flowKind {
                    case .inbound:
                        cost += flowAmt
                        face += faceDelta
                        flowEvent = (.deposit, flowAmt)
                    case .outbound:
                        guard cost >= flowAmt else {
                            errorMessage = "卖出金额不能大于当前成本"; return
                        }
                        guard face >= faceDelta else {
                            errorMessage = "减少面值不能大于当前持有面值"; return
                        }
                        cost -= flowAmt
                        face -= faceDelta
                        flowEvent = (.withdraw, flowAmt)
                    case .none:
                        break
                    }
                }
                if case .editBond(let id) = session,
                   let item = ((try? context.fetch(FetchDescriptor<BondHolding>())) ?? []).first(where: { $0.id == id }) {
                    item.name = trimmed
                    item.currency = currency
                    item.faceValue = face
                    item.cost = cost
                    item.couponRate = coupon
                    item.purchaseDate = purchaseDate
                    item.valueDate = hasValueDate ? valueDate : nil
                    item.maturityDate = hasMaturity ? maturityDate : nil
                    item.expectedRedemptionDate = face > 0 ? expectedRedeem : nil
                    item.couponFrequency = couponFrequency
                    item.marketValue = mv
                    item.accruedInterest = accrued
                    item.receivedInterest = received
                    item.note = note
                    item.updatedAt = .now
                    if let expected = item.expectedRedemptionDate ?? item.maturityDate,
                       Calendar.current.startOfDay(for: expected) > Calendar.current.startOfDay(for: .now) {
                        BondSettlementPromptStore.clearPrompted(item.id)
                    }
                    if let flowEvent {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .bond, kind: flowEvent.0,
                            amount: flowEvent.1, currency: currency,
                            note: flowEvent.0 == .deposit ? "买入增持" : "卖出减持"
                        ))
                    }
                } else if let existing = ((try? context.fetch(FetchDescriptor<BondHolding>())) ?? []).first(where: {
                    $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                        && $0.currency.uppercased() == currency.uppercased()
                        && $0.faceValue > 0
                }) {
                    // 同一债券再次录入：合并面值与成本，保留已有产品信息，更新最近买入日
                    existing.faceValue += face
                    existing.cost += cost
                    existing.purchaseDate = purchaseDate
                    if let marketValue = existing.marketValue {
                        existing.marketValue = marketValue + cost
                    } else if let mv {
                        existing.marketValue = existing.cost - cost + mv
                    }
                    if existing.couponRate <= 0, coupon > 0 {
                        existing.couponRate = coupon
                    }
                    if existing.valueDate == nil, hasValueDate {
                        existing.valueDate = valueDate
                    }
                    if existing.maturityDate == nil, hasMaturity {
                        existing.maturityDate = maturityDate
                    }
                    if existing.expectedRedemptionDate == nil, let expectedRedeem {
                        existing.expectedRedemptionDate = expectedRedeem
                    }
                    if existing.couponFrequency == .unset, couponFrequency != .unset {
                        existing.couponFrequency = couponFrequency
                    }
                    existing.accruedInterest += accrued
                    existing.receivedInterest += received
                    existing.updatedAt = .now
                    if recordPrincipalEvent, cost > 0 {
                        context.insert(ManualCapitalEvent(
                            assetID: existing.id, assetClass: .bond, kind: .deposit,
                            amount: cost, currency: currency,
                            eventDate: purchaseDate, note: "买入增持"
                        ))
                    }
                } else {
                    let item = BondHolding(
                        name: trimmed,
                        currency: currency,
                        faceValue: face,
                        cost: cost,
                        couponRate: coupon,
                        purchaseDate: purchaseDate,
                        valueDate: hasValueDate ? valueDate : nil,
                        maturityDate: hasMaturity ? maturityDate : nil,
                        expectedRedemptionDate: expectedRedeem,
                        couponFrequency: couponFrequency,
                        marketValue: mv,
                        accruedInterest: accrued,
                        receivedInterest: received,
                        note: note
                    )
                    context.insert(item)
                    if recordPrincipalEvent, cost > 0 {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .bond, kind: .deposit,
                            amount: cost, currency: currency,
                            eventDate: purchaseDate, note: "录入时成本本金"
                        ))
                    }
                }

            case .cashOther:
                let balance = dec(balanceText, allowEmpty: true) ?? 0
                guard balance >= 0 else {
                    errorMessage = "请填写有效金额"; return
                }
                let displayName = trimmed.isEmpty ? cashOtherKind.title : trimmed
                if case .editCash(let id) = session,
                   let item = ((try? context.fetch(FetchDescriptor<CashOtherAsset>())) ?? []).first(where: { $0.id == id }) {
                    item.name = displayName
                    item.balance = balance
                    item.currency = currency
                    item.note = note
                    item.kind = cashOtherKind
                    item.updatedAt = .now
                } else {
                    let item = CashOtherAsset(
                        name: displayName,
                        balance: balance,
                        currency: currency,
                        note: note,
                        kind: cashOtherKind
                    )
                    context.insert(item)
                    if recordPrincipalEvent, balance > 0 {
                        context.insert(ManualCapitalEvent(
                            assetID: item.id, assetClass: .cashOther, kind: .deposit,
                            amount: balance, currency: currency, note: "录入时本金"
                        ))
                    }
                }

            case .liability:
                guard let balance = dec(balanceText, allowEmpty: false), balance >= 0 else {
                    errorMessage = "请填写有效负债金额"; return
                }
                if case .editLiability(let id) = session,
                   let item = ((try? context.fetch(FetchDescriptor<LiabilityRecord>())) ?? []).first(where: { $0.id == id }) {
                    item.name = trimmed
                    item.balance = balance
                    item.currency = currency
                    item.note = note
                    item.updatedAt = .now
                } else {
                    context.insert(LiabilityRecord(name: trimmed, balance: balance, currency: currency, note: note))
                }
            }

            try context.save()
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 现金/其他物件肖像选择

private struct CashOtherKindPortraitPicker: View {
    @Binding var selection: CashOtherKind

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CashOtherKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: kind.softHex))
                                .frame(width: 52, height: 52)
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color(hex: kind.strongHex))
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selection == kind ? Color(hex: kind.strongHex) : Color.clear,
                                    lineWidth: 2.5
                                )
                                .frame(width: 56, height: 56)
                        }
                        Text(kind.title)
                            .font(.caption.weight(selection == kind ? .semibold : .regular))
                            .foregroundStyle(selection == kind ? Color(hex: kind.strongHex) : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title)
                .accessibilityAddTraits(selection == kind ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}
