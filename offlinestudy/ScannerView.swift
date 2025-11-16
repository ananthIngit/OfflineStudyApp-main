import SwiftUI
import VisionKit

struct ScannerView: UIViewControllerRepresentable {
    
    @Binding var scannedPage: ScannedPage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let documentViewController = VNDocumentCameraViewController()
        documentViewController.delegate = context.coordinator
        return documentViewController
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: ScannerView
        
        init(parent: ScannerView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            
            guard scan.pageCount > 0 else {
                self.parent.isPresented = false
                return
            }
            
            let originalImage = scan.imageOfPage(at: 0)
            let imageToProcess = originalImage.removeAlphaChannel()
            
            // 1. IMMEDIATELY DISMISS THE CAMERA (THE FIX FOR THE HANG)
            self.parent.isPresented = false
            
            print("--- Analyzing Page in Background ---")
            
            // 2. RUN ANALYSIS ASYNCHRONOUSLY
            StudyService.shared.analyze(image: imageToProcess) { result in
                
                // 3. Update the UI *only* when the result is ready
                DispatchQueue.main.async {
                    guard let result = result else {
                        print("❌ Analysis failed.")
                        return
                    }
                    
                    // This updates the main ContentView, showing the results.
                    self.parent.scannedPage = ScannedPage(image: imageToProcess, result: result)
                }
            }
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - HELPER EXTENSIONS (Add this to the bottom)

extension UIImage {
    func removeAlphaChannel() -> UIImage {
        guard let cgImage = self.cgImage, cgImage.alphaInfo != .none else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        return renderer.image { context in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
    }
    
    func cvPixelBuffer() -> CVPixelBuffer? {
        // This is the helper to convert a UIImage to the CVPixelBuffer
        // that your Create ML model needs (299x299 for ImageFeaturePrint)
        
        // 1. Resize to the model's input size
        let size = CGSize(width: 299, height: 299)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            299, // Model input width
            299, // Model input height
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData,
            width: 299,
            height: 299,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        
        context.translateBy(x: 0, y: 299)
        context.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context)
        context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 299, height: 299))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
}
