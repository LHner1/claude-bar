import AppKit
import Darwin

/// Brings the terminal window/tab that hosts a Claude Code session to the front.
///
/// Strategy:
/// 1. Look up the session's controlling TTY and ask iTerm2 / Terminal.app (via AppleScript)
///    for the tab that owns it, then select that tab and raise its window.
/// 2. Otherwise walk up the process tree to the first GUI app (Ghostty, Warp, VS Code, Cursor,
///    JetBrains IDEs, the Claude desktop app …) and activate it.
enum WindowFocuser {
    @MainActor
    static func focus(_ session: ClaudeSession) -> Bool {
        // The TTY path goes into an AppleScript string, so only accept plain device names.
        if let tty = tty(of: session.pid), tty.range(of: #"^/dev/tty[A-Za-z0-9]+$"#, options: .regularExpression) != nil {
            if isRunning("com.googlecode.iterm2"), run(iTermScript(tty: tty)) { return true }
            if isRunning("com.apple.Terminal"), run(terminalScript(tty: tty)) { return true }
        }
        if let app = hostApp(of: session.pid) {
            return app.activate(options: [.activateAllWindows])
        }
        return false
    }

    /// Opens a session's working directory in Finder. Only real folders are opened – never app
    /// bundles or files – so a tampered session file can't make ClaudeBar launch something.
    @MainActor
    static func revealFolder(_ path: String) {
        var isDir: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
              !NSWorkspace.shared.isFilePackage(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    // MARK: - Process info

    private static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// Controlling terminal of the process or its closest ancestor, e.g. "/dev/ttys004".
    static func tty(of pid: pid_t) -> String? {
        var current = pid
        for _ in 0..<32 {
            guard let info = kinfo(current) else { return nil }
            let dev = info.kp_eproc.e_tdev
            if dev != -1, let name = devname(dev, S_IFCHR) {
                return "/dev/" + String(cString: name)
            }
            current = info.kp_eproc.e_ppid
            if current <= 1 { return nil }
        }
        return nil
    }

    private static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            guard let info = kinfo(current) else { return nil }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                return app
            }
            current = parent
        }
        return nil
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - AppleScript

    @MainActor
    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("ClaudeBar: AppleScript failed: \(error)") }
        return result?.booleanValue ?? false
    }

    private static func iTermScript(tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            tell t to select
                            tell s to select
                            tell w to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }
}
