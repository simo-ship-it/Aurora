// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aurora",
    platforms: [.macOS(.v13)],
    targets: [
        // L'analisi del Markdown: solo Foundation, nessuna vista. Sta in un
        // modulo a parte perché possa essere verificata senza aprire una finestra.
        .target(name: "AuroraCore", path: "Sources/AuroraCore"),
        .executableTarget(name: "Aurora", dependencies: ["AuroraCore"], path: "Sources/Aurora"),
        // I test sono un eseguibile invece che un target di test perché XCTest
        // e swift-testing arrivano con Xcode, mentre per compilare Aurora
        // bastano i Command Line Tools: legarli a Xcode significherebbe che
        // sulla macchina di chi sviluppa i test non girano.
        .executableTarget(name: "AuroraCheck", dependencies: ["AuroraCore"], path: "Sources/AuroraCheck")
    ]
)
