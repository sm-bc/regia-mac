// Disegna l'icona di Regia (1024x1024) e la salva come PNG.
import AppKit
let lato: CGFloat = 1024
let img = NSImage(size: NSSize(width: lato, height: lato))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let forma = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.22, alpha: 1),
                    NSColor(calibratedRed: 0.20, green: 0.28, blue: 0.62, alpha: 1)])!.draw(in: forma, angle: -90)
// Tre cursori da "regia" (mixer)
let colori: [NSColor] = [.systemTeal, .systemGreen, .systemOrange]
let altezze: [CGFloat] = [0.62, 0.38, 0.72]
for i in 0..<3 {
    let x = 300 + CGFloat(i) * 212
    let binario = NSBezierPath(roundedRect: NSRect(x: x - 14, y: 260, width: 28, height: 504), xRadius: 14, yRadius: 14)
    NSColor.white.withAlphaComponent(0.22).setFill(); binario.fill()
    let y = 260 + 504 * altezze[i]
    let pomello = NSBezierPath(roundedRect: NSRect(x: x - 70, y: y - 38, width: 140, height: 76), xRadius: 24, yRadius: 24)
    colori[i].setFill(); pomello.fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
