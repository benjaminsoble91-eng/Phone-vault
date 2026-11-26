// CI helper: synthetic mouse input for the launch test.
//   input scroll <x> <y> <lines per event> <event count>
//   input click  <x> <y>
import CoreGraphics
import Foundation

let a = CommandLine.arguments
func fail() -> Never { print("usage: input scroll x y dy n | input click x y"); exit(2) }
guard a.count >= 4, let x = Double(a[2]), let y = Double(a[3]) else { fail() }
let point = CGPoint(x: x, y: y)
if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
    move.post(tap: .cghidEventTap)
}
usleep(300_000)
if a[1] == "scroll" {
    guard a.count == 6, let dy = Int32(a[4]), let n = Int(a[5]) else { fail() }
    for _ in 0..<n {
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) {
            e.location = point
            e.post(tap: .cghidEventTap)
        }
        usleep(25_000)
    }
    print("scrolled \(n) x \(dy) at \(x),\(y)")
} else if a[1] == "click" {
    if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
       let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
    }
    print("clicked at \(x),\(y)")
} else {
    fail()
}
usleep(500_000)
