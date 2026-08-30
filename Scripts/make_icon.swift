// Disegna l'icona di Aurora e ne scrive l'iconset PNG.
// Uso: swift Scripts/make_icon.swift <cartella-iconset>
//
// L'icona è tenuta come codice, non come immagine: così un colore si cambia
// leggendo una riga, e ogni misura resta espressa nella griglia di Apple
// (arte di 824 punti dentro una tela di 1024).

import AppKit
import Foundation

// MARK: - Forma

/// La superellisse |x/a|^n + |y/b|^n = 1: è la forma degli angoli continui che
/// macOS usa per le icone, dove un rettangolo arrotondato normale si vede.
func squircle(in rect: NSRect, exponent n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        step == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.close()
    return path
}

func bar(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, in art: NSRect) -> NSBezierPath {
    let rect = NSRect(x: art.minX + x, y: art.maxY - top - height, width: width, height: height)
    return NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
}

/// Il contorno di un carattere, preso da un font e riportato dentro `box`.
///
/// Il font si nomina per esteso invece di chiedere "quello di sistema": il
/// carattere di sistema Apple lo ridisegna fra una versione di macOS e l'altra,
/// e l'icona viene rigenerata a ogni build pulita — la CI parte sempre da un
/// checkout vuoto. Un font con un nome proprio, invece, è lo stesso ovunque.
///
/// Se non c'è, meglio fermarsi che disegnare in silenzio una lettera diversa da
/// quella decisa.
func glyphPath(_ character: Character, font name: String, fitting box: NSRect) -> CGPath {
    let font = CTFontCreateWithName(name as CFString, 256, nil)
    let actual = CTFontCopyPostScriptName(font) as String
    guard actual == name else {
        fatalError("Il font \(name) non è installato (ho ottenuto \(actual)).")
    }

    var characters = Array(String(character).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
          let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        fatalError("Il font \(name) non ha un glifo per '\(character)'.")
    }

    // Si riquadra sull'ingombro reale del disegno, non sulle metriche del font:
    // quelle lasciano attorno lo spazio che serve al testo corrente, e qui
    // farebbero galleggiare la lettera in mezzo a un margine invisibile.
    let bounds = path.boundingBoxOfPath
    let scale = min(box.width / bounds.width, box.height / bounds.height)
    var transform = CGAffineTransform.identity
        .translatedBy(x: box.midX, y: box.midY)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
    return path.copy(using: &transform) ?? path
}

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// MARK: - Disegno

// MARK: - Tavolozza

// L'aurora del mattino invece di quella boreale: base bianca appena scaldata,
// e il colore speso tutto sul titolo. Su una base chiara la gerarchia non può
// venire dal contrasto col fondo — è quasi nullo per tutti — quindi viene dalla
// saturazione: il titolo è pieno, le righe di testo sono la stessa tinta diluita.

/// La carta: bianca in alto, crema appena percettibile in basso.
let paper = NSGradient(colors: [rgb(0xFFFFFF), rgb(0xFFF7EE), rgb(0xFDEEDF)],
                       atLocations: [0, 0.55, 1], colorSpace: .sRGB)!

/// La lettera: arancio pieno che vira al terra bruciata, da sinistra a destra.
let ink = NSGradient(colors: [rgb(0xF2970D), rgb(0xCE4E0D)],
                     atLocations: [0, 1], colorSpace: .sRGB)!

/// La lettera.
///
/// Courier New neretto è uno slab da macchina da scrivere già tondeggiante di
/// suo: la A ha la testa piatta col trattino sopra, e i terminali sono curvi
/// invece che tagliati. Fra i caratteri che macOS include di serie è l'unico
/// che abbia insieme le due cose — Rockwell ha il trattino ma è geometrico e
/// spigoloso, e uno slab arrotondato di sistema non esiste.
let letterFont = "CourierNewPS-BoldMT"

/// Le righe della pagina, e il filo di bordo che dà un margine alla forma bianca:
/// senza, su una finestra chiara l'icona non avrebbe contorno.
let paperRule = NSColor(srgbRed: 0.98, green: 0.55, blue: 0.19, alpha: 0.22)
let edge = NSColor(srgbRed: 0.72, green: 0.42, blue: 0.16, alpha: 0.16)

func draw(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Non riesco a creare la tela \(pixels)×\(pixels)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let unit = size / 1024                       // la griglia di Apple, in scala
    let side = 824 * unit
    let art = NSRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side)
    let shape = squircle(in: art)

    // L'ombra si disegna riempiendo la forma piena: un gradiente dentro una
    // maschera non ne proietterebbe alcuna. Su una forma bianca serve più che
    // mai: è tutto ciò che la stacca da uno sfondo chiaro.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 26 * unit
    shadow.shadowColor = NSColor(srgbRed: 0.35, green: 0.20, blue: 0.05, alpha: 0.26)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    paper.draw(in: shape, angle: 265)

    // Il bordo: mezzo tratto, perché la clip taglia la metà esterna e resta un
    // filo netto invece di una sbavatura fuori sagoma.
    NSGraphicsContext.saveGraphicsState()
    shape.setClip()
    shape.lineWidth = 7 * unit
    edge.setStroke()
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Le righe della pagina, dietro alla lettera. Sono regolari e a tutta
    // larghezza, non tre lunghezze diverse come prima: quello che passa dietro
    // alla A ne esce spezzato, e solo un ritmo regolare fa leggere i frammenti
    // come righe di un foglio invece che come sbavature. Il tono scende molto,
    // perché due segni forti sullo stesso quadrato si contendono l'occhio e non
    // ne vince nessuno.
    //
    // Per la sola lettera, senza foglio, basta togliere questo ciclo.
    paperRule.setFill()
    for step in 0..<4 {
        let top = (0.300 + CGFloat(step) * 0.135) * side
        bar(x: 0.150 * side, top: top, width: 0.700 * side, height: 0.048 * side, in: art).fill()
    }

    // La A sopra a tutto. L'alone bianco è ciò che la stacca dalle righe che
    // le passano dietro: senza, i due arancioni si toccherebbero e il profilo
    // della lettera si perderebbe proprio dove si incrociano. Si ottiene
    // ripassando il contorno del glifo con un tratto largo: la metà che cade
    // dentro la lettera sparirà sotto il riempimento.
    // Il riquadro è centrato sul quadrato: larghezza 0.60 a partire da 0.20
    // lascia lo stesso margine ai due lati, e altezza 0.605 che finisce a 0.805
    // comincia a 0.200 — sopra e sotto uguali.
    let letterBox = NSRect(x: art.minX + 0.20 * side, y: art.maxY - 0.805 * side,
                           width: 0.60 * side, height: 0.605 * side)
    let letter = glyphPath("A", font: letterFont, fitting: letterBox)
    let halo = letter.copy(strokingWithWidth: 0.052 * side,
                           lineCap: .round, lineJoin: .round, miterLimit: 10)

    let cg = context.cgContext
    cg.saveGState()
    cg.addPath(halo)
    cg.setFillColor(NSColor(srgbRed: 1, green: 0.992, blue: 0.980, alpha: 1).cgColor)
    cg.fillPath()
    cg.addPath(letter)
    cg.clip()
    ink.draw(in: art, angle: 0)
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Scrittura dell'iconset

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("Uso: swift make_icon.swift <cartella-iconset>\n".data(using: .utf8)!)
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: folder)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

// Le dieci misure che iconutil si aspetta: ogni punto a densità singola e doppia.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = draw(size: CGFloat(points * scale))
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("Non riesco a codificare il PNG \(points)@\(scale)x")
        }
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(points)x\(points)\(suffix).png"
        try png.write(to: folder.appendingPathComponent(name))
    }
}
print("Iconset scritto in \(folder.path)")
