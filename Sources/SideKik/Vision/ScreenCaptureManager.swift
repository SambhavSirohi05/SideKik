import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import ImageIO

public struct ScreenCaptureResult: Sendable {
    public let imageBase64: String
    public let screenFrame: NSRect
    public let displayID: CGDirectDisplayID
    public let pixelWidth: Int
    public let pixelHeight: Int
}

/// Screen capture orchestrator using hardware-accelerated ScreenCaptureKit
public final class ScreenCaptureManager: Sendable {
    public static let shared = ScreenCaptureManager()

    private init() {}

    /// Captures the screen currently containing the mouse cursor
    public func captureActiveDisplay() async throws -> ScreenCaptureResult {
        // Find screen under mouse
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let currentScreen = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? screens.first else {
            throw NSError(domain: "ScreenCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active display found."])
        }

        // Extract display ID from NSScreen deviceDescription
        guard let displayIDNumber = currentScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw NSError(domain: "ScreenCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to retrieve display ID."])
        }
        let targetDisplayID = CGDirectDisplayID(displayIDNumber.uint32Value)

        // Query SCShareableContent
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == targetDisplayID }) ?? content.displays.first else {
            throw NSError(domain: "ScreenCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Matching SCDisplay not found."])
        }

        let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.scalesToFit = true

        // Capture frame in memory (< 15ms)
        let rawCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // Resize image to max 1280px maintaining aspect ratio
        let resizedImage = resizeCGImage(rawCGImage, maxDimension: 1280)

        // Compress to JPEG Data and Base64
        guard let jpegData = jpegDataFromCGImage(resizedImage, compressionQuality: 0.75) else {
            throw NSError(domain: "ScreenCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG buffer."])
        }

        let base64String = jpegData.base64EncodedString()

        return ScreenCaptureResult(
            imageBase64: base64String,
            screenFrame: currentScreen.frame,
            displayID: targetDisplayID,
            pixelWidth: resizedImage.width,
            pixelHeight: resizedImage.height
        )
    }

    private func resizeCGImage(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)

        if originalWidth <= maxDimension && originalHeight <= maxDimension {
            return image
        }

        let scale = min(maxDimension / originalWidth, maxDimension / originalHeight)
        let newWidth = Int(originalWidth * scale)
        let newHeight = Int(originalHeight * scale)

        guard let colorSpace = image.colorSpace,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private func jpegDataFromCGImage(_ image: CGImage, compressionQuality: CGFloat) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
}
