import Foundation
import Darwin
import SystemConfiguration

let fm = FileManager.default
let identifier = "local.codexquota.mac"
func fail(_ message: String) -> Never { fputs("Codex Meter installer: \(message)\n", stderr); exit(1) }
func realDirectory(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
    return values.isDirectory == true && values.isSymbolicLink != true
}
func appVersion(_ url: URL) -> String? {
    guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
          let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
          info["CFBundleIdentifier"] as? String == identifier,
          info["CFBundleExecutable"] as? String == "CodexQuota" else { return nil }
    return info["CFBundleShortVersionString"] as? String
}
func sameItem(_ a: URL, _ b: URL) -> Bool {
    guard let left = try? fm.attributesOfItem(atPath: a.path), let right = try? fm.attributesOfItem(atPath: b.path),
          let inode = left[.systemFileNumber] as? NSNumber, let device = left[.systemNumber] as? NSNumber else { return a.standardizedFileURL == b.standardizedFileURL }
    return inode == right[.systemFileNumber] as? NSNumber && device == right[.systemNumber] as? NSNumber
}
let args = CommandLine.arguments
if args.count < 3 { fail("Expected prepare/finish and version") }
let mode = args[1], version = args[2]
let testing = args.count == 5 && args[3] == "--test-root"
let home: URL, applications: URL, owner: uid_t, group: gid_t
if testing {
    let root = URL(fileURLWithPath: args[4]).standardizedFileURL
    guard root.lastPathComponent.hasPrefix("codex-meter-installer-tests-"), root.path.hasPrefix("/private/tmp/") || root.path.hasPrefix("/tmp/") else { fail("Invalid test root") }
    home = root.appendingPathComponent("home"); applications = root.appendingPathComponent("Applications")
    owner = getuid(); group = getgid()
} else {
    guard geteuid() == 0 else { fail("Run through the macOS installer") }
    var uid: uid_t = 0, gid: gid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?, name != "loginwindow", uid > 0, let record = getpwuid(uid) else { fail("Install while a user is logged in") }
    home = URL(fileURLWithPath: String(cString: record.pointee.pw_dir))
    applications = URL(fileURLWithPath: "/Applications"); owner = uid; group = gid
}
let destination = applications.appendingPathComponent("Codex Meter.app")
let folders = [applications, home.appendingPathComponent("Applications")]
let apps = folders.filter(realDirectory).flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? [] }.filter { $0.pathExtension == "app" && appVersion($0) != nil }
if mode == "prepare" {
    if !testing {
        for app in apps {
            let binary = app.appendingPathComponent("Contents/MacOS/CodexQuota").path
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            p.arguments = ["-f", "^" + NSRegularExpression.escapedPattern(for: binary) + "($|[[:space:]])"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let pids = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }
            for pid in pids { _ = kill(pid, SIGTERM) }
            for _ in 0..<30 where pids.contains(where: { kill($0, 0) == 0 }) { Thread.sleep(forTimeInterval: 0.1) }
            for pid in pids where kill(pid, 0) == 0 {
                var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 && String(cString: buffer) == binary { _ = kill(pid, SIGKILL) }
            }
        }
    }
    print("Prepared existing Codex Meter instances for replacement")
} else if mode == "finish" {
    guard appVersion(destination) == version else { fail("New application was not installed correctly; old copies were preserved") }
    let trash = home.appendingPathComponent(".Trash")
    if !fm.fileExists(atPath: trash.path) {
        try fm.createDirectory(at: trash, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        if !testing && chown(trash.path, owner, group) != 0 { fail("Cannot set Trash ownership") }
    }
    guard realDirectory(trash) else { fail("Trash is not a normal directory; old copies were preserved") }
    for app in apps where !sameItem(app, destination) {
        guard let old = appVersion(app), old.compare(version, options: .numeric) != .orderedDescending else { continue }
        let target = trash.appendingPathComponent("\(app.deletingPathExtension().lastPathComponent) (旧版本 \(old) \(UUID().uuidString.prefix(8))).app")
        try fm.moveItem(at: app, to: target)
        print("Moved an older Codex Meter copy to the user's Trash")
    }
    print("Upgrade complete; account data and preferences were preserved")
} else { fail("Unknown installer stage") }
