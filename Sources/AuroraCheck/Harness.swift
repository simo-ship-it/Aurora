import Foundation

/// Un banco di prova essenziale.
///
/// Non è XCTest perché XCTest arriva con Xcode, mentre per compilare Aurora
/// bastano i Command Line Tools: legare le prove a Xcode significherebbe che
/// chi sviluppa l'app non può eseguirle.
enum Check {

    private(set) static var total = 0
    private(set) static var failures: [String] = []
    private static var suite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        suite = name
        body()
    }

    static func expect(_ condition: Bool, _ what: @autoclosure () -> String,
                       line: UInt = #line) {
        total += 1
        guard !condition else { return }
        failures.append("\(suite):\(line)  \(what())")
    }

    static func equal<T: Equatable>(_ got: T, _ want: T, _ what: @autoclosure () -> String,
                                    line: UInt = #line) {
        total += 1
        guard got != want else { return }
        failures.append("\(suite):\(line)  \(what()): atteso \(want), ottenuto \(got)")
    }

    static func report() -> Int32 {
        if failures.isEmpty {
            print("\(total) verifiche superate.")
            return 0
        }
        print("\(failures.count) verifiche fallite su \(total):")
        for failure in failures { print("  " + failure) }
        return 1
    }
}
