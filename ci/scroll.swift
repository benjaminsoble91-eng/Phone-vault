// CI helper: move the pointer to a point and send mouse-wheel scroll events there.
// usage: swift ci/scroll.swift <x> <y> <lines per event> <event count>
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count == 5, let x = Double(a[1]), let y = Double(a[2]), let dy = Int32(a[3]), let n = Int(a[4]) else {
    print("usage: scroll <x> <y> <dy> <count>")
    exit(2)
}
let point = CGPoint(x: x, y: y)
if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
    move.post(tap: .cghidEventTap)
}
usleep(300_000)
for _ in 0..<n {
    if let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) {
        e.location = point
        e.post(tap: .cghidEventTap)
    }
    usleep(25_000)
}
usleep(400_000)
print("sent \(n) scroll events of \(dy) at \(x),\(y)")
