import AppKit
import AVFoundation

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/NativeFixtures", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 480, height: 240))
image.lockFocus()
NSColor.systemTeal.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 480, height: 240)).fill()
("SpaceLens · Native Preview" as NSString).draw(at: NSPoint(x: 30, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.white])
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("Native.png"))
let pdf = NSMutableData()
let consumer = CGDataConsumer(data: pdf)!
var box = CGRect(x: 0, y: 0, width: 480, height: 240)
let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
context.beginPDFPage(nil)
context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.6, alpha: 1))
context.fill(box)
context.endPDFPage()
context.closePDF()
try (pdf as Data).write(to: directory.appendingPathComponent("Native.pdf"))

let videoURL = directory.appendingPathComponent("Native.mov")
// AVAssetWriter needs a new URL; refuse to overwrite a prior fixture.
if !FileManager.default.fileExists(atPath: videoURL.path) {
    let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<30 {
        let deadline = Date().addingTimeInterval(10)
        while !input.isReadyForMoreMediaData {
            if Date() > deadline { throw NSError(domain: "SpaceLensFixture", code: 1) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        var pixel: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel)
        let buffer = pixel!
        CVPixelBufferLockBaseAddress(buffer, [])
        let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<180 { for x in 0..<320 {
            let offset = y * stride + x * 4
            pointer[offset] = 255; pointer[offset + 1] = UInt8(frame * 8); pointer[offset + 2] = 150; pointer[offset + 3] = 180
        }}
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
    }
    input.markAsFinished()
    let completed = DispatchSemaphore(value: 0)
    writer.finishWriting { completed.signal() }
    guard completed.wait(timeout: .now() + 15) == .success, writer.status == .completed else { throw NSError(domain: "SpaceLensFixture", code: 2) }
}
var wav = Data()
func appendLE<T: FixedWidthInteger>(_ value: T) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
}
wav.append(Data("RIFF".utf8)); appendLE(UInt32(36 + 44100 * 2))
wav.append(Data("WAVEfmt ".utf8)); appendLE(UInt32(16))
appendLE(UInt16(1)); appendLE(UInt16(1)); appendLE(UInt32(44100))
appendLE(UInt32(88200)); appendLE(UInt16(2)); appendLE(UInt16(16))
wav.append(Data("data".utf8)); appendLE(UInt32(88200))
for i in 0..<44100 { appendLE(Int16(800 * sin(2 * Double.pi * 440 * Double(i) / 44100))) }
try wav.write(to: directory.appendingPathComponent("Native.wav"))
print("Native image/PDF/audio/video fixtures: \(directory.path)")
