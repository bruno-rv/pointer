import Darwin
import Foundation
import PointerAppKit

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--benchmark-gestures") {
    guard arguments == ["--benchmark-gestures", "--format", "json"] else {
        fputs("Pointer: usage: Pointer --benchmark-gestures --format json\n", stderr)
        exit(EXIT_FAILURE)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(GestureBenchmark.run())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        fputs("Pointer: could not encode gesture benchmark report: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else if arguments.contains("--smoke") {
    let formatIndex = arguments.firstIndex(of: "--format")
    guard let formatIndex,
          formatIndex + 1 < arguments.count,
          arguments[formatIndex + 1] == "json" else {
        fputs("Pointer: smoke mode requires --format json\n", stderr)
        exit(EXIT_FAILURE)
    }

    var displays: [SmokeRunner.Display] = []
    var index = 0
    while index < arguments.count {
        if arguments[index] == "--display" {
            let valueIndex = index + 1
            guard valueIndex < arguments.count,
                  let display = SmokeRunner.Display(rawValue: arguments[valueIndex]) else {
                fputs("Pointer: --display requires built-in or external\n", stderr)
                exit(EXIT_FAILURE)
            }
            displays.append(display)
            index += 2
        } else {
            index += 1
        }
    }
    if displays.isEmpty {
        displays = SmokeRunner.defaultDisplays
    }

    do {
        let data = try SmokeRunner.json(displays: displays)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        fputs("Pointer: could not encode smoke report: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else {
    MainActor.assumeIsolated {
        let application = PointerApplication.shared as! PointerApplication
        let controller = PointerApplicationController()
        application.commandRouter = controller.commandRouter
        application.delegate = controller
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
