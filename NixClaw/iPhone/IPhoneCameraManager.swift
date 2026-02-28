import AVFoundation
import UIKit

class IPhoneCameraManager: NSObject {
  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "iphone-camera-session")
  private let context = CIContext()
  private var isRunning = false
  private var currentDevice: AVCaptureDevice?

  var onFrameCaptured: ((UIImage) -> Void)?

  func start() {
    guard !isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.configureSession()
      self?.captureSession.startRunning()
      self?.isRunning = true
    }
  }

  func stop() {
    guard isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.captureSession.stopRunning()
      self?.isRunning = false
    }
  }

  func pauseCapture() {
    guard isRunning else { return }
    NSLog("[iPhoneCamera] Pausing capture for background")
    sessionQueue.async { [weak self] in
      self?.captureSession.stopRunning()
    }
  }

  func resumeCapture() {
    guard isRunning else { return }
    NSLog("[iPhoneCamera] Resuming capture from background")
    sessionQueue.async { [weak self] in
      self?.captureSession.startRunning()
    }
  }

  /// Tap to focus at a specific point (normalized 0-1 coordinates)
  func focusAt(point: CGPoint) {
    sessionQueue.async { [weak self] in
      guard let device = self?.currentDevice else { return }
      
      do {
        try device.lockForConfiguration()
        
        // Set focus point if supported
        if device.isFocusPointOfInterestSupported {
          device.focusPointOfInterest = point
          device.focusMode = .autoFocus
          NSLog("[iPhoneCamera] Focus point set to (%.2f, %.2f)", point.x, point.y)
        }
        
        // Set exposure point if supported
        if device.isExposurePointOfInterestSupported {
          device.exposurePointOfInterest = point
          device.exposureMode = .autoExpose
        }
        
        device.unlockForConfiguration()
      } catch {
        NSLog("[iPhoneCamera] Failed to set focus: %@", error.localizedDescription)
      }
    }
  }

  private func configureSession() {
    captureSession.beginConfiguration()
    
    // Use high quality preset for better image quality
    captureSession.sessionPreset = .high

    // Add back camera input with best available device
    guard let camera = getBestCamera(),
          let input = try? AVCaptureDeviceInput(device: camera) else {
      NSLog("[iPhoneCamera] Failed to access back camera")
      captureSession.commitConfiguration()
      return
    }

    currentDevice = camera

    if captureSession.canAddInput(input) {
      captureSession.addInput(input)
    }

    // Configure camera for optimal quality
    configureCameraSettings(device: camera)

    // Add video output
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true

    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }

    // Fix orientation to portrait
    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    }

    captureSession.commitConfiguration()
    NSLog("[iPhoneCamera] Session configured with high quality preset")
  }

  /// Get the best available back camera (prefer wide angle, then ultra-wide)
  private func getBestCamera() -> AVCaptureDevice? {
    // Prefer the standard wide-angle camera for best quality
    if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
      return device
    }
    // Fallback to any back camera
    return AVCaptureDevice.default(for: .video)
  }

  /// Configure camera for optimal image quality with continuous auto-focus and exposure
  private func configureCameraSettings(device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()

      // Enable continuous auto-focus for sharp images
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
        NSLog("[iPhoneCamera] Continuous auto-focus enabled")
      } else if device.isFocusModeSupported(.autoFocus) {
        device.focusMode = .autoFocus
        NSLog("[iPhoneCamera] Auto-focus enabled (continuous not supported)")
      }

      // Enable continuous auto-exposure for proper brightness
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
        NSLog("[iPhoneCamera] Continuous auto-exposure enabled")
      } else if device.isExposureModeSupported(.autoExpose) {
        device.exposureMode = .autoExpose
      }

      // Enable auto white balance
      if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
        device.whiteBalanceMode = .continuousAutoWhiteBalance
        NSLog("[iPhoneCamera] Continuous auto white balance enabled")
      }

      // Enable HDR if available for better dynamic range
      if device.activeFormat.isVideoHDRSupported {
        device.automaticallyAdjustsVideoHDREnabled = true
        NSLog("[iPhoneCamera] Auto HDR enabled")
      }

      // Low light boost if available
      if device.isLowLightBoostSupported {
        device.automaticallyEnablesLowLightBoostWhenAvailable = true
        NSLog("[iPhoneCamera] Low light boost enabled")
      }

      device.unlockForConfiguration()
    } catch {
      NSLog("[iPhoneCamera] Failed to configure camera settings: %@", error.localizedDescription)
    }
  }

  static func requestPermission() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default:
      return false
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension IPhoneCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    let image = UIImage(cgImage: cgImage)

    onFrameCaptured?(image)
  }
}
