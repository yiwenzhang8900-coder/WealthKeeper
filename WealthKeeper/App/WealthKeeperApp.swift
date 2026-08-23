import SwiftUI
import SwiftData

@main
struct WealthKeeperApp: App {
    private let container: ModelContainer
    private let storeRecoveryMessage: String?

    init() {
        let result = Self.makeContainer()
        self.container = result.container
        self.storeRecoveryMessage = result.recoveryMessage
        if let recoveryMessage = result.recoveryMessage {
            AppLog.error(recoveryMessage)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootThemeHost {
                ContentView()
                    .overlay(alignment: .top) {
                        if let storeRecoveryMessage {
                            Text(storeRecoveryMessage)
                                .font(.caption2)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.9))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .modelContainer(container)
    }

    /// 升级 schema 时递增，避免旧库迁移失败卡死白屏
    private static let storeFileName = "WealthKeeper_v11.store"

    private static func makeContainer() -> (container: ModelContainer, recoveryMessage: String?) {
        let schema = Schema([
            Instrument.self,
            TransactionRecord.self,
            Position.self,
            CorporateActionRecord.self,
            CachedQuote.self,
            AppSettings.self,
            BankDepositAccount.self,
            FXSavingsAccount.self,
            BondHolding.self,
            CashOtherAsset.self,
            LiabilityRecord.self,
            ManualCapitalEvent.self,
            LifestyleEntry.self,
        ])

        let storeURL = storeURL(fileName: storeFileName)

        // 1) 打开当前版本库
        do {
            let config = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            AppLog.debug("ModelContainer opened \(storeFileName)")
            return (container, nil)
        } catch {
            AppLog.error("ModelContainer open failed: \(error.localizedDescription)")
        }

        // 2) 先备份再删除当前版本库文件后重建
        backupStoreFiles(at: storeURL)
        removeStoreFiles(at: storeURL)
        do {
            let config = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            AppLog.debug("ModelContainer recreated \(storeFileName)")
            return (
                container,
                "本地数据已重置（数据库升级）。损坏库已备份至 Application Support/WealthKeeperBackups/。若有导出文件，可到设置 → 导入备份恢复。"
            )
        } catch {
            AppLog.error("ModelContainer recreate failed: \(error.localizedDescription)")
        }

        // 3) 内存库兜底，保证一定能出界面
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            return (
                container,
                "本地数据库无法打开，已使用临时模式。损坏库已备份至 Application Support/WealthKeeperBackups/。若有导出文件，可到设置 → 导入备份恢复。"
            )
        } catch {
            AppLog.error("ModelContainer in-memory failed: \(error.localizedDescription)")
        }

        // 4) 再试一次短暂内存配置
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            return (
                container,
                "本地数据库无法打开，已使用临时模式。损坏库已备份至 Application Support/WealthKeeperBackups/。若有导出文件，可到设置 → 导入备份恢复。"
            )
        } catch {
            fatalError("WealthKeeper 无法初始化数据层，请重装应用。")
        }
    }

    private static func storeURL(fileName: String) -> URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        try? fm.createDirectory(
            at: support,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        // 本地库路径：Application Support / WealthKeeper_v*.store
        // 可能随系统备份；未做应用层复杂加密或账号体系。详见设置 → 数据来源说明。
        return support.appendingPathComponent(fileName)
    }

    /// 在 wipe 前复制 store / wal / shm 到 Application Support/WealthKeeperBackups/
    private static func backupStoreFiles(at url: URL) {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let backupDir = support.appendingPathComponent("WealthKeeperBackups", isDirectory: true)
        do {
            try fm.createDirectory(
                at: backupDir,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            AppLog.error("backup dir create failed: \(error.localizedDescription)")
            return
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let candidates = storeFileCandidates(at: url)
        var copied = 0
        for file in candidates {
            guard fm.fileExists(atPath: file.path) else { continue }
            let destName = "\(file.lastPathComponent).\(stamp)"
            let dest = backupDir.appendingPathComponent(destName)
            do {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: file, to: dest)
                copied += 1
                AppLog.debug("backed up \(file.lastPathComponent) -> WealthKeeperBackups/\(destName)")
            } catch {
                AppLog.error("backup copy failed \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if copied == 0 {
            AppLog.debug("no store files to backup at \(url.lastPathComponent)")
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for file in storeFileCandidates(at: url) {
            if fm.fileExists(atPath: file.path) {
                try? fm.removeItem(at: file)
                AppLog.debug("removed \(file.lastPathComponent)")
            }
        }
    }

    private static func storeFileCandidates(at url: URL) -> [URL] {
        [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal"),
            url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-shm"),
            url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-wal"),
        ]
    }
}
