// Lifts the main subject of an image onto a transparent background with
// Vision (the same subject lifting as "Copy Subject" in Photos), at 1024×1024.
// Usage: swift scripts/cutout-subject.swift <input.png> <output.png>
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3,
      let image = NSImage(contentsOfFile: args[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: cutout-subject.swift <input.png> <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: cgImage)
try handler.perform([request])
guard let result = request.results?.first else {
    FileHandle.standardError.write("no subject found\n".data(using: .utf8)!)
    exit(1)
}
let masked = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)

let context = CIContext()
let source = CIImage(cvPixelBuffer: masked)
let scale = 1024 / source.extent.width
let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
guard let output = context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: 1024, height: 1024)) else { exit(1) }
let rep = NSBitmapImageRep(cgImage: output)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("subject: \(result.allInstances.count) instance(s)")
