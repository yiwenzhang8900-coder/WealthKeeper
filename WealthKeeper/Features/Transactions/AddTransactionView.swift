import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    let transactionID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var transactions: [TransactionRecord]
    @Query private var instruments: [Instrument]

    @State private var kind: TransactionKind = .buy
    @State private var tradeDate: Date = .now
    @State private var quantityText = ""
    @State private var sharesOnRecordText = ""
    @State private var priceText = ""
    @State private var feeText = ""
    @State private var cashAmountText = ""
    @State private var splitRatioText = "1"
    @State private var noteText = ""
    @State private var currencyText = ""
    @State private var didLoad = false
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    @State private var showSavedAlert = false

    private var transaction: TransactionRecord? {
        transactions.first { $0.id == transactionID }
    }

    private var instrument: Instrument? {
        guard let transaction else { return nil }
        return instruments.first { $0.id == transaction.instrumentID }
    }

    var body: some View {
        Group {
            if let tx = transaction {
                Form {
                    Section {
                        HStack(spacing: 10) {
                            if let market = instrument?.market {
                                Text(market.regionFlag).font(.largeTitle)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(instrument?.name.isEmpty == false ? (instrument?.name ?? tx.instrumentID) : tx.instrumentID)
                                    .font(.title3.weight(.semibold))
                                if let instrument {
                                    Text("\(instrument.market.displayName) · \(instrument.symbol)")
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("交易信息") {
                        Picker("类型", selection: $kind) {
                            ForEach(TransactionKind.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        DatePicker(
                            kind.isDividendEvent || kind == .bonusShare ? "权益登记日" : "交易日",
                            selection: $tradeDate,
                            displayedComponents: .date
                        )
                        if let instrument {
                            LabeledContent("代码") { Text(instrument.symbol).monospaced() }
                            LabeledContent("市场") {
                                Text("\(instrument.market.regionFlag) \(instrument.market.displayName)")
                            }
                            LabeledContent("币种") {
                                Text(currencyText.isEmpty ? instrument.currency : currencyText)
                            }
                        }
                    }

                    Section("金额明细（可修改）") {
                        switch kind {
                        case .buy, .sell:
                            LabeledContent("数量") {
                                DecimalTextField(placeholder: "如 100", text: $quantityText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("单价") {
                                DecimalTextField(placeholder: "如 39.20", text: $priceText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("手续费") {
                                DecimalTextField(placeholder: "可空", text: $feeText)
                                    .frame(minHeight: 36)
                            }
                            if let qty = DecimalMath.parse(quantityText),
                               let px = DecimalMath.parse(priceText),
                               qty > 0, px > 0 {
                                let fee = DecimalMath.parse(feeText) ?? 0
                                let notional = qty * px
                                LabeledContent("成交金额") {
                                    Text(MoneyFormat.compact(notional)).monospacedDigit()
                                }
                                LabeledContent("合计") {
                                    Text(MoneyFormat.compact(kind == .buy ? notional + fee : notional - fee))
                                        .monospacedDigit()
                                }
                            }
                        case .dividend:
                            LabeledContent("登记日持仓") {
                                DecimalTextField(placeholder: "可选", text: $sharesOnRecordText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("每股/份分红") {
                                DecimalTextField(placeholder: "可选", text: $priceText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("分红总额") {
                                DecimalTextField(placeholder: "必填或由上两项推算", text: $cashAmountText)
                                    .frame(minHeight: 36)
                            }
                        case .dividendReinvest:
                            LabeledContent("登记日持仓") {
                                DecimalTextField(placeholder: "可选", text: $sharesOnRecordText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("每份分红/净值") {
                                DecimalTextField(placeholder: "可选", text: $priceText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("再投资份额") {
                                DecimalTextField(placeholder: "到账份额", text: $quantityText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("分红等价金额") {
                                DecimalTextField(placeholder: "可选", text: $cashAmountText)
                                    .frame(minHeight: 36)
                            }
                        case .bonusShare:
                            LabeledContent("登记日持仓") {
                                DecimalTextField(placeholder: "可选", text: $sharesOnRecordText)
                                    .frame(minHeight: 36)
                            }
                            LabeledContent("送股数量") {
                                DecimalTextField(placeholder: "必填", text: $quantityText)
                                    .frame(minHeight: 36)
                            }
                        case .fee:
                            LabeledContent("费用") {
                                DecimalTextField(placeholder: "金额", text: $cashAmountText)
                                    .frame(minHeight: 36)
                            }
                        case .split:
                            LabeledContent("拆合股比例") {
                                DecimalTextField(placeholder: "如 2 = 1拆2", text: $splitRatioText)
                                    .frame(minHeight: 36)
                            }
                        }
                    }

                    Section("备注") {
                        CJKTextField(placeholder: "可选", text: $noteText)
                            .frame(height: 40)
                    }

                    Section("系统信息") {
                        LabeledContent("录入时间") {
                            Text(MoneyFormat.dateTime(tx.createdAt))
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
                ContentUnavailableView("交易不存在", systemImage: "tray")
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
            Text("交易已更新，持仓已重建。")
        }
        .confirmationDialog("删除这笔交易？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteCurrent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将重建相关持仓，此操作不可撤销。")
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let tx = transaction else { return }
        didLoad = true
        kind = tx.kind
        tradeDate = tx.recordDate ?? tx.tradeDate
        quantityText = tx.quantity > 0 ? DecimalMath.plainString(tx.quantity, fractionDigits: 4) : ""
        sharesOnRecordText = tx.sharesOnRecord > 0 ? DecimalMath.plainString(tx.sharesOnRecord, fractionDigits: 4) : ""
        priceText = tx.price > 0 ? DecimalMath.plainString(tx.price, fractionDigits: 4) : ""
        feeText = tx.fee > 0 ? DecimalMath.plainString(tx.fee, fractionDigits: 4) : ""
        cashAmountText = tx.cashAmount > 0 ? DecimalMath.plainString(tx.cashAmount, fractionDigits: 4) : ""
        splitRatioText = tx.splitRatio > 0 ? DecimalMath.plainString(tx.splitRatio, fractionDigits: 6) : "1"
        noteText = tx.note
        currencyText = tx.currency
    }

    private func saveEdits() {
        guard let tx = transaction else { return }
        guard let instrument else {
            errorMessage = "标的不存在，无法保存"
            showErrorAlert = true
            return
        }

        let input = TransactionSaveService.Input(
            market: instrument.market,
            assetType: instrument.type,
            symbol: instrument.symbol,
            name: instrument.name,
            currency: currencyText.isEmpty ? instrument.currency : currencyText,
            kind: kind,
            tradeDate: tradeDate,
            recordDate: (kind.isDividendEvent || kind == .bonusShare) ? tradeDate : nil,
            quantityText: quantityText,
            sharesOnRecordText: sharesOnRecordText,
            priceText: priceText,
            feeText: feeText,
            cashAmountText: cashAmountText,
            splitRatioText: splitRatioText,
            note: noteText
        )

        switch TransactionSaveService.prepare(input) {
        case .failure(let error):
            errorMessage = error.localizedDescription
            showErrorAlert = true
        case .success(let prepared):
            tx.instrumentID = prepared.instrumentID
            tx.kind = prepared.kind
            tx.tradeDate = prepared.tradeDate
            tx.recordDate = prepared.recordDate
            tx.quantity = prepared.quantity
            tx.sharesOnRecord = prepared.sharesOnRecord
            tx.price = prepared.price
            tx.fee = prepared.fee
            tx.cashAmount = prepared.cashAmount
            tx.splitRatio = prepared.splitRatio
            tx.note = prepared.note
            tx.currency = prepared.currency
            do {
                try context.save()
                PortfolioEngine.rebuildPositions(
                    transactions: try context.fetch(FetchDescriptor<TransactionRecord>()),
                    context: context
                )
                showSavedAlert = true
            } catch {
                errorMessage = "保存失败：\(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func deleteCurrent() {
        guard let tx = transaction else { return }
        context.delete(tx)
        do {
            try context.save()
            PortfolioEngine.rebuildPositions(
                transactions: try context.fetch(FetchDescriptor<TransactionRecord>()),
                context: context
            )
            dismiss()
        } catch {
            AppLog.error("delete detail failed: \(error.localizedDescription)")
        }
    }
}

struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme
    @Query private var instruments: [Instrument]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]
    @Query private var corporateActions: [CorporateActionRecord]
    @Query(sort: \TransactionRecord.tradeDate, order: .reverse) private var allTransactions: [TransactionRecord]

    var useMockMarketData: Bool = false
    var prefill: TransactionPrefill? = nil
    /// 导航标题；持仓详情「修改资料」传「修改资料」
    var presentationTitle: String = "录入交易"
    /// 打开后默认展开手动标的区（市场/类型/代码/名称/币种可改）
    var preferManualInstrumentEntry: Bool = false
    /// 非空时为「修改资料」：可只改标的；改代码/市场会迁移关联；交易区有内容时一并录入
    var editingInstrumentID: String? = nil
    var onInstrumentSaved: ((String) -> Void)? = nil

    @State private var market: Market = .cnA
    @State private var assetType: InstrumentType = .stock
    @State private var symbol: String = ""
    @State private var name: String = ""
    @State private var currency: String = Market.cnA.defaultCurrency
    @State private var filledFromSearch = false
    @State private var showSearch = false

    @State private var kind: TransactionKind = .buy
    @State private var tradeDate: Date = .now
    @State private var quantity: String = ""
    @State private var sharesOnRecordText: String = ""
    @State private var price: String = ""
    @State private var fee: String = ""
    @State private var cashAmount: String = ""
    @State private var splitRatio: String = "1"
    @State private var note: String = ""
    @State private var errorMessage: String?
    @State private var showManualEntry = true
    @State private var showErrorAlert = false
    @State private var showSuccessAlert = false
    @State private var successMessage = "交易已写入本地，持仓已更新。可在「资产」查看。"
    @State private var didApplyPrefill = false
    @State private var autoFilledName = false
    @State private var lastAutoName = ""
    @State private var isResolvingName = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var autoDividendQuantity = true
    @State private var autoDividendPrice = true
    @State private var autoDividendTotal = true
    @State private var isWritingDividendField = false
    @State private var dividendHint: String?
    /// 「修改资料」时绑定的已有交易（保存时就地更新，避免重复插入）
    @State private var editingTransactionID: UUID?
    @State private var loadedTradeFingerprint: String?
    @State private var didLoadEditingProfile = false

    private var isEditingProfile: Bool { editingInstrumentID != nil }

    /// 从持仓详情买入 / 卖出 / 分红进入：标的已锁定
    private var isHoldingTradeEntry: Bool {
        guard let prefill,
              prefill.filledFromSearch,
              !prefill.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              editingInstrumentID == nil
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标的") {
                    if isHoldingTradeEntry {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(market.regionFlag)
                                Text(name.isEmpty ? symbol : name)
                                    .font(.headline)
                            }
                            Text(symbol)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(market.displayName)
                                Text(currency)
                                Text(assetType.displayName)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Button {
                            showSearch = true
                        } label: {
                            Label("搜索标的", systemImage: "magnifyingglass")
                        }

                        if filledFromSearch && !symbol.isEmpty && !showManualEntry {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(market.regionFlag)
                                    Text(name.isEmpty ? symbol : name)
                                        .font(.headline)
                                }
                                Text(symbol)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(market.displayName)
                                    Text(currency)
                                    Text(assetType.displayName)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        Toggle("手动输入 / 修改名称", isOn: $showManualEntry)

                        if showManualEntry || !filledFromSearch {
                            Picker("市场", selection: $market) {
                                ForEach(Market.allCases) { item in
                                    Text("\(item.regionFlag) \(item.displayName)").tag(item)
                                }
                            }
                            Picker("类型", selection: $assetType) {
                                ForEach(InstrumentType.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("代码")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                SymbolTextField(placeholder: symbolPlaceholder, text: $symbol)
                                    .frame(height: 40)

                                HStack {
                                    Text("名称")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if isResolvingName {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else if autoFilledName && !name.isEmpty {
                                        Text("已自动匹配")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                CJKTextField(placeholder: "输入代码后自动显示，也可手改", text: $name)
                                    .frame(height: 40)
                                    .id("instrument-name-field")
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                            Picker("币种", selection: $currency) {
                                Text("CNY").tag("CNY")
                                Text("HKD").tag("HKD")
                                Text("USD").tag("USD")
                            }
                        }
                    }
                }

                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(TransactionKind.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    DatePicker(
                        kind.isDividendEvent || kind == .bonusShare ? "权益登记日" : "日期",
                        selection: $tradeDate,
                        displayedComponents: .date
                    )

                    switch kind {
                    case .buy, .sell:
                        LabeledContent("数量") {
                            DecimalTextField(placeholder: "如 100 或 1.5", text: $quantity)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("单价") {
                            DecimalTextField(placeholder: "如 1680.50", text: $price)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("手续费") {
                            DecimalTextField(placeholder: "可空，支持小数", text: $fee)
                                .frame(minHeight: 36)
                        }
                    case .dividend:
                        LabeledContent("登记日持仓") {
                            DecimalTextField(placeholder: "按登记日回放", text: $sharesOnRecordText)
                                .frame(minHeight: 36)
                        }
                        LabeledContent(market == .cnFund ? "每份分红" : "每股分红") {
                            DecimalTextField(placeholder: "按除息方案估算", text: $price)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("分红总额") {
                            DecimalTextField(placeholder: "登记日持仓×每股/份", text: $cashAmount)
                                .frame(minHeight: 36)
                        }
                        Text("按除息方案估算，非实时价；持仓取权益登记日，非当前持仓")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let dividendHint {
                            Text(dividendHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    case .dividendReinvest:
                        LabeledContent("登记日持仓") {
                            DecimalTextField(placeholder: "按登记日回放", text: $sharesOnRecordText)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("每份分红") {
                            DecimalTextField(placeholder: "元/份", text: $price)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("再投资份额") {
                            DecimalTextField(placeholder: "实际到账份额", text: $quantity)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("分红等价金额") {
                            DecimalTextField(placeholder: "登记日持仓×每份", text: $cashAmount)
                                .frame(minHeight: 36)
                        }
                        if let dividendHint {
                            Text(dividendHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    case .bonusShare:
                        LabeledContent("登记日持仓") {
                            DecimalTextField(placeholder: "可选，审计用", text: $sharesOnRecordText)
                                .frame(minHeight: 36)
                        }
                        LabeledContent("送股数量") {
                            DecimalTextField(placeholder: "实际获赠股数", text: $quantity)
                                .frame(minHeight: 36)
                        }
                    case .fee:
                        LabeledContent("手续费") {
                            DecimalTextField(placeholder: "金额", text: $cashAmount)
                                .frame(minHeight: 36)
                        }
                    case .split:
                        LabeledContent("拆合股比例") {
                            DecimalTextField(placeholder: "如 2 = 1拆2", text: $splitRatio)
                                .frame(minHeight: 36)
                        }
                    }

                    LabeledContent("备注") {
                        CJKTextField(placeholder: "可选", text: $note)
                            .frame(minHeight: 36)
                    }
                } header: {
                    Text("交易")
                } footer: {
                    if kind == .dividend {
                        Text("分红按权益登记日持仓计算。登记日后卖出不影响该次分红；登记日前卖出则无分红。总额 = 登记日持仓 × 每股（份）分红。")
                    } else if kind == .dividendReinvest {
                        Text("红利再投资：分红等价金额计入累计分红与已实现收益，同时增加基金份额。登记日持仓按流水回放，不用当前持仓倒推。")
                    } else if kind == .bonusShare {
                        Text("送股增加持仓数量并摊薄成本，不影响累计现金分红。")
                    } else {
                        Text("单价请用键盘小数点输入。名称支持拼音中文输入。")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(theme.destructive)
                            .accessibilityIdentifier("saveErrorLabel")
                    }
                }

                if !isHoldingTradeEntry {
                    Section {
                        Button("保存交易") {
                            save()
                        }
                        .accessibilityIdentifier("saveTransactionButton")
                    }
                }
            }
            .wkPageChrome()
            .navigationTitle(presentationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .accessibilityIdentifier("saveToolbarButton")
                }
            }
            .sheet(isPresented: $showSearch) {
                InstrumentSearchView(onSelect: { hit in
                    applySearchHit(hit)
                }, useMock: useMockMarketData)
            }
            .alert("无法保存", isPresented: $showErrorAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请检查并补全遗漏项")
            }
            .alert("保存成功", isPresented: $showSuccessAlert) {
                Button("好") { dismiss() }
            } message: {
                Text(successMessage)
            }
            .onAppear {
                if editingInstrumentID != nil {
                    loadEditingProfileIfNeeded()
                } else {
                    applyPrefillIfNeeded()
                }
                refreshDividendDefaults()
            }
            .onChange(of: instruments.count) { _, _ in
                if editingInstrumentID != nil { loadEditingProfileIfNeeded() }
            }
            .onChange(of: allTransactions.count) { _, _ in
                if editingInstrumentID != nil { loadEditingProfileIfNeeded() }
            }
            .onChange(of: market) { _, newValue in
                if !filledFromSearch || showManualEntry {
                    currency = newValue.defaultCurrency
                    if newValue == .cnFund {
                        assetType = .fund
                    } else if assetType == .fund {
                        assetType = .stock
                    }
                }
                scheduleNameResolve(for: symbol)
                refreshDividendDefaults()
            }
            .onChange(of: symbol) { _, newValue in
                scheduleNameResolve(for: newValue)
                refreshDividendDefaults()
            }
            .onChange(of: kind) { _, newValue in
                if newValue.isDividendEvent {
                    autoDividendQuantity = true
                    autoDividendPrice = true
                    autoDividendTotal = true
                    refreshDividendDefaults()
                } else if newValue == .bonusShare {
                    autoDividendQuantity = true
                    refreshDividendDefaults()
                } else {
                    dividendHint = nil
                }
            }
            .onChange(of: tradeDate) { _, _ in
                if kind.isDividendEvent || kind == .bonusShare {
                    autoDividendQuantity = true
                    refreshDividendDefaults()
                }
            }
            .onChange(of: sharesOnRecordText) { _, _ in
                if kind.isDividendEvent {
                    if !isWritingDividendField { autoDividendQuantity = false }
                    recalculateDividendTotal()
                }
            }
            .onChange(of: price) { _, _ in
                if kind.isDividendEvent {
                    if !isWritingDividendField { autoDividendPrice = false }
                    recalculateDividendTotal()
                }
            }
            .onChange(of: cashAmount) { _, _ in
                if kind.isDividendEvent, !isWritingDividendField {
                    autoDividendTotal = false
                }
            }
            .onChange(of: name) { _, newValue in
                if autoFilledName, newValue != lastAutoName {
                    autoFilledName = false
                }
            }
            .onDisappear {
                resolveTask?.cancel()
            }
        }
    }

    private var currentInstrumentID: String {
        "\(market.rawValue):\(symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())"
    }

    private func refreshDividendDefaults() {
        guard kind.isDividendEvent || kind == .bonusShare else {
            dividendHint = nil
            return
        }
        let id = currentInstrumentID
        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dividendHint = "选择标的后：按权益登记日回放持仓 → 本地/远程除息方案 → 手填"
            return
        }

        let recordQty = PortfolioEngine.quantityAsOf(
            transactions: Array(allTransactions),
            instrumentID: id,
            asOf: tradeDate
        )

        if autoDividendQuantity {
            isWritingDividendField = true
            sharesOnRecordText = recordQty > 0
                ? DecimalMath.plainString(recordQty, fractionDigits: 4)
                : ""
            if kind == .dividend {
                quantity = sharesOnRecordText
            }
            isWritingDividendField = false
        }

        var hintParts: [String] = []
        if recordQty > 0 {
            hintParts.append("登记日持仓 \(MoneyFormat.quantity(recordQty))")
        } else {
            hintParts.append("登记日持仓 0（该次无分红）")
        }

        if kind == .bonusShare {
            dividendHint = hintParts.joined(separator: " · ")
            return
        }

        if autoDividendPrice {
            if let local = latestLocalCorporateDividend(instrumentID: id) {
                applyDividendPrice(
                    local.perShare,
                    hint: "来源：本地分红记录 · 登记 \(MoneyFormat.shortDate(local.recordDate)) · 除息 \(MoneyFormat.shortDate(local.exDate))",
                    into: &hintParts
                )
                // 若本地有登记日，自动切到该日并重算持仓
                if autoDividendQuantity,
                   Calendar.current.startOfDay(for: local.recordDate) != Calendar.current.startOfDay(for: tradeDate) {
                    tradeDate = local.recordDate
                    let qty = PortfolioEngine.quantityAsOf(
                        transactions: Array(allTransactions),
                        instrumentID: id,
                        asOf: local.recordDate
                    )
                    isWritingDividendField = true
                    sharesOnRecordText = qty > 0 ? DecimalMath.plainString(qty, fractionDigits: 4) : ""
                    if kind == .dividend { quantity = sharesOnRecordText }
                    isWritingDividendField = false
                    hintParts.removeAll { $0.hasPrefix("登记日持仓") }
                    hintParts.insert(
                        qty > 0 ? "登记日持仓 \(MoneyFormat.quantity(qty))" : "登记日持仓 0（该次无分红）",
                        at: 0
                    )
                }
            } else {
                hintParts.append("正在查询除息方案…")
                dividendHint = hintParts.joined(separator: " · ")
                Task { await resolveRemoteDividend(instrumentID: id) }
                return
            }
        }

        dividendHint = hintParts.isEmpty ? nil : hintParts.joined(separator: " · ")
        recalculateDividendTotal()
    }

    private func latestLocalCorporateDividend(instrumentID: String) -> (perShare: Decimal, exDate: Date, recordDate: Date)? {
        let actions = corporateActions
            .filter { $0.instrumentID == instrumentID && $0.kind == .dividend && $0.value > 0 }
            .sorted { $0.exDate > $1.exDate }
        guard let latest = actions.first else { return nil }
        return (Decimal(latest.value), latest.exDate, latest.effectiveRecordDate)
    }

    private func latestLocalTransactionDividend(instrumentID: String) -> Decimal? {
        allTransactions.first(where: {
            $0.instrumentID == instrumentID && $0.kind.isDividendEvent && $0.price > 0
        })?.price
    }

    private func applyDividendPrice(_ perShare: Decimal, hint: String, into hintParts: inout [String]) {
        isWritingDividendField = true
        price = DecimalMath.plainString(perShare, fractionDigits: 4)
        isWritingDividendField = false
        hintParts.append(hint)
    }

    private func recalculateDividendTotal() {
        guard kind.isDividendEvent, autoDividendTotal else { return }
        let shares = DecimalMath.parse(sharesOnRecordText) ?? DecimalMath.parse(quantity) ?? 0
        guard let p = DecimalMath.parse(price), shares > 0, p >= 0 else { return }
        isWritingDividendField = true
        cashAmount = DecimalMath.plainString(shares * p, fractionDigits: 4)
        isWritingDividendField = false
    }

    @MainActor
    private func resolveRemoteDividend(instrumentID: String) async {
        guard kind.isDividendEvent, autoDividendPrice else { return }
        let instrument = Instrument(
            symbol: symbol,
            name: name.isEmpty ? symbol : name,
            market: market,
            type: assetType,
            currency: currency
        )
        let dto = InstrumentDTO(instrument)

        var remote: [RemoteCorporateAction] = []
        do {
            switch market {
            case .cnA, .cnFund:
                if useMockMarketData {
                    remote = MockMarketData.sampleDividends(for: dto)
                } else {
                    remote = try await EastMoneyProvider().fetchCorporateActions(for: dto)
                }
            case .hk, .us:
                if useMockMarketData {
                    remote = MockMarketData.sampleDividends(for: dto)
                } else {
                    remote = try await YahooFinanceProvider().fetchCorporateActions(for: dto)
                }
            }
        } catch {
            AppLog.debug("dividend remote fail: \(error.localizedDescription)")
        }

        guard kind.isDividendEvent, autoDividendPrice else { return }

        var hintParts: [String] = []

        if let div = remote.filter({ $0.kind == .dividend }).max(by: { $0.exDate < $1.exDate }) {
            upsertLocalCorporateAction(div)
            let recordDate = div.effectiveRecordDate
            if autoDividendQuantity {
                tradeDate = recordDate
                let qty = PortfolioEngine.quantityAsOf(
                    transactions: Array(allTransactions),
                    instrumentID: instrumentID,
                    asOf: recordDate
                )
                isWritingDividendField = true
                sharesOnRecordText = qty > 0 ? DecimalMath.plainString(qty, fractionDigits: 4) : ""
                if kind == .dividend { quantity = sharesOnRecordText }
                isWritingDividendField = false
                hintParts.append(
                    qty > 0 ? "登记日持仓 \(MoneyFormat.quantity(qty))" : "登记日持仓 0（该次无分红）"
                )
            } else {
                let qty = PortfolioEngine.quantityAsOf(
                    transactions: Array(allTransactions),
                    instrumentID: instrumentID,
                    asOf: tradeDate
                )
                hintParts.append(
                    qty > 0 ? "登记日持仓 \(MoneyFormat.quantity(qty))" : "登记日持仓 0（该次无分红）"
                )
            }
            applyDividendPrice(
                div.value,
                hint: "来源：远程除息方案 · 登记 \(MoneyFormat.shortDate(div.effectiveRecordDate)) · 除息 \(MoneyFormat.shortDate(div.exDate))",
                into: &hintParts
            )
        } else if let hist = latestLocalTransactionDividend(instrumentID: instrumentID) {
            let qty = PortfolioEngine.quantityAsOf(
                transactions: Array(allTransactions),
                instrumentID: instrumentID,
                asOf: tradeDate
            )
            hintParts.append(
                qty > 0 ? "登记日持仓 \(MoneyFormat.quantity(qty))" : "登记日持仓 0（该次无分红）"
            )
            applyDividendPrice(hist, hint: "来源：历史分红流水（可手改）", into: &hintParts)
        } else {
            let qty = PortfolioEngine.quantityAsOf(
                transactions: Array(allTransactions),
                instrumentID: instrumentID,
                asOf: tradeDate
            )
            hintParts.append(
                qty > 0 ? "登记日持仓 \(MoneyFormat.quantity(qty))" : "登记日持仓 0（该次无分红）"
            )
            hintParts.append("未找到除息方案，请手填每股/份分红")
        }

        dividendHint = hintParts.joined(separator: " · ")
        recalculateDividendTotal()
    }

    private func upsertLocalCorporateAction(_ action: RemoteCorporateAction) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dayKey = formatter.string(from: Calendar.current.startOfDay(for: action.exDate))
        let id = "\(action.instrumentID):\(action.kind.rawValue):\(dayKey)"
        let descriptor = FetchDescriptor<CorporateActionRecord>(predicate: #Predicate { $0.id == id })
        if (try? context.fetch(descriptor).first) != nil { return }
        context.insert(
            CorporateActionRecord(
                instrumentID: action.instrumentID,
                kind: action.kind,
                exDate: action.exDate,
                value: DecimalMath.double(action.value),
                currency: action.currency,
                source: action.source,
                recordDate: action.effectiveRecordDate,
                settlement: action.settlement
            )
        )
        try? context.save()
    }

    private var symbolPlaceholder: String {
        switch market {
        case .cnA: return "如 600519"
        case .hk: return "如 0700"
        case .us: return "如 AAPL"
        case .cnFund: return "如 110022"
        }
    }

    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill, let prefill else { return }
        didApplyPrefill = true
        market = prefill.market
        assetType = prefill.assetType
        symbol = prefill.symbol
        name = prefill.name
        currency = prefill.currency
        kind = prefill.kind
        filledFromSearch = prefill.filledFromSearch
        showManualEntry = preferManualInstrumentEntry || !prefill.filledFromSearch
        if prefill.filledFromSearch && !prefill.name.isEmpty {
            lastAutoName = prefill.name
            autoFilledName = true
        }
        if !prefill.quantityText.isEmpty {
            isWritingDividendField = true
            quantity = prefill.quantityText
            isWritingDividendField = false
            autoDividendQuantity = true
        }
        if !prefill.priceText.isEmpty {
            isWritingDividendField = true
            price = prefill.priceText
            isWritingDividendField = false
            autoDividendPrice = true
        }
        if !prefill.symbol.isEmpty, prefill.name.isEmpty {
            scheduleNameResolve(for: prefill.symbol)
        }
    }

    /// 「修改资料」：载入当前标的 + 最近一笔交易（无交易则用持仓数量/成本），均可改
    private func loadEditingProfileIfNeeded() {
        guard !didLoadEditingProfile, let id = editingInstrumentID else { return }

        let instrument = instruments.first(where: { $0.id == id })
        guard instrument != nil || prefill != nil else { return }

        didLoadEditingProfile = true
        didApplyPrefill = true
        showManualEntry = true

        if let instrument {
            market = instrument.market
            assetType = instrument.type
            symbol = instrument.symbol
            name = instrument.name
            currency = instrument.currency
            filledFromSearch = !instrument.symbol.isEmpty
            if !instrument.name.isEmpty {
                lastAutoName = instrument.name
                autoFilledName = true
            }
        } else if let prefill {
            market = prefill.market
            assetType = prefill.assetType
            symbol = prefill.symbol
            name = prefill.name
            currency = prefill.currency
            filledFromSearch = prefill.filledFromSearch
            if !prefill.name.isEmpty {
                lastAutoName = prefill.name
                autoFilledName = true
            }
        }

        isWritingDividendField = true
        if let tx = allTransactions.first(where: { $0.instrumentID == id }) {
            editingTransactionID = tx.id
            kind = tx.kind
            tradeDate = tx.recordDate ?? tx.tradeDate
            applyLoadedTradeNumbers(
                quantity: tx.quantity,
                sharesOnRecord: tx.sharesOnRecord,
                price: tx.price,
                fee: tx.fee,
                cashAmount: tx.cashAmount,
                splitRatio: tx.splitRatio
            )
            note = tx.note
            if !tx.currency.isEmpty {
                currency = tx.currency
            }
        } else if let position = positions.first(where: { $0.instrumentID == id }), position.quantity > 0 {
            editingTransactionID = nil
            kind = .buy
            applyLoadedTradeNumbers(
                quantity: position.quantity,
                sharesOnRecord: 0,
                price: position.averageCost,
                fee: 0,
                cashAmount: 0,
                splitRatio: 1
            )
            note = ""
        }
        isWritingDividendField = false
        loadedTradeFingerprint = tradeFingerprint()
    }

    private func applyLoadedTradeNumbers(
        quantity qty: Decimal,
        sharesOnRecord: Decimal,
        price px: Decimal,
        fee feeValue: Decimal,
        cashAmount cash: Decimal,
        splitRatio ratio: Decimal
    ) {
        quantity = qty > 0 ? DecimalMath.plainString(qty, fractionDigits: 4) : ""
        sharesOnRecordText = sharesOnRecord > 0 ? DecimalMath.plainString(sharesOnRecord, fractionDigits: 4) : ""
        price = px > 0 ? DecimalMath.plainString(px, fractionDigits: 4) : ""
        fee = feeValue > 0 ? DecimalMath.plainString(feeValue, fractionDigits: 4) : ""
        cashAmount = cash > 0 ? DecimalMath.plainString(cash, fractionDigits: 4) : ""
        splitRatio = ratio > 0 ? DecimalMath.plainString(ratio, fractionDigits: 6) : "1"
    }

    private func tradeFingerprint() -> String {
        [
            kind.rawValue,
            String(tradeDate.timeIntervalSince1970),
            quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            sharesOnRecordText.trimmingCharacters(in: .whitespacesAndNewlines),
            price.trimmingCharacters(in: .whitespacesAndNewlines),
            fee.trimmingCharacters(in: .whitespacesAndNewlines),
            cashAmount.trimmingCharacters(in: .whitespacesAndNewlines),
            splitRatio.trimmingCharacters(in: .whitespacesAndNewlines),
            note.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "|")
    }

    private var tradeUnchangedFromLoad: Bool {
        guard let loadedTradeFingerprint else { return false }
        return tradeFingerprint() == loadedTradeFingerprint
    }

    /// 修改资料时：交易区未填则可只保存标的
    private var tradeFieldsEffectivelyEmpty: Bool {
        let qty = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let shares = sharesOnRecordText.trimmingCharacters(in: .whitespacesAndNewlines)
        let px = price.trimmingCharacters(in: .whitespacesAndNewlines)
        let feeText = fee.trimmingCharacters(in: .whitespacesAndNewlines)
        let cash = cashAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratio = splitRatio.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .buy, .sell:
            return qty.isEmpty && px.isEmpty && feeText.isEmpty
        case .dividend, .dividendReinvest:
            return qty.isEmpty && shares.isEmpty && px.isEmpty && cash.isEmpty
        case .bonusShare:
            return qty.isEmpty && shares.isEmpty
        case .fee:
            return cash.isEmpty && feeText.isEmpty
        case .split:
            return ratio.isEmpty || ratio == "1"
        }
    }

    private func failSave(_ message: String) {
        errorMessage = message
        showErrorAlert = true
        AppLog.error("save failed: \(message)")
    }

    /// 收集当前交易类型下尚未填写的必填项，用于保存前提醒
    private func missingRequiredFields() -> [String] {
        var missing: [String] = []
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSymbol.isEmpty {
            missing.append("代码")
        }
        let qty = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let shares = sharesOnRecordText.trimmingCharacters(in: .whitespacesAndNewlines)
        let px = price.trimmingCharacters(in: .whitespacesAndNewlines)
        let feeText = fee.trimmingCharacters(in: .whitespacesAndNewlines)
        let cash = cashAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratio = splitRatio.trimmingCharacters(in: .whitespacesAndNewlines)

        func positiveDecimal(_ text: String) -> Bool {
            guard let v = DecimalMath.parse(text), v > 0 else { return false }
            return true
        }

        switch kind {
        case .buy, .sell:
            if !positiveDecimal(qty) { missing.append("数量") }
            if !positiveDecimal(px) { missing.append("单价") }
        case .dividend:
            let hasCash = positiveDecimal(cash)
            let hasShares = positiveDecimal(shares) || positiveDecimal(qty)
            let hasPx = positiveDecimal(px)
            if !hasCash && !(hasShares && hasPx) {
                if !hasCash { missing.append("分红总额") }
                if !hasShares { missing.append("登记日持仓") }
                if !hasPx { missing.append("每股/份分红") }
            }
        case .dividendReinvest:
            let hasQty = positiveDecimal(qty)
            let hasCash = positiveDecimal(cash)
            let hasShares = positiveDecimal(shares) || positiveDecimal(qty)
            let hasPx = positiveDecimal(px)
            if !hasQty && !hasCash && !(hasShares && hasPx) {
                if !hasQty { missing.append("再投资份额") }
                if !hasCash { missing.append("分红金额") }
                if !hasPx { missing.append("净值") }
            }
        case .bonusShare:
            if !positiveDecimal(qty) { missing.append("送股数量") }
        case .fee:
            if !positiveDecimal(cash) && !positiveDecimal(feeText) {
                missing.append("手续费金额")
            }
        case .split:
            if ratio.isEmpty || !positiveDecimal(ratio) {
                missing.append("拆合股比例")
            }
        }
        return missing
    }

    /// 更新或迁移标的资料，返回新 instrumentID
    private func saveInstrumentProfile() -> String? {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSymbol.isEmpty else {
            failSave("请填写代码")
            return nil
        }
        guard !trimmedName.isEmpty else {
            failSave("请填写名称")
            return nil
        }
        guard let oldID = editingInstrumentID else { return nil }
        guard let instrument = instruments.first(where: { $0.id == oldID }) else {
            failSave("标的不存在")
            return nil
        }

        let normalizedSymbol = InstrumentSearchService.normalizeSymbol(trimmedSymbol, market: market)
        let newID = "\(market.rawValue):\(normalizedSymbol.uppercased())"
        let resolvedType: InstrumentType = market == .cnFund ? .fund : assetType

        if newID != oldID, instruments.contains(where: { $0.id == newID }) {
            failSave("该市场下已存在相同代码的标的")
            return nil
        }

        do {
            if newID == oldID {
                instrument.name = trimmedName
                instrument.type = resolvedType
                instrument.currency = currency
                instrument.symbol = normalizedSymbol
                instrument.market = market
            } else {
                let created = Instrument(
                    symbol: normalizedSymbol,
                    name: trimmedName,
                    market: market,
                    type: resolvedType,
                    currency: currency
                )
                context.insert(created)
                allTransactions.filter { $0.instrumentID == oldID }.forEach { $0.instrumentID = newID }
                positions.filter { $0.instrumentID == oldID }.forEach { $0.instrumentID = newID }
                quotes.filter { $0.instrumentID == oldID }.forEach { $0.instrumentID = newID }
                corporateActions.filter { $0.instrumentID == oldID }.forEach { $0.instrumentID = newID }
                context.delete(instrument)
            }
            try context.save()
            PortfolioEngine.rebuildPositions(
                transactions: try context.fetch(FetchDescriptor<TransactionRecord>()),
                context: context
            )
            onInstrumentSaved?(newID)
            return newID
        } catch {
            failSave("保存失败，请重试")
            AppLog.error("instrument profile save failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func updateExistingTransaction(_ prepared: TransactionSaveService.Prepared, transactionID: UUID) throws {
        guard let tx = allTransactions.first(where: { $0.id == transactionID }) else {
            try TransactionSaveService.persist(prepared, context: context)
            return
        }
        tx.instrumentID = prepared.instrumentID
        tx.kind = prepared.kind
        tx.tradeDate = prepared.tradeDate
        tx.recordDate = prepared.recordDate
        tx.quantity = prepared.quantity
        tx.sharesOnRecord = prepared.sharesOnRecord
        tx.price = prepared.price
        tx.fee = prepared.fee
        tx.cashAmount = prepared.cashAmount
        tx.splitRatio = prepared.splitRatio
        tx.note = prepared.note
        tx.currency = prepared.currency
        try context.save()
        PortfolioEngine.rebuildPositions(
            transactions: try context.fetch(FetchDescriptor<TransactionRecord>()),
            context: context
        )
    }

    private func applySearchHit(_ hit: InstrumentSearchHit) {
        market = hit.market
        symbol = hit.symbol
        lastAutoName = hit.name
        name = hit.name
        currency = hit.currency
        assetType = hit.assetType
        filledFromSearch = true
        showManualEntry = false
        autoFilledName = true
        errorMessage = nil
        AppLog.debug("search selected market=\(hit.market.rawValue)")
        if kind.isDividendEvent {
            autoDividendQuantity = true
            autoDividendPrice = true
            autoDividendTotal = true
            refreshDividendDefaults()
        }
    }

    private func scheduleNameResolve(for raw: String) {
        resolveTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let minLen = market == .us ? 1 : 2
        guard trimmed.count >= minLen else {
            isResolvingName = false
            return
        }
        // 已从搜索选定且未开手动时，不必反复查
        if filledFromSearch && !showManualEntry { return }

        isResolvingName = true
        let marketSnapshot = market
        let useMock = useMockMarketData
        resolveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            do {
                let hits = try await InstrumentSearchService(useMock: useMock).search(query: trimmed)
                guard !Task.isCancelled else { return }
                let normalized = InstrumentSearchService.normalizeSymbol(trimmed, market: marketSnapshot)
                let exactSameMarket = hits.first {
                    $0.market == marketSnapshot
                        && $0.symbol.caseInsensitiveCompare(normalized) == .orderedSame
                }
                let exactAny = hits.first {
                    $0.symbol.caseInsensitiveCompare(normalized) == .orderedSame
                }
                let hit = exactSameMarket ?? exactAny
                await MainActor.run {
                    isResolvingName = false
                    guard let hit else { return }
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || autoFilledName {
                        lastAutoName = hit.name
                        name = hit.name
                        autoFilledName = true
                    }
                    assetType = hit.assetType
                    if hit.market != marketSnapshot, exactSameMarket == nil, exactAny != nil {
                        market = hit.market
                        currency = hit.currency
                    } else {
                        currency = hit.currency
                    }
                }
            } catch {
                await MainActor.run { isResolvingName = false }
            }
        }
    }

    private func save() {
        AppLog.debug("save tapped kind=\(kind.rawValue) market=\(market.rawValue)")
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // 「修改资料」：交易未改或为空 → 只保存标的
        if isEditingProfile, tradeFieldsEffectivelyEmpty || tradeUnchangedFromLoad {
            guard saveInstrumentProfile() != nil else { return }
            errorMessage = nil
            successMessage = "标的资料已更新。"
            showSuccessAlert = true
            return
        }

        // 「修改资料」且改了交易：先迁移/更新标的，再更新或新增交易
        if isEditingProfile {
            guard saveInstrumentProfile() != nil else { return }
        }

        let missing = missingRequiredFields()
        if !missing.isEmpty {
            failSave("请补全遗漏项：\(missing.joined(separator: "、"))")
            return
        }

        let input = TransactionSaveService.Input(
            market: market,
            assetType: assetType,
            symbol: symbol,
            name: name,
            currency: currency,
            kind: kind,
            tradeDate: tradeDate,
            recordDate: (kind.isDividendEvent || kind == .bonusShare) ? tradeDate : nil,
            quantityText: quantity,
            sharesOnRecordText: sharesOnRecordText,
            priceText: price,
            feeText: fee,
            cashAmountText: cashAmount,
            splitRatioText: splitRatio,
            note: note
        )

        switch TransactionSaveService.prepare(input) {
        case .failure(let error):
            errorMessage = error.localizedDescription
            showErrorAlert = true
            AppLog.error("save validation failed: \(error.localizedDescription)")
        case .success(let prepared):
            do {
                if let txID = editingTransactionID {
                    try updateExistingTransaction(prepared, transactionID: txID)
                } else {
                    try TransactionSaveService.persist(prepared, context: context)
                }
                errorMessage = nil
                successMessage = isEditingProfile
                    ? "资料与交易已保存，持仓已更新。"
                    : "交易已写入本地，持仓已更新。可在「资产」查看。"
                if isEditingProfile {
                    onInstrumentSaved?(prepared.instrumentID)
                }
                showSuccessAlert = true
            } catch {
                errorMessage = TransactionSaveError.persistence(error.localizedDescription).localizedDescription
                showErrorAlert = true
                AppLog.error("save persist failed: \(error.localizedDescription)")
            }
        }
    }
}

extension TransactionRecord: Identifiable {}
