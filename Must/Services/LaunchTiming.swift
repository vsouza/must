import Darwin
import Foundation
import OSLog
import Synchronization

/// Tempo de arranque (prompt 18 · A.6), só em DEBUG: marca o início do processo, o `init` do App e o primeiro frame
/// da raiz. Loga no subsistema `dev.viniso.must`, categoria `launch` (`xcrun simctl spawn <udid> log stream --predicate 'category == "launch"'`).
enum LaunchTiming {
    #if DEBUG
    private static let logger = Logger(subsystem: Log.subsystem, category: "launch")
    private static let appInit = Date()
    private static let firstFrameDone = Mutex(false)

    /// Hora em que o processo começou (sysctl `kp_proc.p_starttime`); `nil` se o kernel não disser.
    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// Chamado no `init` do App (uma vez).
    static func appDidInit() {
        let since = processStart().map { Int(appInit.timeIntervalSince($0) * 1000) }
        logger.notice("init do App: \(since.map { "\($0) ms desde o processo" } ?? "processo sem horário", privacy: .public)")
    }

    /// Chamado no primeiro `onAppear` da raiz: quanto levou até a tela aparecer.
    static func firstFrame() {
        guard firstFrameDone.withLock({ done -> Bool in defer { done = true }; return !done }) else { return }
        let now = Date()
        let fromInit = Int(now.timeIntervalSince(appInit) * 1000)
        let fromProcess = processStart().map { Int(now.timeIntervalSince($0) * 1000) }
        logger.notice("primeiro frame: \(fromProcess.map { "\($0) ms desde o processo" } ?? "sem horário", privacy: .public) · \(fromInit) ms desde o init")
    }

    /// Marca livre (ex.: sincronização começou/terminou), com o tempo desde o init.
    static func mark(_ name: String) {
        logger.notice("\(name, privacy: .public) · \(Int(Date().timeIntervalSince(appInit) * 1000)) ms desde o init")
    }
    #else
    static func appDidInit() {}
    static func firstFrame() {}
    static func mark(_ name: String) {}
    #endif
}
