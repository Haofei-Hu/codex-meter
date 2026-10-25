import Foundation

func testWorkLogReducer() {
    var reducer = WorkLogReducer(task: WorkTask(id: "test", title: "测试任务"))
    func event(_ kind: String, _ payload: [String: Any] = [:]) -> [String: Any] {
        ["timestamp": "2026-10-25T15:00:00.000Z", "type": "event_msg", "payload": payload.merging(["type": kind]) { _, new in new }]
    }
    func item(_ kind: String, _ payload: [String: Any] = [:]) -> [String: Any] {
        ["timestamp": "2026-10-25T15:00:01.000Z", "type": "response_item", "payload": payload.merging(["type": kind]) { _, new in new }]
    }
    reducer.consume(event("task_started", ["turn_id": "turn1", "started_at": 1792940400]))
    precondition(reducer.task.active && reducer.task.progress == nil)
    reducer.consume(item("message", ["role": "assistant", "phase": "commentary", "content": [["text": "正在运行测试"]]]))
    precondition(reducer.task.detail == "正在运行测试")
    reducer.consume(item("reasoning", ["text": "private reasoning must not appear"]))
    reducer.consume(item("message", ["role": "user", "content": [["text": "private user text"]]]))
    precondition(reducer.task.detail == "正在运行测试")
    reducer.consume(item("custom_tool_call", ["call_id": "c1", "name": "functions.exec", "input": "private script"]))
    precondition(reducer.task.stage == "执行工具" && reducer.task.tools.count == 1)
    reducer.consume(item("custom_tool_call_output", ["call_id": "c1", "output": "private output"]))
    precondition(reducer.task.stage == "进行中" && reducer.task.completedCalls.count == 1)
    reducer.consume(event("plan_updated", ["plan": [["step": "分析", "status": "completed"], ["step": "验证", "status": "in_progress"]]]))
    precondition(reducer.task.progress == 0.5 && reducer.task.detail == "验证")
    reducer.consume(event("task_complete", ["turn_id": "old-turn"]))
    precondition(reducer.task.active)
    reducer.consume(event("task_complete", ["turn_id": "turn1", "completed_at": 1792940460]))
    precondition(!reducer.task.active && reducer.task.stage == "已完成")
    precondition(workElapsed(reducer.task, now: Date()) == "1分 0秒")
    reducer.consume(event("task_started", ["turn_id": "turn2"]))
    precondition(reducer.task.progress == nil && reducer.task.detail.isEmpty)
    reducer.consume(event("turn_aborted", ["turn_id": "turn2"]))
    precondition(!reducer.task.active && reducer.task.stage == "已中断")
    print("PASS: work lifecycle, public progress only, tool state, explicit plan, stale turn isolation, completion and interruption")
}

@MainActor func runWorkTrackerTest(directory: String) {
    let root = URL(fileURLWithPath: directory)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let log = root.appendingPathComponent("rollout-fixture.jsonl")
    let index = root.appendingPathComponent("index.jsonl")
    try! Data("{\"id\":\"fixture\",\"thread_name\":\"验证实时进度\"}\n".utf8).write(to: index)
    try! Data().write(to: log)
    func record(_ type: String, _ payload: [String: Any]) -> Data {
        var data = try! JSONSerialization.data(withJSONObject: ["timestamp": ISO8601DateFormatter().string(from: Date()), "type": type, "payload": payload]); data.append(10); return data
    }
    func append(_ data: Data) { let handle = try! FileHandle(forWritingTo: log); try! handle.seekToEnd(); try! handle.write(contentsOf: data); try! handle.close() }
    append(record("session_meta", ["id": "fixture"]))
    append(record("event_msg", ["type": "task_started", "turn_id": "t1", "started_at": Date().timeIntervalSince1970]))
    var phase = 0
    let tracker = WorkProgressTracker(root: root, index: index) { overview in
        switch phase {
        case 0 where overview.state == .running:
            precondition(overview.tasks.first?.title == "验证实时进度")
            phase = 1
            let data = record("response_item", ["type": "custom_tool_call", "call_id": "c1", "name": "functions.exec"])
            append(data.prefix(data.count / 2))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { append(data.suffix(data.count - data.count / 2)) }
        case 1 where overview.tasks.first?.stage == "执行工具":
            print("PASS: incremental watcher follows real file appends and waits for complete JSON lines")
            phase = 2
            append(record("response_item", ["type": "custom_tool_call_output", "call_id": "c1"]))
            append(record("event_msg", ["type": "task_complete", "turn_id": "t1", "completed_at": Date().timeIntervalSince1970]))
        case 2 where overview.state == .idle:
            precondition(overview.activeCount == 0 && overview.tasks.first?.stage == "已完成")
            print("PASS: completion changes running work to idle and stops the task timer")
            exit(0)
        default: break
        }
    }
    tracker.setEnabled(true)
    RunLoop.main.run(until: Date().addingTimeInterval(16))
    fputs("FAIL: work tracker test timed out at phase \(phase)\n", stderr); exit(1)
}

@MainActor func probeLiveWork() {
    let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
    let tracker = WorkProgressTracker(root: home.appendingPathComponent("sessions"), index: home.appendingPathComponent("session_index.jsonl")) { overview in
        if overview.state == .running || overview.state == .idle {
            print("PASS: live local work read: \(overview.label), latest stage: \(overview.tasks.first?.stage ?? "none")")
            exit(0)
        }
        if overview.state == .unavailable { fputs("FAIL: no readable local session records\n", stderr); exit(1) }
    }
    tracker.setEnabled(true)
    RunLoop.main.run(until: Date().addingTimeInterval(15))
    fputs("FAIL: work tracker probe timed out\n", stderr); exit(1)
}
