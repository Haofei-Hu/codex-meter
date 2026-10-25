import Foundation

@MainActor func runIntegrationTests(directory: String) {
    let root = URL(fileURLWithPath: directory)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let auth = root.appendingPathComponent("mock-account.json")
    let state = root.appendingPathComponent("account-state.json")
    let cli = root.appendingPathComponent("mock-codex.py")
    let log = root.appendingPathComponent("rpc-log.jsonl")
    let notification = root.appendingPathComponent("notify.json")
    for url in [log, notification] { try? FileManager.default.removeItem(at: url) }
    let script = #"""
#!/usr/bin/python3
import json,sys,time,pathlib,threading
root=pathlib.Path(__file__).parent
state_path=root/'account-state.json'
def load():
    try: return json.loads(state_path.read_text())
    except (FileNotFoundError,json.JSONDecodeError): return None
def watch():
    last=None
    while True:
        try:
            current=(root/'notify.json').read_text()
            if current!=last:
                last=current
                print(json.dumps({'method':'account/updated','params':json.loads(current)}),flush=True)
        except (FileNotFoundError,json.JSONDecodeError): pass
        time.sleep(.05)
threading.Thread(target=watch,daemon=True).start()
quota_calls=0
for line in sys.stdin:
    req=json.loads(line)
    method=req.get('method')
    with (root/'rpc-log.jsonl').open('a') as log: log.write(json.dumps({'method':method})+'\n')
    if 'id' not in req: continue
    state=load()
    if method=='initialize':
        print(json.dumps({'method':'account/updated','params':{'authMode':'chatgpt' if state else None}}),flush=True)
        result={}
    elif method=='account/read':
        result={'account':None if state is None else {'type':'chatgpt','email':state['email'],'planType':state['plan']}}
    elif method=='account/rateLimits/read':
        quota_calls+=1
        time.sleep(state.get('delay',0))
        bucket={'limitId':'codex','planType':state['plan'],'primary':{'usedPercent':state['used'],'windowDurationMins':300,'resetsAt':1793536107},'secondary':None}
        if 'weeklyUsed' in state and (not state.get('partial') or quota_calls>1):
            bucket['secondary']={'usedPercent':state['weeklyUsed'],'windowDurationMins':10080,'resetsAt':1793536107}
        result={'rateLimits':bucket,'rateLimitsByLimitId':{'codex':bucket}}
    else: result={}
    print(json.dumps({'id':req['id'],'result':result}),flush=True)
"""#
    try! script.write(to: cli, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
    var stamp = 0
    func write(_ value: [String: Any]?, authChanged: Bool = true) {
        let data = try! JSONSerialization.data(withJSONObject: value as Any? ?? NSNull(), options: [.fragmentsAllowed])
        try! data.write(to: state, options: .atomic)
        if authChanged {
            if value == nil { try? FileManager.default.removeItem(at: auth) }
            else { stamp += 1; try! Data("stamp-\(stamp)".utf8).write(to: auth, options: .atomic) }
        }
    }
    func notify(_ mode: Any) {
        try! JSONSerialization.data(withJSONObject: ["authMode": mode, "stamp": UUID().uuidString]).write(to: notification, options: .atomic)
    }
    func calls(_ method: String) -> Int {
        (try? String(contentsOf: log, encoding: .utf8))?.components(separatedBy: "\n").filter { $0.contains("\"method\": \"" + method + "\"") }.count ?? 0
    }
    write(["email": "plus@example.test", "plan": "plus", "used": 25, "weeklyUsed": 60])
    let suite = "local.codexquota.integration." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    let model = QuotaModel(executableOverride: cli.path, authURL: auth, preferences: preferences)
    var stage = 0
    model.onChange = {
        switch stage {
        case 0 where !model.loading && model.account?.email == "plus@example.test":
            precondition(model.rows.map { $0.window.remaining } == [75, 40])
            precondition(model.displayRows.map { $0.label } == ["5 小时额度", "每周额度"])
            print("PASS: Plus shows short-term above weekly quota")
            stage = 1; model.refresh()
        case 1 where !model.loading && model.account?.email == "plus@example.test":
            precondition(calls("initialize") == 1 && calls("account/read") == 1 && calls("account/rateLimits/read") == 2)
            print("PASS: quota refresh does not reread login")
            stage = 2; write(nil)
            // Writes to unrelated files used to keep postponing the debounce forever.
            for i in 0..<30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                    try! Data("log \(i)".utf8).write(to: root.appendingPathComponent("noise.log"))
                }
            }
        case 2 where model.waitingForLogin:
            precondition(model.rows.isEmpty && model.statusText == "等待登录" && model.account == nil)
            stage = -1
            let count = calls("account/rateLimits/read")
            model.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                precondition(calls("account/rateLimits/read") == count)
                print("PASS: filesystem logout works amid log writes; menu says waiting; requests stop")
                stage = 3
                write(["email": "partial-plus@example.test", "plan": "plus", "used": 7, "weeklyUsed": 20, "partial": true])
            }
        case 3 where !model.loading && model.account?.email == "partial-plus@example.test":
            precondition(model.displayRows.count == 2 && model.displayRows[1].window == nil)
            precondition(model.displayRows[0].remaining == 93)
            print("PASS: partial Plus payload preserves weekly row as unknown")
            stage = 4
        case 4 where !model.loading && model.rows.count == 2:
            precondition(model.rows.map { $0.window.remaining } == [93, 80])
            print("PASS: quota-only retry fills the missing weekly value")
            stage = -2
            model.setScale(0.1); precondition(model.desktopScale == 0.75)
            model.setScale(3); precondition(model.desktopScale == 1.6)
            model.setScale(1.25); precondition(preferences.double(forKey: "desktopScale") == 1.25)
            model.setHostRunning(false)
            let count = calls("account/rateLimits/read")
            model.refresh()
            precondition(model.statusText == "等待登录" && model.rows.isEmpty && calls("account/rateLimits/read") == count)
            print("PASS: closing host clears quota and shows waiting without requests")
            stage = 5; model.setHostRunning(true)
        case 5 where !model.loading && model.account?.email == "partial-plus@example.test" && model.rows.count == 2:
            stage = 6
            write(nil, authChanged: false); notify(NSNull())
        case 6 where model.waitingForLogin:
            precondition(model.rows.isEmpty)
            print("PASS: logout notification clears quota without a file change")
            stage = 7
            write(["email": "notification-plus@example.test", "plan": "plus", "used": 17, "weeklyUsed": 45], authChanged: false)
            notify("chatgpt")
        case 7 where !model.loading && model.account?.email == "notification-plus@example.test":
            precondition(model.rows.map { $0.window.remaining } == [83, 55])
            print("PASS: login notification resumes after logout without a file change")
            stage = 8
            write(["email": "delayed@example.test", "plan": "pro", "used": 99, "delay": 4])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                write(["email": "final-plus@example.test", "plan": "plus", "used": 2, "weeklyUsed": 12])
            }
        case 8 where !model.loading && model.account?.email == "final-plus@example.test":
            precondition(model.rows.map { $0.window.remaining } == [98, 88])
            stage = 9
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                precondition(model.account?.email == "final-plus@example.test")
                precondition(model.rows.map { $0.window.remaining } == [98, 88])
                print("PASS: rapid switch cannot restore delayed old-account data")
                model.disconnect(); preferences.removePersistentDomain(forName: suite); exit(0)
            }
        default: break
        }
    }
    model.start()
    RunLoop.main.run(until: Date().addingTimeInterval(35))
    fputs("FAIL: integration sequence timed out at stage \(stage)\n", stderr)
    model.disconnect(); exit(1)
}
