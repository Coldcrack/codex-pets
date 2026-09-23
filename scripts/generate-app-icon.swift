import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)
let sourceIconURL = resourcesDirectory.appendingPathComponent("AppIconSource.png")
let iconsetDirectory = resourcesDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesDirectory.appendingPathComponent("AppIcon.icns")

guard let sourceIcon = NSImage(contentsOf: sourceIconURL) else {
    throw NSError(
        domain: "CodexPetsIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing or invalid icon source at \(sourceIconURL.path)"]
    )
}

try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetDirectory)
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for iconFile in iconFiles {
    let image = makeIcon(pixelSize: iconFile.pixels)
    let destination = iconsetDirectory.appendingPathComponent(iconFile.name)
    try writePNG(image, to: destination)
}

try? FileManager.default.removeItem(at: icnsURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetDirectory.path,
    "-o",
    icnsURL.path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(
        domain: "CodexPetsIcon",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
    )
}

try? FileManager.default.removeItem(at: iconsetDirectory)

print("Generated \(icnsURL.path)")

func makeIcon(pixelSize: Int) -> NSImage {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let image = NSImage(size: size)
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    sourceIcon.draw(
        in: NSRect(origin: .zero, size: size),
        from: NSRect(origin: .zero, size: sourceIcon.size),
        operation: .copy,
        fraction: 1
    )

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "CodexPetsIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"]
        )
    }
    try pngData.write(to: url)
}
