import Foundation

/// Atalhos de DEBUG (`-debugScreen`, fakes `debug*`, `skipOnboarding`) lidos das preferências.
/// Quando o processo é o host de testes (XCTest), tudo fica desligado: a suíte não abre telas nem usa fakes
/// de sobra gravados no simulador.
enum DebugFlags {
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func string(_ key: String) -> String? {
        #if DEBUG
        isTestHost ? nil : UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }

    static func bool(_ key: String) -> Bool {
        #if DEBUG
        !isTestHost && UserDefaults.standard.bool(forKey: key)
        #else
        false
        #endif
    }

    static func double(_ key: String) -> Double {
        #if DEBUG
        isTestHost ? 0 : UserDefaults.standard.double(forKey: key)
        #else
        0
        #endif
    }

    static func has(_ argument: String) -> Bool {
        #if DEBUG
        !isTestHost && ProcessInfo.processInfo.arguments.contains(argument)
        #else
        false
        #endif
    }
}
