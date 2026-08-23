import SwiftUI

struct InstrumentSearchView: View {
    var onSelect: (InstrumentSearchHit) -> Void
    var useMock: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [InstrumentSearchHit] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        CJKTextField(placeholder: "代码或名称，如 600519 / 茅台 / AAPL", text: $query)
                            .frame(minHeight: 36)
                        Button("搜索") {
                            Task { await runSearch(immediate: true) }
                        }
                    }
                    if useMock {
                        Text("当前为 Mock 搜索（本地数据）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if isSearching {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在搜索…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                        Button("重试") {
                            Task { await runSearch(immediate: true) }
                        }
                    }
                } else if didSearch && results.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "未找到匹配标的",
                            systemImage: "magnifyingglass",
                            description: Text("请换个代码或名称重试。也可关闭后手动选择市场并输入代码。")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else if !results.isEmpty {
                    Section("搜索结果（\(results.count)）") {
                        ForEach(results) { hit in
                            Button {
                                onSelect(hit)
                                dismiss()
                            } label: {
                                SearchResultRow(hit: hit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Section {
                        Text("支持按代码或名称搜索 A股、港股、美股与基金。市场信息来自行情源，不会仅凭代码猜测。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("搜索标的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("搜索") {
                        Task { await runSearch(immediate: true) }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
            }
            .onChange(of: query) { _, _ in
                Task { await runSearch(immediate: false) }
            }
        }
    }

    @MainActor
    private func runSearch(immediate: Bool) async {
        searchTask?.cancel()
        let current = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            results = []
            didSearch = false
            errorMessage = nil
            isSearching = false
            return
        }

        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }

            isSearching = true
            errorMessage = nil
            defer { isSearching = false }

            let service = InstrumentSearchService(useMock: useMock)
            do {
                let hits = try await service.search(query: current)
                guard !Task.isCancelled else { return }
                results = hits
                didSearch = true
                AppLog.debug("search UI success count=\(hits.count) mock=\(useMock)")
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                didSearch = true
                errorMessage = error.localizedDescription
                AppLog.error("search UI failed: \(error.localizedDescription)")
            }
        }
    }
}

private struct SearchResultRow: View {
    let hit: InstrumentSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hit.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(hit.symbol)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                chip(hit.market.displayName)
                chip(hit.currency)
                chip(hit.assetType.displayName)
                if !hit.securityTypeName.isEmpty {
                    Text(hit.securityTypeName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}
