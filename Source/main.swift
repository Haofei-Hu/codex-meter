import AppKit
import SwiftUI
import Combine
import ServiceManagement
import Darwin

struct QuotaWindow: Codable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int { Int(max(0, min(100, 100 - usedPercent)).rounded(.down)) }
    var label: String {
        guard let minutes = windowDurationMins else { return "额度" }
        if minutes == 10080 { return "每周额度" }
        if minutes == 300 { return "5 小时额度" }
        if minutes >= 1440 { return "\(minutes / 1440) 天额度" }
        if minutes >= 60 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}
struct Bucket: Codable {
    let limitId: String?
    let limitName: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
}
struct Limits: Codable {
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?
    var rows: [QuotaRow] {
        let buckets: [(String, Bucket)]
        if let all = rateLimitsByLimitId, !all.isEmpty {
            buckets = all.sorted { ($0.key == "codex" ? "" : $0.key) < ($1.key == "codex" ? "" : $1.key) }
        } else if let single = rateLimits { buckets = [(single.limitId ?? "codex", single)] }
        else { buckets = [] }
        return buckets.flatMap { key, bucket in
            let fallback = rateLimits?.limitId == key || key == "codex" ? rateLimits : nil
            return [bucket.primary ?? fallback?.primary, bucket.secondary ?? fallback?.secondary].enumerated().compactMap { index, window -> QuotaRow? in
                guard let window else { return nil }
                return QuotaRow(id: "\(key)-\(index)", group: key == "codex" ? "Codex" : (bucket.limitName ?? key), window: window)
            }
        }.sorted {
            if $0.group != $1.group { return $0.group == "Codex" || ($1.group != "Codex" && $0.group < $1.group) }
            return ($0.window.windowDurationMins ?? Int.max) < ($1.window.windowDurationMins ?? Int.max)
        }
    }
}
struct QuotaRow: Identifiable { let id: String; let group: String; let window: QuotaWindow }
struct QuotaDisplayRow: Identifiable {
    let id: String
    let group: String
    let label: String
    let window: QuotaWindow?
    var remaining: Int? { window?.remaining }
}
struct AccountInfo: Decodable {
    let type: String
    let email: String?
    let planType: String?
}
struct AccountResponse: Decodable { let account: AccountInfo? }
struct AuthStamp: Equatable {
    let exists: Bool
    let modified: Date?
    let size: UInt64?
    let inode: UInt64?
    static func read(_ url: URL) -> AuthStamp {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return AuthStamp(exists: attributes != nil, modified: attributes?[.modificationDate] as? Date, size: attributes?[.size] as? UInt64, inode: attributes?[.systemFileNumber] as? UInt64)
    }
}

@MainActor final class QuotaModel: ObservableObject {
    @Published var limits: Limits?
    @Published var work = WorkOverview()
    private lazy var workTracker = WorkProgressTracker(
        root: authURL.deletingLastPathComponent().appendingPathComponent("sessions"),
        index: authURL.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
    ) { [weak self] overview in
        guard let self else { return }
        self.work = self.waitingForLogin || self.account == nil ? WorkOverview(state: .paused) : overview
        self.onChange?()
    }
    private func updateWorkTracking() {
        guard executableOverride == nil else { return }
        workTracker.setEnabled(hostRunning && !signedOut && account != nil)
    }
    @Published var lastUpdate: Date?
    @Published var error: String?
    @Published var loading = false
    @Published var account: AccountInfo?
    @Published var desktopScale: Double = 1
    @Published private(set) var desktopGlass: GlassAppearance
    @Published private(set) var popoverGlass: GlassAppearance
    @Published var cardHeight: CGFloat = 274
    @Published var cardVisibleHeight: CGFloat = 274
    @Published var cardScale: Double = 1
    private let executableOverride: String?
    private let authURL: URL
    private let preferences: UserDefaults
    private var authStamp: AuthStamp
    @Published private(set) var pausedReason: String?
    private var hostRunning = true
    private var signedOut = false
    private var needsAccountRead = true
    private var authDirectoryWatcher: DispatchSourceFileSystemObject?
    private var authFileWatcher: DispatchSourceFileSystemObject?
    private var authChangeWork: DispatchWorkItem?
    private var checkingAccount = false
    private var switchRetry: DispatchWorkItem?
    private var switchAttempts = 0
    private var partialRetry: DispatchWorkItem?
    private var partialAttempts = 0
    @Published var now = Date()
    @Published var desktopVisible = !UserDefaults.standard.bool(forKey: "desktopHidden")
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    var onChange: (() -> Void)?
    var toggleDesktop: (() -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var ready = false
    private var requestID = 10
    private var pendingID: Int?
    private var pendingAccountID: Int?
    private var timeout: DispatchWorkItem?
    private var ticker: Timer?
    private var nextPoll = Date.distantPast
    private var generation = UUID()
    let interval: TimeInterval = 15
    var rows: [QuotaRow] { limits?.rows ?? [] }
    var waitingForLogin: Bool { signedOut || !hostRunning }
    var statusText: String {
        if waitingForLogin { return "等待登录" }
        if loading && rows.isEmpty { return "正在同步" }
        if rows.isEmpty { return "暂未获取额度" }
        return minimum.map { "\($0)%" } ?? "暂未获取额度"
    }
    var displayRows: [QuotaDisplayRow] {
        let actual = rows.map { QuotaDisplayRow(id: $0.id, group: $0.group, label: $0.window.label, window: $0.window) }
        guard !waitingForLogin, account?.planType?.lowercased() == "plus" else { return actual }
        let codex = actual.filter { $0.group == "Codex" }
        let short = codex.filter { ($0.window?.windowDurationMins ?? 300) < 10080 }
        let weekly = codex.filter { ($0.window?.windowDurationMins ?? 0) >= 10080 }
        return (short.isEmpty ? [QuotaDisplayRow(id: "plus-short", group: "Codex", label: "5 小时额度", window: nil)] : short)
            + (weekly.isEmpty ? [QuotaDisplayRow(id: "plus-weekly", group: "Codex", label: "每周额度", window: nil)] : weekly)
            + actual.filter { $0.group != "Codex" }
    }
    var stale: Bool { pausedReason != nil || error != nil || lastUpdate.map { now.timeIntervalSince($0) > interval * 2 + 5 } ?? true }
    var dataAge: Int? { lastUpdate.map { max(0, Int(now.timeIntervalSince($0))) } }
    var syncLabel: String {
        if pausedReason != nil { return "已暂停" }
        if loading { return "同步中" }
        if stale { return "待更新" }
        return dataAge.map { $0 < 2 ? "刚更新" : "\($0)秒前" } ?? "待更新"
    }
    var minimum: Int? { rows.map { $0.window.remaining }.min() }
    var nextReset: Date? { rows.compactMap { $0.window.resetsAt }.map(Date.init(timeIntervalSince1970:)).min() }
    var nextUpdate: Date { nextPoll }
    var accountLabel: String {
        guard let account else { return loading ? "正在识别当前账号…" : "未登录 ChatGPT 账号" }
        let plan = ["plus": "Plus", "pro": "Pro", "prolite": "Pro Lite", "free": "Free", "team": "Team", "business": "Business", "enterprise": "Enterprise", "edu": "Edu"][account.planType ?? ""] ?? account.planType?.capitalized ?? "ChatGPT"
        return plan + (account.email.map { " · " + $0 } ?? "")
    }
    init(executableOverride: String? = nil, authURL: URL? = nil, preferences: UserDefaults = .standard) {
        self.executableOverride = executableOverride
        self.authURL = authURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path).appendingPathComponent("auth.json")
        self.preferences = preferences
        desktopGlass = GlassAppearance(preferences: preferences, target: .desktop)
        popoverGlass = GlassAppearance(preferences: preferences, target: .popover)
        self.authStamp = AuthStamp.read(self.authURL)
        // Quota is shown only after verifying the current login. Never restore another account's cache.
        preferences.removeObject(forKey: "cachedLimits")
        let saved = preferences.double(forKey: "desktopScale")
        desktopScale = saved == 0 ? 1 : max(0.75, min(1.6, saved))
    }
    func setScale(_ value: Double) {
        desktopScale = max(0.75, min(1.6, value))
        preferences.set(desktopScale, forKey: "desktopScale")
        onChange?()
    }
    func glassAppearance(for target: GlassTarget) -> GlassAppearance {
        target == .desktop ? desktopGlass : popoverGlass
    }
    func setGlassAppearance(_ value: GlassAppearance, for target: GlassTarget) {
        let next = GlassAppearance(transparency: value.transparency, frost: value.frost, theme: value.theme)
        guard next != glassAppearance(for: target) else { return }
        if target == .desktop { desktopGlass = next } else { popoverGlass = next }
        next.save(to: preferences, target: target)
        onChange?()
    }
    @discardableResult func checkLoginChange() -> Bool {
        let stamp = AuthStamp.read(authURL)
        guard stamp != authStamp else { return false }
        authStamp = stamp
        if !stamp.exists && account != nil {
            suspendForLogout()
        } else {
            signedOut = false
            reloadAccount()
        }
        return true
    }
    private func observeLoginChanges() {
        authDirectoryWatcher?.cancel(); authFileWatcher?.cancel()
        func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                // Ignore unrelated session/log writes in .codex. They must not postpone login detection.
                guard AuthStamp.read(self.authURL) != self.authStamp else { return }
                self.authChangeWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.checkLoginChange() { self.observeLoginChanges() }
                }
                self.authChangeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            return source
        }
        authDirectoryWatcher = watch(authURL.deletingLastPathComponent())
        authFileWatcher = watch(authURL)
    }
    func setHostRunning(_ running: Bool) {
        guard hostRunning != running else { return }
        hostRunning = running
        if !running {
            switchRetry?.cancel(); partialRetry?.cancel()
            disconnect(); loading = false
            limits = nil; lastUpdate = nil; account = nil; needsAccountRead = true
            pausedReason = "等待登录 · Codex 已退出"
            work = WorkOverview(state: .paused); updateWorkTracking()
            nextPoll = .distantFuture
            onChange?()
        } else { reloadAccount() }
    }
    private func suspendForLogout() {
        // Keep the idle connection listening for account/updated after logout.
        timeout?.cancel(); pendingID = nil; pendingAccountID = nil; checkingAccount = false
        switchRetry?.cancel(); partialRetry?.cancel()
        loading = false; signedOut = true; needsAccountRead = true
        limits = nil; lastUpdate = nil; account = nil; error = nil
        pausedReason = "等待登录 · 已退出登录"
        work = WorkOverview(state: .paused); updateWorkTracking()
        nextPoll = .distantFuture
        onChange?()
    }
    func reloadAccount() {
        switchRetry?.cancel(); partialRetry?.cancel(); switchAttempts = 0; partialAttempts = 0
        disconnect(); loading = false; needsAccountRead = true; signedOut = false
        limits = nil; lastUpdate = nil; account = nil; error = nil
        preferences.removeObject(forKey: "cachedLimits")
        work = WorkOverview(); updateWorkTracking()
        pausedReason = hostRunning ? nil : "等待登录 · Codex 已退出"
        if hostRunning { refresh() } else { onChange?() }
    }
    func start() {
        observeLoginChanges()
        refresh()
        ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                if self.pausedReason == nil && self.now >= self.nextPoll && !self.loading { self.refresh() }
                self.onChange?()
            }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    static func cliPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let custom = UserDefaults.standard.string(forKey: "cliPath")
        let appRoots = ["\(home)/Applications/ChatGPT.app", "/Applications/ChatGPT.app", "\(home)/Applications/Codex.app", "/Applications/Codex.app"]
        var candidates = custom.map { [$0] } ?? []
        for root in appRoots {
            candidates += ["\(root)/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "\(root)/Contents/Resources/codex", "\(root)/Contents/MacOS/codex"]
        }
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.npm-global/bin/codex"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func refresh() {
        guard !loading, pausedReason == nil else { return }
        loading = true; nextPoll = Date().addingTimeInterval(interval)
        let token = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.disconnect()
            self.fail("连接超时；将自动重试。请确认 Codex 已登录且网络正常。")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
        if ready {
            if needsAccountRead || account == nil { requestAccount() } else { requestLimits() }
        } else if process == nil { connect() }
        onChange?()
    }
    private func connect() {
        guard let path = executableOverride ?? Self.cliPath() else { fail("未找到 Codex。请安装并登录 Codex，或在菜单中选择 codex 程序。"); return }
        let proc = Process(); let stdin = Pipe(); let stdout = Pipe()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["app-server"]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        proc.environment = environment
        process = proc; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        let token = generation
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if !data.isEmpty { self.receive(data) }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.disconnect()
                self.fail("Codex 连接已断开；15 秒内自动重连。")
            }
        }
        do {
            try proc.run()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_quota", "title": "Codex Meter", "version": "1.4.0"]]])
        } catch { disconnect(); fail("无法启动 Codex：\(error.localizedDescription)") }
    }
    private func send(_ object: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
            try input?.write(contentsOf: data)
        } catch { disconnect(); fail("无法发送读取请求：\(error.localizedDescription)") }
    }
    private func requestLimits() {
        requestID += 1; pendingID = requestID
        send(["id": requestID, "method": "account/rateLimits/read"])
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let index = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<index]); buffer.removeSubrange(...index)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = object["id"] as? Int {
                guard id == 1 || id == pendingAccountID || id == pendingID else { continue }
                if let rpcError = object["error"] as? [String: Any] {
                    let accountFailed = id == pendingAccountID
                    disconnect()
                    if accountFailed { limits = nil; lastUpdate = nil; account = nil }
                    fail("读取失败：\(rpcError["message"] as? String ?? "请检查 Codex 登录状态")")
                    continue
                }
                if id == 1 {
                    ready = true; send(["method": "initialized", "params": [:]])
                    if needsAccountRead || account == nil {
                        requestAccount()
                    } else { requestLimits() }
                } else if id == pendingAccountID, let result = object["result"] as? [String: Any] {
                    checkingAccount = false; pendingAccountID = nil
                    guard let data = try? JSONSerialization.data(withJSONObject: result),
                          let response = try? JSONDecoder().decode(AccountResponse.self, from: data) else {
                        disconnect(); limits = nil; lastUpdate = nil; account = nil; fail("无法识别当前账号，请重新检测。"); return
                    }
                    guard let current = response.account, current.type == "chatgpt" || current.type == "chatgptAuthTokens" else {
                        suspendForLogout()
                        scheduleSwitchRetry()
                        return
                    }
                    switchRetry?.cancel(); switchAttempts = 0
                    if account?.email != current.email || account?.planType != current.planType {
                        limits = nil; lastUpdate = nil
                    }
                    account = current; needsAccountRead = false; pausedReason = nil; signedOut = false
                    updateWorkTracking()
                    requestLimits()
                } else if !checkingAccount, account != nil, id == pendingID, let result = object["result"] as? [String: Any] { accept(result) }
            } else if object["method"] as? String == "account/rateLimits/updated", let params = object["params"] as? [String: Any] {
                // An in-flight fresh read takes precedence over older push messages.
                if account != nil && !checkingAccount && pendingID == nil { accept(params, fromNotification: true) }
            } else if object["method"] as? String == "account/updated" {
                // The server also announces its initial auth state during the handshake.
                // Let the in-flight account/read verify it rather than restarting in a loop.
                if !ready { continue }
                if let params = object["params"] as? [String: Any], params["authMode"] is NSNull { suspendForLogout(); return }
                if checkingAccount { continue }
                // Read the updated account on this connection; reconnecting here can repeat startup notifications.
                timeout?.cancel(); pendingID = nil
                limits = nil; lastUpdate = nil; account = nil; error = nil
                needsAccountRead = true; signedOut = false; pausedReason = nil
                work = WorkOverview(); updateWorkTracking()
                partialRetry?.cancel(); partialAttempts = 0
                loading = false; refresh()
                return
            }
        }
    }
    private func requestAccount() {
        checkingAccount = true; requestID += 1; pendingAccountID = requestID
        send(["id": requestID, "method": "account/read", "params": ["refreshToken": false]])
    }
    private func scheduleSwitchRetry() {
        guard hostRunning, AuthStamp.read(authURL).exists, switchAttempts < 4 else { return }
        // A login-file change may precede the finished account write. Retry only this transition.
        switchAttempts += 1
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.hostRunning else { return }
            self.signedOut = false; self.pausedReason = nil
            self.refresh()
        }
        switchRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(switchAttempts * 2), execute: work)
    }
    private func accept(_ object: [String: Any], fromNotification: Bool = false) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let value = try JSONDecoder().decode(Limits.self, from: data)
            guard !value.rows.isEmpty else { limits = nil; fail("此账号未返回百分比额度。请确认使用 ChatGPT 账号登录 Codex。"); return }
            limits = value; lastUpdate = Date(); now = Date(); error = nil; loading = false
            timeout?.cancel(); pendingID = nil
            // Push updates must not postpone the next authoritative read.
            if !fromNotification { nextPoll = Date().addingTimeInterval(interval) }
            if displayRows.contains(where: { $0.window == nil }), partialAttempts < 3 {
                partialAttempts += 1
                let token = generation
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.refresh()
                }
                partialRetry?.cancel(); partialRetry = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(partialAttempts * 2), execute: work)
            } else { partialRetry?.cancel() }
            onChange?()
        } catch { fail("额度数据格式发生变化，请更新本工具。") }
    }
    private func fail(_ message: String) {
        error = message; loading = false; timeout?.cancel(); pendingID = nil
        nextPoll = Date().addingTimeInterval(interval); onChange?()
    }
    func disconnect() {
        generation = UUID(); ready = false; checkingAccount = false; timeout?.cancel(); pendingID = nil; pendingAccountID = nil
        output?.readabilityHandler = nil; process?.terminationHandler = nil
        try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil; buffer.removeAll()
    }
    func selectCLI() {
        let panel = NSOpenPanel(); panel.title = "选择 codex 可执行程序"; panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { error = "所选文件不是可执行程序。"; return }
            UserDefaults.standard.set(url.path, forKey: "cliPath")
            reloadAccount()
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { error = "请在系统设置 → 通用 → 登录项中允许 Codex Meter。" }
        } catch { self.error = "无法更改开机启动：\(error.localizedDescription)" }
    }
}

let mint = Color(red: 0.42, green: 0.92, blue: 0.77)
func quotaColor(_ amount: Int) -> Color {
    let remaining = Double(max(0, min(100, amount)))
    let green = (r: 0.42, g: 0.92, b: 0.77)
    let orange = (r: 1.0, g: 0.58, b: 0.18)
    let red = (r: 1.0, g: 0.25, b: 0.28)
    let start = remaining >= 30 ? green : orange
    let end = remaining >= 30 ? orange : red
    let t = remaining >= 30 ? (100 - remaining) / 70 : (30 - remaining) / 30
    // Continuous color with a gentle transition at the orange midpoint.
    let blend = t * t * (3 - 2 * t)
    return Color(red: start.r + (end.r - start.r) * blend,
                 green: start.g + (end.g - start.g) * blend,
                 blue: start.b + (end.b - start.b) * blend)
}
func dateText(_ date: Date, short: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = short ? "MM/dd" : "MM月dd日 HH:mm"
    return formatter.string(from: date)
}
func remainingText(_ date: Date, now: Date) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    if seconds == 0 { return "等待服务器更新" }
    let days = seconds / 86400; let hours = seconds % 86400 / 3600; let mins = seconds % 3600 / 60
    return days > 0 ? "\(days)天 \(hours)小时后重置" : hours > 0 ? "\(hours)小时 \(mins)分钟后重置" : "\(max(1, mins))分钟后重置"
}
struct QuotaRing: View {
    let remaining: Int?
    // Strokes extend on both sides of the path. Keep the full stroke plus an
    // antialiasing margin inside the layout bounds, including in a ScrollView.
    private let inset: CGFloat = 4
    private var fraction: Double { Double(max(0, min(100, remaining ?? 0))) / 100 }
    var body: some View {
        ZStack {
            Circle().inset(by: inset).stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle().inset(by: inset).trim(from: 1 - fraction, to: 1)
                .stroke(quotaColor(remaining ?? 100), style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.2), value: remaining)
            VStack(spacing: 0) {
                Text(remaining.map(String.init) ?? "—").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Text(remaining == nil ? "未返回" : "% 剩余").font(.system(size: 9, weight: .medium)).foregroundStyle(glassSecondary)
            }
        }.frame(width: 94, height: 94)
    }
}
struct QuotaCard: View {
    @ObservedObject var model: QuotaModel
    @Environment(\.colorScheme) private var inheritedColorScheme
    var desktop = false
    var openMenu: (() -> Void)? = nil
    var viewportHeight: CGFloat? = nil
    var showsSurface = true
    var header: some View {
            HStack(spacing: 9) {
              HStack(spacing: 9) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 17, weight: .bold)).foregroundStyle(mint)
                Text("Codex 剩余额度").font(.system(size: 14, weight: .semibold))
                Spacer()
                Circle().fill(model.stale ? Color.orange : mint).frame(width: 5, height: 5)
                Text(model.syncLabel).font(.system(size: 10)).foregroundStyle(glassSecondary)
              }
                if desktop {
                    Button { openMenu?() } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }.modifier(NativeIconButtonStyle()).help("卡片设置").background { WindowControlRegion() }
                }
            }
    }
    var contents: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.accountLabel).font(.system(size: 10)).foregroundStyle(glassSecondary).lineLimit(1).truncationMode(.middle)
            if model.displayRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("—").font(.system(size: 52, weight: .light))
                    Text(model.pausedReason ?? (model.loading ? "正在读取你的 Codex 额度…" : "暂未获取到额度")).foregroundStyle(glassSecondary)
                }.frame(height: 110)
            } else {
                ForEach(model.displayRows) { row in
                    HStack(spacing: 20) {
                        QuotaRing(remaining: row.remaining)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.group == "Codex" ? row.label : "\(row.group) · \(row.label)").font(.system(size: 13, weight: .semibold))
                            if let reset = row.window?.resetsAt {
                                let date = Date(timeIntervalSince1970: reset)
                                Text(remainingText(date, now: model.now)).font(.system(size: 11)).foregroundStyle(mint)
                                Text(dateText(date)).font(.system(size: 11)).foregroundStyle(glassSecondary)
                            } else { Text(row.window == nil ? "等待服务器返回额度" : "未提供重置时间").font(.system(size: 11)).foregroundStyle(glassSecondary) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            WorkProgressSection(overview: model.work, now: model.now)
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.fixedSize(horizontal: false, vertical: true)
    }
    var footer: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.lastUpdate.map { "更新于 " + $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)) } ?? "尚未同步").font(.system(size: 10)).foregroundStyle(glassSecondary)
                    Text(model.pausedReason ?? "每 \(Int(model.interval)) 秒同步 · \(max(0, Int(model.nextUpdate.timeIntervalSince(model.now)))) 秒后刷新").font(.system(size: 9)).foregroundStyle(glassTertiary).monospacedDigit()
                }
                Spacer()
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30)
                }.modifier(NativeIconButtonStyle()).disabled(model.loading || model.pausedReason != nil).help("立即刷新")
                 .background { if desktop { WindowControlRegion() } }

            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header.fixedSize(horizontal: false, vertical: true)
            if viewportHeight != nil {
                ScrollView(.vertical) { contents }.scrollIndicators(.automatic)
                    .frame(maxHeight: .infinity)
            } else { contents }
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            footer.fixedSize(horizontal: false, vertical: true)
            if !desktop { QuotaSettings(model: model) }
        }
        .padding(22).frame(width: 332, height: viewportHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .background { if showsSurface { GlassSurface(appearance: model.desktopGlass) } }
        .overlay(alignment: .bottomTrailing) {
            if desktop { ResizeGrip(model: model).frame(width: 30, height: 30).padding(5) }
        }
        .environment(\.colorScheme, (desktop ? model.desktopGlass : model.popoverGlass).theme.colorScheme ?? inheritedColorScheme)
    }
}
struct QuotaSettings: View {
    @ObservedObject var model: QuotaModel
    var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    GlassAppearanceSettings(model: model)
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("桌面卡片大小")
                            Spacer()
                            Text("\(Int((model.desktopScale * 100).rounded()))%").monospacedDigit()
                            Button("还原") { model.setScale(1) }
                        }
                        Slider(value: Binding(get: { model.desktopScale }, set: { model.setScale($0) }), in: 0.75...1.6, step: 0.05)
                            .accessibilityLabel("桌面卡片缩放")
                    }
                    Button("重新检测账号") { model.reloadAccount() }
                    Toggle("显示桌面卡片", isOn: Binding(get: { model.desktopVisible }, set: { _ in model.toggleDesktop?() }))
                    Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    HStack {
                        Button("选择 Codex 程序…") { model.selectCLI() }
                        Spacer()
                        Button("退出") { NSApp.terminate(nil) }
                    }.foregroundStyle(glassSecondary)
                }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
    }
}
struct SettingsPanel: View {
    @ObservedObject var model: QuotaModel
    @Environment(\.colorScheme) private var inheritedColorScheme
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("卡片设置").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("关闭设置")
            }
            QuotaSettings(model: model)
        }
        .padding(20).frame(width: 300)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .background { GlassSurface(appearance: model.popoverGlass) }
        .environment(\.colorScheme, model.popoverGlass.theme.colorScheme ?? inheritedColorScheme)
    }
}
struct DesktopCard: View {
    @ObservedObject var model: QuotaModel
    var openMenu: () -> Void
    var body: some View {
        QuotaCard(model: model, desktop: true, openMenu: openMenu, viewportHeight: model.cardVisibleHeight)
            .fixedSize()
            .scaleEffect(model.cardScale, anchor: .topLeading)
            .frame(width: 332 * model.cardScale, height: model.cardVisibleHeight * model.cardScale, alignment: .topLeading)
    }
}
func statusProgressImage(remaining: Int?, stale: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 44, height: 16), flipped: false) { _ in
        let track = NSRect(x: 1, y: 4, width: 42, height: 8)
        let shape = NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4)
        NSColor.gray.withAlphaComponent(0.32).setFill()
        shape.fill()
        if let remaining {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSColor(quotaColor(remaining)).withAlphaComponent(stale ? 0.45 : 1).setFill()
            NSRect(x: track.minX, y: track.minY, width: track.width * Double(max(0, min(100, remaining))) / 100, height: track.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = "Codex 剩余额度进度条"
    return image
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = QuotaModel()
    var statusItem: NSStatusItem!
    // Desktop settings and the menu-bar overview have independent windows and anchors.
    var popover = makeNativePopover()
    var statusPopover = makeNativePopover()
    var statusHostingController: NSHostingController<StatusMenuContent>?
    var lastMenuLayoutKey = ""
    var panel: DesktopPanel!
    var subscriptions = Set<AnyCancellable>()
    var lastStatusImageKey = ""
    var lastLayoutKey = ""
    var hostObservers: [NSObjectProtocol] = []
    func hostIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            !$0.isTerminated && ["ChatGPT.app", "Codex.app"].contains($0.bundleURL?.lastPathComponent ?? "")
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(showPopover)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.imagePosition = .imageLeading
        NSApp.publisher(for: \.effectiveAppearance).receive(on: RunLoop.main).sink { [weak self] appearance in
            guard let self else { return }
            let resolved = self.model.popoverGlass.theme.nativeAppearance ?? appearance
            self.popover.appearance = resolved
            self.statusPopover.appearance = resolved
        }.store(in: &subscriptions)
        panel = DesktopPanel(cardFrame: NSRect(x: 0, y: 0, width: 332, height: 244))
        let desktopHost = NSHostingView(rootView: DesktopCard(model: model, openMenu: { [weak self] in self?.showDesktopPopover() }))
        desktopHost.sizingOptions = []
        panel.contentView = desktopHost
        panel.dragEnded = { [weak self] in self?.lastLayoutKey = ""; self?.updateStatus() }
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: area.maxX - 356, y: area.maxY - 285))
        panel.setFrameAutosaveName("CodexQuotaDesktop")
        panel.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "打开状态栏面板", target: self, selector: #selector(accessibilityOpenStatusMenu))])
        if model.desktopVisible { panel.orderBack(nil) }
        model.onChange = { [weak self] in DispatchQueue.main.async { self?.updateStatus() } }
        model.toggleDesktop = { [weak self] in
            guard let self else { return }
            self.model.desktopVisible.toggle()
            UserDefaults.standard.set(!self.model.desktopVisible, forKey: "desktopHidden")
            if self.model.desktopVisible { self.panel.orderBack(nil) } else { self.panel.orderOut(nil) }
        }
        model.setHostRunning(hostIsRunning())
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            hostObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      ["ChatGPT.app", "Codex.app"].contains(app.bundleURL?.lastPathComponent ?? "") else { return }
                Task { @MainActor in guard let self else { return }; self.model.setHostRunning(self.hostIsRunning()) }
            })
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lastLayoutKey = ""; self?.updateStatus() }
        }
        updateStatus(); model.start()
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.snapshot(path) }
        }
    }
    @objc func accessibilityOpenStatusMenu() -> Bool { showPopover(); return true }
    @objc func showPopover() {
        if statusPopover.isShown { closeStatusMenu(); return }
        popover.performClose(nil)
        guard let button = statusItem.button else { return }
        statusPopover.appearance = NSApp.effectiveAppearance
        statusPopover.glassAppearance = model.popoverGlass
        lastMenuLayoutKey = ""
        layoutStatusMenu()
        statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if model.lastUpdate == nil || (model.dataAge ?? 0) >= 3 { model.refresh() }
    }
    func closeStatusMenu() { statusPopover.performClose(nil) }
    func layoutStatusMenu() {
        guard let buttonWindow = statusItem.button?.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let key = "\(model.displayRows.map { $0.id }.joined(separator: ","))-\(model.error ?? "")-\(model.accountLabel)-\(model.pausedReason ?? "")-\(model.work.state)-\(model.work.tasks.map { "\($0.id):\($0.title):\($0.detail):\($0.planTotal):\($0.stage)" }.joined(separator: ","))"
        guard key != lastMenuLayoutKey else { return }
        lastMenuLayoutKey = key
        let measure = NSHostingView(rootView: QuotaCard(model: model, showsSurface: false))
        let size = statusPopoverContentSize(natural: measure.fittingSize, visibleFrame: screen.visibleFrame)
        if let host = statusHostingController {
            if host.rootView.height != size.height { host.rootView = StatusMenuContent(model: model, height: size.height) }
        } else {
            let host = NSHostingController(rootView: StatusMenuContent(model: model, height: size.height))
            statusHostingController = host
            statusPopover.contentViewController = host
        }
        if statusPopover.contentSize != size { statusPopover.contentSize = size }
    }
    func showDesktopPopover() {
        closeStatusMenu()
        guard let view = panel.contentView else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.appearance = NSApp.effectiveAppearance
            popover.glassAppearance = model.popoverGlass
            popover.contentViewController = NSHostingController(rootView: SettingsPanel(model: model, close: { [weak self] in self?.popover.performClose(nil) }))
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minX)
            if model.lastUpdate == nil || (model.dataAge ?? 0) >= 3 { model.refresh() }
        }
    }
    func updateStatus() {
        statusPopover.glassAppearance = model.popoverGlass
        popover.glassAppearance = model.popoverGlass
        if statusPopover.isShown { layoutStatusMenu() }
        let layoutKey = "\(model.displayRows.map { $0.id }.joined(separator: ","))-\(model.error ?? "")-\(model.accountLabel)-\(model.pausedReason ?? "")-\(model.desktopScale)-\(model.work.state)-\(model.work.tasks.map { "\($0.id):\($0.title):\($0.detail):\($0.planTotal):\($0.stage)" }.joined(separator: ","))"
        if layoutKey != lastLayoutKey, panel != nil, !panel.userDragging {
            lastLayoutKey = layoutKey
            // Measure the unconstrained card, rather than the already-sized window.
            let measuringView = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
            let baseSize = measuringView.fittingSize
            if baseSize.height > 100 {
                let area = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
                let layout = desktopCardLayout(naturalHeight: baseSize.height, requestedScale: model.desktopScale, visibleFrame: area, currentFrame: panel.frame)
                model.cardHeight = baseSize.height
                model.cardVisibleHeight = layout.visibleHeight
                model.cardScale = layout.scale
                if panel.frame != layout.frame { panel.setFrame(layout.frame, display: true) }
            }
        }
        let waiting = model.waitingForLogin
        let displayRows = model.displayRows
        let doubleRows = displayRows.count == 2 && model.account?.planType?.lowercased() == "plus"
        let imageKey = "\(waiting)-\(displayRows.map { "\($0.label):\($0.remaining ?? -1)" }.joined(separator: ","))-\(model.stale)"
        if imageKey != lastStatusImageKey {
            statusItem.button?.image = waiting ? nil : doubleRows ? statusDoubleProgressImage(rows: displayRows, stale: model.stale) : statusProgressImage(remaining: model.minimum, stale: model.stale)
            lastStatusImageKey = imageKey
        }
        let workSuffix = model.work.state == .running ? " · \(model.work.activeCount)任务" : ""
        let title = waiting ? "Codex · 等待登录" : (doubleRows ? " Codex 剩余额度" : " Codex 剩余额度 " + model.statusText) + workSuffix
        let color = waiting ? NSColor.labelColor : model.minimum.map { NSColor(quotaColor($0)).withAlphaComponent(model.stale ? 0.65 : 1) } ?? NSColor.labelColor
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: color, .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        statusItem.button?.setAccessibilityLabel(title)
        let rows = displayRows.map { row in
            "\(row.group) \(row.label)：" + (row.remaining.map { "剩余 \($0)%" } ?? "等待服务器返回")
                + (row.window.map { " · 已用 \(Int($0.usedPercent.rounded()))%" } ?? "")
        }.joined(separator: "\n")
        let workTip = "\n工作状态：" + model.work.label + model.work.tasks.map { "\n" + $0.title + " · " + $0.stage + " · " + workElapsed($0, now: model.now) }.joined()
        statusItem.button?.toolTip = waiting ? "等待登录 · 登录 Codex 后自动更新" : model.accountLabel + workTip + "\n" + rows + "\n" + (model.nextReset.map { "重置：" + dateText($0) } ?? "") + (model.lastUpdate.map { "\n接口更新：" + $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)) } ?? "") + (model.stale ? "\n数据待更新" : "")
    }

    func snapshot(_ path: String) {
        let host = NSHostingView(rootView: QuotaCard(model: model, desktop: true))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    func applicationWillTerminate(_ notification: Notification) { statusPopover.close(); popover.close(); model.disconnect() }
}

if let index = CommandLine.arguments.firstIndex(of: "--desktop-test"), CommandLine.arguments.count > index + 1 {
    MainActor.assumeIsolated { runDesktopCardTests(directory: CommandLine.arguments[index + 1]) }
} else if CommandLine.arguments.contains("--work-probe") {
    MainActor.assumeIsolated { probeLiveWork() }
} else if let index = CommandLine.arguments.firstIndex(of: "--work-test"), CommandLine.arguments.count > index + 1 {
    MainActor.assumeIsolated { runWorkTrackerTest(directory: CommandLine.arguments[index + 1]) }
} else if let index = CommandLine.arguments.firstIndex(of: "--render-plus"), CommandLine.arguments.count > index + 1 {
    MainActor.assumeIsolated { renderPlusPreview(directory: CommandLine.arguments[index + 1]) }
} else if let index = CommandLine.arguments.firstIndex(of: "--integration-test"), CommandLine.arguments.count > index + 1 {
    MainActor.assumeIsolated { runIntegrationTests(directory: CommandLine.arguments[index + 1]) }
} else if let index = CommandLine.arguments.firstIndex(of: "--render-status"), CommandLine.arguments.count > index + 1 {
    MainActor.assumeIsolated {
        let levels = [100, 75, 50, 30, 15, 0]
        let image = NSImage(size: NSSize(width: 360, height: 164), flipped: false) { _ in
            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.10, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 360, height: 164).fill()
            for (index, level) in levels.enumerated() {
                let x = CGFloat(index) * 60 + 8
                let y: CGFloat = 66
                NSColor(quotaColor(level)).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 40, height: 40))
                ring.lineWidth = 4; ring.stroke()
                let label = "\(level)%"
                label.draw(at: NSPoint(x: x + 3, y: 115), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
                statusProgressImage(remaining: level, stale: false).draw(in: NSRect(x: x - 2, y: 32, width: 44, height: 16))
            }
            return true
        }
        if let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
            try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }
} else if CommandLine.arguments.contains("--self-test") {
    testDesktopCardLayout()
    testStatusMenuPositioning()
    testWorkLogReducer()
    let data = #"{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1793536107}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1793536107},"secondary":{"usedPercent":105,"windowDurationMins":300,"resetsAt":1793000000}}}}"#.data(using: .utf8)!
    let limits = try JSONDecoder().decode(Limits.self, from: data)
    precondition(limits.rows.count == 2)
    precondition(limits.rows.map { $0.window.remaining } == [0, 99])
    precondition(limits.rows.map { $0.window.label } == ["5 小时额度", "每周额度"])
    precondition(QuotaWindow(usedPercent: -1, windowDurationMins: nil, resetsAt: nil).remaining == 100)
    let partial = #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"usedPercent":54,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}"#.data(using: .utf8)!
    let merged = try JSONDecoder().decode(Limits.self, from: partial)
    precondition(merged.rows.map { $0.window.remaining } == [88, 46])
    print("PASS: quota parsing, window ordering, partial-bucket merge, percentage clamping")
} else if CommandLine.arguments.contains("--probe") {
    MainActor.assumeIsolated {
        let model = QuotaModel()
        model.onChange = {
            if let error = model.error { fputs("FAIL: \(error)\n", stderr); exit(1) }
            if model.lastUpdate != nil && !model.loading {
                print("PASS: live app-server read: " + model.rows.map { "\($0.window.label) \($0.window.remaining)% remaining" }.joined(separator: ", "))
                model.disconnect(); exit(0)
            }
        }
        model.start()
        RunLoop.main.run(until: Date().addingTimeInterval(30))
        model.disconnect(); exit(2)
    }
} else {
    MainActor.assumeIsolated {
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("local.codexquota.mac.\(getuid()).lock")
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
