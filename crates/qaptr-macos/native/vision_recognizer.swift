import CoreGraphics
import Foundation
import ImageIO
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(message.utf8))
    exit(2)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: vision-helper <ocr|vision> <image-path>\n")
}

let mode = CommandLine.arguments[1]
let path = CommandLine.arguments[2]
let url = URL(fileURLWithPath: path)
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("could not load image\n")
}

func run(_ requests: [VNRequest]) {
    do {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
    } catch {
        fail("Vision request failed: \(error.localizedDescription)\n")
    }
}

switch mode {
case "ocr":
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.01
    run([request])
    for observation in (request.results as? [VNRecognizedTextObservation] ?? []) {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let box = observation.boundingBox
        let encoded = Data(candidate.string.utf8).base64EncodedString()
        print("text\t\(encoded)\t\(candidate.confidence)\t\(box.origin.x)\t\(box.origin.y)\t\(box.size.width)\t\(box.size.height)")
    }
case "vision":
    let faceRequest = VNDetectFaceRectanglesRequest()
    let barcodeRequest = VNDetectBarcodesRequest()
    run([faceRequest, barcodeRequest])
    for observation in (faceRequest.results as? [VNFaceObservation] ?? []) {
        let box = observation.boundingBox
        print("face\t\(observation.confidence)\t\(box.origin.x)\t\(box.origin.y)\t\(box.size.width)\t\(box.size.height)")
    }

    for observation in (barcodeRequest.results as? [VNBarcodeObservation] ?? []) {
        let box = observation.boundingBox
        print("barcode\t\(observation.confidence)\t\(box.origin.x)\t\(box.origin.y)\t\(box.size.width)\t\(box.size.height)")
    }
default:
    fail("unknown mode\n")
}

print("ok")
