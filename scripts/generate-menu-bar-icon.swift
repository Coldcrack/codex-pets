import AppKit
import CoreImage
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)
let sourceURL = resourcesDirectory.appendingPathComponent("MenuBarIconSource.png")
let outputURL = resourcesDirectory.appendingPathComponent("MenuBarIcon.png")

guard let sourceImage = CIImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "CodexPetsMenuBarIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing or invalid menu bar icon source at \(sourceURL.path)"]
    )
}

guard let inverted = CIFilter(
    name: "CIColorInvert",
    parameters: [kCIInputImageKey: sourceImage]
)?.outputImage,
let thresholded = CIFilter(
    name: "CIColorThreshold",
    parameters: [kCIInputImageKey: inverted, "inputThreshold": 0.5]
)?.outputImage,
let alphaMask = CIFilter(
    name: "CIMaskToAlpha",
    parameters: [kCIInputImageKey: thresholded]
)?.outputImage?.cropped(to: sourceImage.extent) else {
    throw NSError(
        domain: "CodexPetsMenuBarIcon",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create the menu bar template mask"]
    )
}

let context = CIContext(options: [.useSoftwareRenderer: false])
guard let cgImage = context.createCGImage(alphaMask, from: sourceImage.extent) else {
    throw NSError(
        domain: "CodexPetsMenuBarIcon",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Failed to render the menu bar template image"]
    )
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(
        domain: "CodexPetsMenuBarIcon",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Failed to encode the menu bar template image"]
    )
}

try pngData.write(to: outputURL, options: .atomic)
print("Generated \(outputURL.path)")
