import Foundation
import SwiftUI

struct WorkTask: Identifiable, Equatable {
    let id: String
    var title: String
    var turnID: String?
    var active = false
    var stage = "进行中"
    var startedAt: Date?
    var finishedAt: Date?
    var updatedAt = Date.distantPast
    var detail = ""
    var tools: Set<String> = []
    var completedCalls: Set<String> = []
    var planDone = 0
    var planTotal = 0
    var progress: Double? { planTotal > 0 ? Double(planDone) / Double(planTotal) : nil }
}
struct WorkOverview: Equatable {
    enum State: Equatable { case loading, running, idle, unavailable, paused }
    var state: State = .loading
    var tasks: [WorkTask] = []
    var activeCount = 0
    var label: String {
        switch state {
        case .loading: return "读取工作状态…"
        case .running: return activeCount > 1 ? "\(activeCount) 个任务进行中" : "工作中"
        case .idle: return "空闲"
        case .unavailable: return "任务状态暂不可用"
        case .paused: return "更新已暂停"
        }
    }
}

// Local logs are data, never commands. Parse only public progress and lifecycle fields;
// reasoning, tool arguments/results, credentials, and user message bodies are not displayed.
struct WorkLogReducer {
    var task: WorkTask
    private static let timestampFormatter = ISO8601DateFormatter()
    static func timestamp(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        guard let text = value as? String else { return nil }
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = timestampFormatter.date(from: text) { return date }
        timestampFormatter.formatOptions = [.withInternetDateTime]
        return timestampFormatter.date(from: text)
    }
    static func clean(_ text: String, limit: Int = 160) -> String {
        String(text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
    mutating func consume(_ object: [String: Any]) {
        guard let payload = object["payload"] as? [String: Any] else { return }
        let record = object["type"] as? String ?? ""
        let kind = payload["type"] as? String ?? ""
        let timestamp = Self.timestamp(object["timestamp"]) ?? task.updatedAt
        if record == "session_meta", let id = payload["id"] as? String {
            task = WorkTask(id: id, title: task.title)
            return
        }
        if record == "event_msg" {
            switch kind {
            case "task_started":
                task.turnID = payload["turn_id"] as? String
                task.active = true; task.stage = "进行中"
                task.startedAt = Self.timestamp(payload["started_at"]) ?? timestamp
                task.finishedAt = nil; task.detail = ""
                task.tools.removeAll(); task.completedCalls.removeAll(); task.planDone = 0; task.planTotal = 0
            case "task_complete", "turn_aborted":
                if let turn = payload["turn_id"] as? String, let current = task.turnID, turn != current { return }
                task.active = false
                task.stage = kind == "task_complete" ? "已完成" : "已中断"
                task.finishedAt = Self.timestamp(payload["completed_at"]) ?? timestamp
                task.tools.removeAll()
            case "approval_requested", "user_input_requested":
                if task.active { task.stage = "等待操作" }
            case "plan_update", "plan_updated": updatePlan(payload["plan"])
            default: break
            }
        } else if record == "response_item", task.active {
            switch kind {
            case "function_call", "custom_tool_call":
                if let id = payload["call_id"] as? String { task.tools.insert(id) }
                task.stage = "执行工具"
                if payload["name"] as? String == "update_plan",
                   let args = payload["arguments"] as? String,
                   let data = args.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { updatePlan(object["plan"]) }
            case "function_call_output", "custom_tool_call_output":
                if let id = payload["call_id"] as? String { task.tools.remove(id); task.completedCalls.insert(id) }
                task.stage = task.tools.isEmpty ? "进行中" : "执行工具"
            case "message":
                guard payload["role"] as? String == "assistant", payload["phase"] as? String == "commentary",
                      let content = payload["content"] as? [[String: Any]] else { break }
                let text = content.compactMap { $0["text"] as? String }.joined(separator: " ")
                if !text.isEmpty { task.detail = Self.clean(text) }
            default: break
            }
        }
        // Activity timestamp alone can be observed; private reasoning text is ignored.
        task.updatedAt = max(task.updatedAt, timestamp)
    }
    private mutating func updatePlan(_ value: Any?) {
        guard let steps = value as? [[String: Any]], !steps.isEmpty else { return }
        task.planTotal = steps.count
        task.planDone = steps.filter { $0["status"] as? String == "completed" }.count
        if let step = steps.first(where: { $0["status"] as? String == "in_progress" })?["step"] as? String {
            task.detail = Self.clean(step)
        }
    }
}

final class WorkProgressTracker: @unchecked Sendable {
    private struct Cursor {
        var offset: UInt64 = 0
        var pending = Data()
        var reducer: WorkLogReducer
    }
    private let root: URL
    private let index: URL
    private let queue = DispatchQueue(label: "local.codexmeter.work-progress", qos: .utility)
    private let onUpdate: @MainActor (WorkOverview) -> Void
    private var enabled = false
    private var timer: DispatchSourceTimer?
    private var cursors: [URL: Cursor] = [:]
    private var lastOverview: WorkOverview?
    init(root: URL, index: URL, onUpdate: @escaping @MainActor (WorkOverview) -> Void) {
        self.root = root; self.index = index; self.onUpdate = onUpdate
    }
    func setEnabled(_ value: Bool) {
        queue.async { [self] in
            if enabled != value { cursors.removeAll(); lastOverview = nil }
            enabled = value
            if timer == nil {
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(200))
                source.setEventHandler { [weak self] in self?.poll() }
                timer = source; source.resume()
            }
            if !value { emit(WorkOverview(state: .paused)) } else { poll() }
        }
    }
    private func emit(_ overview: WorkOverview) {
        guard overview != lastOverview else { return }
        lastOverview = overview
        DispatchQueue.main.async { [onUpdate] in onUpdate(overview) }
    }
    private func titles() -> [String: String] {
        guard let data = try? Data(contentsOf: index) else { return [:] }
        var result: [String: String] = [:]
        for line in data.suffix(1024 * 1024).split(separator: 10) {
            guard let item = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = item["id"] as? String, let name = item["thread_name"] as? String else { continue }
            result[id] = WorkLogReducer.clean(name, limit: 80)
        }
        return result
    }
    private func poll() {
        guard enabled else { return }
        let now = Date()
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            emit(WorkOverview(state: .unavailable)); return
        }
        let names = titles()
        var touched = Set<URL>()
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = attrs.contentModificationDate, now.timeIntervalSince(modified) < 86400 else { continue }
            touched.insert(url)
            var cursor = cursors[url] ?? Cursor(reducer: WorkLogReducer(task: WorkTask(id: url.lastPathComponent, title: "本机 Codex 任务")))
            if UInt64(attrs.fileSize ?? 0) < cursor.offset { cursor = Cursor(reducer: WorkLogReducer(task: WorkTask(id: url.lastPathComponent, title: "本机 Codex 任务"))) }
            if UInt64(attrs.fileSize ?? 0) > cursor.offset, let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                do {
                    try handle.seek(toOffset: cursor.offset)
                    while let chunk = try handle.read(upToCount: 262144), !chunk.isEmpty {
                        cursor.offset += UInt64(chunk.count); cursor.pending.append(chunk)
                        while let end = cursor.pending.firstIndex(of: 10) {
                            let line = Data(cursor.pending[..<end]); cursor.pending.removeSubrange(...end)
                            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { cursor.reducer.consume(object) }
                        }
                        // A giant unfinished record cannot be public progress; avoid unbounded buffering.
                        if cursor.pending.count > 16 * 1024 * 1024 { cursor.pending.removeAll() }
                    }
                } catch { continue }
            }
            if let title = names[cursor.reducer.task.id] { cursor.reducer.task.title = title }
            cursors[url] = cursor
        }
        cursors = cursors.filter { touched.contains($0.key) }
        let tasks = cursors.values.map { $0.reducer.task }.filter { $0.startedAt != nil }.sorted { $0.updatedAt > $1.updatedAt }
        let active = tasks.filter { $0.active }
        if !active.isEmpty { emit(WorkOverview(state: .running, tasks: Array(active.prefix(2)), activeCount: active.count)) }
        else { emit(WorkOverview(state: .idle, tasks: Array(tasks.filter { now.timeIntervalSince($0.updatedAt) < 900 }.prefix(1)))) }
    }
}

func workElapsed(_ task: WorkTask, now: Date) -> String {
    guard let start = task.startedAt else { return "" }
    let seconds = max(0, Int((task.finishedAt ?? now).timeIntervalSince(start)))
    if seconds >= 3600 { return "\(seconds / 3600)小时 \(seconds % 3600 / 60)分钟" }
    return seconds >= 60 ? "\(seconds / 60)分 \(seconds % 60)秒" : "\(seconds)秒"
}
struct WorkProgressSection: View {
    let overview: WorkOverview
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path").foregroundStyle(mint)
                Text("实时工作进度").fontWeight(.semibold)
                Spacer()
                Text(overview.label).foregroundStyle(overview.state == .running ? mint : .secondary)
            }.font(.system(size: 11))
            ForEach(overview.tasks) { task in
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        if task.active { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12) }
                        Text(task.stage)
                        Spacer()
                        Text((task.active ? "已运行 " : "耗时 ") + workElapsed(task, now: now)).monospacedDigit()
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    if let progress = task.progress {
                        ProgressView(value: progress).tint(mint)
                        Text("计划步骤 \(task.planDone)/\(task.planTotal) 完成").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    if !task.detail.isEmpty { Text(task.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                    if task.active && now.timeIntervalSince(task.updatedAt) > 120 {
                        Text("\(Int(now.timeIntervalSince(task.updatedAt) / 60)) 分钟未收到新记录").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
            }
            if overview.tasks.isEmpty {
                Text(overview.state == .idle ? "暂无运行中的本机任务" : overview.state == .paused ? "登录并打开 Codex 后自动恢复" : overview.state == .unavailable ? "未找到可读取的本机任务记录" : "正在读取本机任务记录…")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("本机任务记录 · 每 2 秒更新").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
