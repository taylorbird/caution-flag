// Launches Cool-Down in a demo mode and screenshots only its floating window.
// Usage: swift scripts/snap-demo.swift <app-binary> <warm|hot|breathing|onboarding|settings> <out.png>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: snap-demo <binary> <mode> <out.png>"); exit(2) }
let app = Process()
app.executableURL = URL(fileURLWithPath: args[1])
app.arguments = ["-demo", args[2]]
try app.run()
defer { app.terminate() }

var windowID: Int?
for _ in 0..<40 {
    Thread.sleep(forTimeInterval: 0.25)
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier }
    if let w = mine.first(where: { (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 30 }) {
        windowID = w[kCGWindowNumber as String] as? Int
        break
    }
}
guard let windowID else { print("no window appeared"); app.terminate(); exit(1) }
Thread.sleep(forTimeInterval: 0.8) // let the fade-in finish
let shot = Process()
shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
shot.arguments = ["-x", "-o", "-l", String(windowID), args[3]]
try shot.run()
shot.waitUntilExit()
print("saved \(args[3])")
