import SwiftUI
import SwiftData

/// 生活记账：生活化分类、增删改、备注；结余计入总资产
struct LifestyleLedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query(sort: \LifestyleEntry.entryDate, order: .reverse) private var entries: [LifestyleEntry]
    @Query private var settingsList: [AppSettings]

    @State private var editor: LifestyleEditorSession?
    @State private var filter: LifestyleFlowKind? = nil
    @State private var pendingDeleteEntryID: UUID?
    @State private var confirmDeleteEntry = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var filtered: [LifestyleEntry] {
        guard let filter else { return entries }
        return entries.filter { $0.flowKind == filter }
    }

    private var incomeTotal: Decimal {
        entries.filter { $0.flowKind == .income }.reduce(0) {
            $0 + $1.amount * settings.rateToCNY(for: $1.currency)
        }
    }

    private var expenseTotal: Decimal {
        entries.filter { $0.flowKind == .expense }.reduce(0) {
            $0 + $1.amount * settings.rateToCNY(for: $1.currency)
        }
    }

    private var net: Decimal { incomeTotal - expenseTotal }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("生活小账本")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.lifestyleOverviewTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("记下购物、旅行、工资日常，结余会计入首页总资产。")
                        .font(.subheadline)
                        .foregroundStyle(theme.lifestyleOverviewSubtitle)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        summaryChip(title: "收入", value: incomeTotal, tone: .income) {
                            editor = .create(.income)
                        }
                        summaryChip(title: "支出", value: expenseTotal, tone: .expense) {
                            editor = .create(.expense)
                        }
                        summaryChip(title: "结余", value: net, tone: .net, action: nil)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(
                    theme.lifestyleOverviewGradient
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(theme.separator.opacity(0.9), lineWidth: 1)
                        )
                )
            }

            Section {
                Picker("筛选", selection: Binding(
                    get: { filter.map { Optional($0) } ?? Optional<LifestyleFlowKind>.none },
                    set: { filter = $0 }
                )) {
                    Text("全部").tag(Optional<LifestyleFlowKind>.none)
                    Text("支出").tag(Optional.some(LifestyleFlowKind.expense))
                    Text("收入").tag(Optional.some(LifestyleFlowKind.income))
                }
                .pickerStyle(.segmented)
                .listRowBackground(theme.cardBackground)
            }

            Section {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "还没有生活账",
                        systemImage: "leaf.fill",
                        description: Text("记下一次咖啡、一次出行，或一笔工资吧。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered, id: \.id) { entry in
                        Button {
                            editor = .edit(entry.id)
                        } label: {
                            LifestyleEntryRow(entry: entry, rateToCNY: settings.rateToCNY(for: entry.currency))
                        }
                        .listRowBackground(theme.cardBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteEntryID = entry.id
                                confirmDeleteEntry = true
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }
                            .tint(.red)
                        }
                    }
                }
            } header: {
                Text("流水")
            }
        }
        .wkPageChrome()
        .navigationTitle("生活记账")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editor = .create(.expense)
                    } label: {
                        Label("记一笔支出", systemImage: "minus.circle")
                    }
                    Button {
                        editor = .create(.income)
                    } label: {
                        Label("记一笔收入", systemImage: "plus.circle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editor) { session in
            LifestyleEntryEditorView(session: session)
        }
        .confirmationDialog("删除这笔生活账？", isPresented: $confirmDeleteEntry, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteEntryID,
                   let entry = entries.first(where: { $0.id == id }) {
                    context.delete(entry)
                    try? context.save()
                }
                pendingDeleteEntryID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteEntryID = nil }
        } message: {
            Text("删除后不可恢复，结余将随之更新。")
        }
    }

    private enum ChipTone { case income, expense, net }

    private func summaryChip(
        title: String,
        value: Decimal,
        tone: ChipTone,
        action: (() -> Void)?
    ) -> some View {
        let color: Color = {
            switch tone {
            case .income: return theme.income
            case .expense: return theme.expense
            case .net: return theme.net
            }
        }()
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(color)
            Text(MoneyFormat.compact(value, sign: tone != .expense))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.lifestyleChipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)

        return Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityHint(tone == .income ? "记一笔收入" : "记一笔支出")
            } else {
                content
            }
        }
    }
}

private struct LifestyleEntryRow: View {
    @Environment(\.wkTheme) private var theme
    let entry: LifestyleEntry
    let rateToCNY: Decimal

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.flowKind == .income
                          ? theme.lifestyleIncomeSoft
                          : theme.lifestyleExpenseSoft)
                    .frame(width: 40, height: 40)
                Image(systemName: entry.category.systemImage)
                    .foregroundStyle(theme.lifestyleAmount(isIncome: entry.flowKind == .income))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.category.displayName)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                HStack(spacing: 6) {
                    Text(MoneyFormat.shortDate(entry.entryDate))
                    if !entry.note.isEmpty {
                        Text("·")
                        Text(entry.note)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            Text((entry.flowKind == .income ? "+" : "−") + MoneyFormat.compact(entry.amount * rateToCNY))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.lifestyleAmount(isIncome: entry.flowKind == .income))
        }
        .padding(.vertical, 2)
    }
}

enum LifestyleEditorSession: Identifiable {
    case create(LifestyleFlowKind)
    case edit(UUID)

    var id: String {
        switch self {
        case .create(let k): return "new-\(k.rawValue)"
        case .edit(let id): return "edit-\(id)"
        }
    }
}

struct LifestyleEntryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wkTheme) private var theme

    let session: LifestyleEditorSession

    @State private var flowKind: LifestyleFlowKind = .expense
    @State private var category: LifestyleCategory = .dining
    @State private var amountText = ""
    @State private var currency = "CNY"
    @State private var entryDate = Date()
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var categories: [LifestyleCategory] {
        flowKind == .income ? LifestyleCategory.incomeCases : LifestyleCategory.expenseCases
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $flowKind) {
                        ForEach(LifestyleFlowKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: flowKind) { _, newValue in
                        category = newValue == .income ? .salary : .dining
                    }
                }

                Section("生活场景") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                        ForEach(categories) { item in
                            Button {
                                category = item
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: item.systemImage)
                                        .font(.title3)
                                    Text(item.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(category == item ? theme.onAccent : theme.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(category == item
                                              ? theme.lifestyleAmount(isIncome: flowKind == .income)
                                              : theme.secondaryCardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("金额") {
                    LabeledContent("金额") {
                        DecimalTextField(placeholder: "如 58.5", text: $amountText)
                            .frame(height: 36)
                    }
                    Picker("币种", selection: $currency) {
                        Text("CNY").tag("CNY")
                        Text("USD").tag("USD")
                        Text("HKD").tag("HKD")
                    }
                    DatePicker("日期", selection: $entryDate, displayedComponents: .date)
                }

                Section("备注") {
                    CJKTextField(placeholder: "写点什么，如周末市集", text: $note)
                        .frame(height: 40)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(theme.destructive) }
                }
            }
            .wkPageChrome()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear { loadIfNeeded() }
        }
    }

    private var title: String {
        switch session {
        case .create(let kind): return kind == .income ? "记一笔收入" : "记一笔支出"
        case .edit: return "改一笔账"
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        switch session {
        case .create(let kind):
            flowKind = kind
            category = kind == .income ? .salary : .dining
        case .edit(let id):
            let all = (try? context.fetch(FetchDescriptor<LifestyleEntry>())) ?? []
            guard let item = all.first(where: { $0.id == id }) else { return }
            flowKind = item.flowKind
            category = item.category
            amountText = "\(item.amount)"
            currency = item.currency
            entryDate = item.entryDate
            note = item.note
        }
    }

    private func save() {
        guard let amount = DecimalMath.parse(amountText), amount > 0 else {
            errorMessage = "请填写有效金额"
            return
        }
        // 分类与收支类型对齐
        let resolvedCategory: LifestyleCategory = {
            if category.flowKind == flowKind { return category }
            return flowKind == .income ? .otherIncome : .otherExpense
        }()

        do {
            if case .edit(let id) = session,
               let item = ((try? context.fetch(FetchDescriptor<LifestyleEntry>())) ?? []).first(where: { $0.id == id }) {
                item.flowKind = flowKind
                item.category = resolvedCategory
                item.amount = amount
                item.currency = currency
                item.entryDate = entryDate
                item.note = note
                item.updatedAt = .now
            } else {
                context.insert(
                    LifestyleEntry(
                        flowKind: flowKind,
                        category: resolvedCategory,
                        amount: amount,
                        currency: currency,
                        entryDate: entryDate,
                        note: note
                    )
                )
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}
