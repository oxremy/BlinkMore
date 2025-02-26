//
//  EyeTrackingService.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import Combine
import AVFoundation
import Vision
import CoreML
import AppKit

class EyeTrackingService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isEyeOpen: Bool = false
    @Published var isActive: Bool = false
    
    // These properties are still needed for internal state tracking, but not labeled as debug
    private var faceDetected: Bool = false
    private var multipleFacesDetected: Bool = false
    private var eyesVisible: Bool = false
    
    // Video capture properties
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var processingQueue = DispatchQueue(label: "com.oxremy.blinkmore.videoprocessing", qos: .userInitiated)
    
    // Image caching to limit memory usage
    private var currentFrameBuffer: CVPixelBuffer?
    private var currentFrameCIImage: CIImage?
    
    // Frame processing control
    private var frameCount: Int = 0
    private let frameSkip: Int = 2 // Process every nth frame (for efficiency)
    
    // Vision requests
    private lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest(completionHandler: self.handleFaceDetection)
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()
    
    private lazy var faceLandmarksRequest: VNDetectFaceLandmarksRequest = {
        let request = VNDetectFaceLandmarksRequest(completionHandler: self.handleFaceLandmarks)
        return request
    }()
    
    // Temporal smoothing
    private var recentEyeStates: [Double] = []
    private let smoothingWindowSize = Constants.temporalSmoothingFrameCount
    
    // Temporary eye state simulation (until real ML model)
    private var lastEyeStateChangeTime = Date()
    private var simulatedEyeState: Double = 0.0 // 0 = closed, 1 = open
    
    private var permissionsService = PermissionsService.shared
    
    // Initialize the service
    override init() {
        super.init()
        
        setupVision()
        checkPermissionsAndSetupCamera()
    }
    
    // Check permissions before setting up camera
    private func checkPermissionsAndSetupCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            // Permission already granted, safe to setup
            setupCaptureSession()
        case .notDetermined:
            // Need to request permission first
            permissionsService.requestCameraAccess { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCaptureSession()
                    }
                } else {
                    print("Camera permission denied")
                }
            }
        case .denied, .restricted:
            // Permission denied, cannot proceed with camera
            print("Camera permission denied or restricted")
        @unknown default:
            print("Unknown camera permission status")
        }
    }
    
    // Start the eye tracking
    func startTracking() {
        // Verify permissions before starting
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            self.captureSession?.startRunning()
            isActive = true
        } else {
            // Try to request permissions again
            checkPermissionsAndSetupCamera()
        }
    }
    
    // Stop the eye tracking
    func stopTracking() {
        captureSession?.stopRunning()
        isActive = false
        isEyeOpen = false
    }
    
    // MARK: - Vision Setup
    
    private func setupVision() {
        // Vision requests are configured using lazy vars above
    }
    
    // MARK: - AVCapture Setup
    
    private func setupCaptureSession() {
        // Run setup on a background queue to not block the UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create capture session
            let session = AVCaptureSession()
            session.sessionPreset = .medium // Balance between quality and performance
            
            // Verify camera permission once more before trying to access
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                print("Camera permissions not authorized, cannot setup capture session")
                return
            }
            
            // Find front camera
            guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("No front camera available")
                return
            }
            
            // Create device input
            do {
                let input = try AVCaptureDeviceInput(device: frontCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print("Error setting up camera input: \(error.localizedDescription)")
                return
            }
            
            // Create and configure video output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            
            // Save references
            self.captureSession = session
            self.videoOutput = videoOutput
            
            // Don't automatically start session - let the caller decide when to start
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip frames for efficiency
        frameCount += 1
        guard frameCount % frameSkip == 0 else { return }
        
        // Get pixel buffer from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Store current frame for later processing
        currentFrameBuffer = pixelBuffer
        currentFrameCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Process the frame
        processVideoFrame(pixelBuffer)
    }
    
    // MARK: - Video Frame Processing
    
    private func processVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            // Run face detection request
            try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
            print("Failed to perform face detection: \(error.localizedDescription)")
            updateEyeState(isOpen: false)
        }
    }
    
    // MARK: - Vision Request Handlers
    
    private func handleFaceDetection(request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Face detection error: \(error!.localizedDescription)")
            DispatchQueue.main.async {
                self.faceDetected = false
                self.multipleFacesDetected = false
                self.updateEyeState(isOpen: false)
            }
            return
        }
        
        guard let observations = request.results as? [VNFaceObservation] else { return }
        
        DispatchQueue.main.async {
            // Check if exactly one face is detected
            if observations.count == 1 {
                self.faceDetected = true
                self.multipleFacesDetected = false
                
                // Process face landmarks
                if let face = observations.first {
                    // Process the face landmarks in the original image
                    let faceLandmarksRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
                        self?.handleFaceLandmarks(request: request, error: error)
                    }
                    
                    // Process the landmarks request on the same image
                    let handler = VNImageRequestHandler(cvPixelBuffer: self.currentFrameBuffer!, orientation: .up, options: [:])
                    try? handler.perform([faceLandmarksRequest])
                }
            } else if observations.count > 1 {
                self.faceDetected = true
                self.multipleFacesDetected = true
                self.eyesVisible = false
                self.updateEyeState(isOpen: false)
            } else {
                self.faceDetected = false
                self.multipleFacesDetected = false
                self.eyesVisible = false
                self.updateEyeState(isOpen: false)
            }
        }
    }
    
    private func handleFaceLandmarks(request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Landmark detection error: \(error!.localizedDescription)")
            DispatchQueue.main.async {
                self.eyesVisible = false
                self.updateEyeState(isOpen: false)
            }
            return
        }
        
        guard let observations = request.results as? [VNFaceObservation],
              let face = observations.first,
              let landmarks = face.landmarks else {
            DispatchQueue.main.async {
                self.eyesVisible = false
                self.updateEyeState(isOpen: false)
            }
            return
        }
        
        // Check if eyes are visible
        let eyesAreVisible = landmarks.leftEye != nil && landmarks.rightEye != nil
        
        // Extract eye regions if eyes are visible
        var leftEyeImage: CGImage?
        var rightEyeImage: CGImage?
        
        if eyesAreVisible {
            // Extract eye regions from the current frame
            if let ciImage = currentFrameCIImage {
                // Extract eye regions directly without collecting for debug
                leftEyeImage = extractEyeRegion(from: ciImage, faceBounds: face.boundingBox, eyePoints: landmarks.leftEye!.normalizedPoints)
                rightEyeImage = extractEyeRegion(from: ciImage, faceBounds: face.boundingBox, eyePoints: landmarks.rightEye!.normalizedPoints)
            }
        }
        
        DispatchQueue.main.async {
            self.eyesVisible = eyesAreVisible && (leftEyeImage != nil || rightEyeImage != nil)
            
            if self.eyesVisible {
                // For now, use the temporary model logic until we integrate a real CoreML model
                // In a future implementation, this would pass eye images to a CoreML model
                let isOpen = self.detectEyeStateTemporary()
                self.updateEyeState(isOpen: isOpen)
            } else {
                self.updateEyeState(isOpen: false)
            }
        }
    }
    
    // MARK: - Eye Region Extraction
    
    private func extractEyeRegion(from image: CIImage, faceBounds: CGRect, eyePoints: [CGPoint]) -> CGImage? {
        // Calculate the eye region in the image
        let imageSize = image.extent.size
        
        // Eye points are normalized within face bounds, so we need to transform them to image coordinates
        guard let eyeRegion = calculateEyeRegion(faceBounds: faceBounds, eyePoints: eyePoints, imageSize: imageSize) else {
            return nil
        }
        
        // Create a crop rectangle with padding
        let cropRect = eyeRegion.insetBy(dx: -eyeRegion.width * 0.2, dy: -eyeRegion.height * 0.2)
        
        // Ensure crop rect is within image bounds
        let validCropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
        
        // Crop the eye region from the image
        let croppedImage = image.cropped(to: validCropRect)
        
        // Convert CIImage to CGImage
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else {
            return nil
        }
        
        return cgImage
    }
    
    private func calculateEyeRegion(faceBounds: CGRect, eyePoints: [CGPoint], imageSize: CGSize) -> CGRect? {
        // Transform normalized eye points to image coordinates
        let transformedPoints = eyePoints.map { point -> CGPoint in
            let x = faceBounds.origin.x + point.x * faceBounds.width
            let y = 1.0 - (faceBounds.origin.y + point.y * faceBounds.height) // Flip Y-coordinate
            return CGPoint(x: x * imageSize.width, y: y * imageSize.height)
        }
        
        guard !transformedPoints.isEmpty else { return nil }
        
        // Find the min/max X and Y coordinates to create a bounding box
        let minX = transformedPoints.map { $0.x }.min() ?? 0
        let maxX = transformedPoints.map { $0.x }.max() ?? 0
        let minY = transformedPoints.map { $0.y }.min() ?? 0
        let maxY = transformedPoints.map { $0.y }.max() ?? 0
        
        // Create a rect that bounds the eye
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // MARK: - Eye State Detection
    
    private func detectEyeStateTemporary() -> Bool {
        // Temporary implementation that outputs 0 by default, and every 10 seconds output changes to 1 for 5 seconds
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastEyeStateChangeTime)
        
        if simulatedEyeState == 0 && timeInterval >= 10.0 {
            // After 10 seconds of closed eyes, switch to open
            simulatedEyeState = 1.0
            lastEyeStateChangeTime = now
        } else if simulatedEyeState == 1 && timeInterval >= 5.0 {
            // After 5 seconds of open eyes, switch to closed
            simulatedEyeState = 0.0
            lastEyeStateChangeTime = now
        }
        
        // Return the eye state
        return simulatedEyeState > 0.5
    }
    
    // MARK: - Eye State Prediction with CoreML (Future implementation)
    
    private func detectEyeState(_ leftEyeImage: CGImage?, _ rightEyeImage: CGImage?) -> Bool {
        // This function would use a CoreML model to predict eye state
        // For now, we use the temporary implementation
        return detectEyeStateTemporary()
    }
    
    private func preprocessEyeImage(_ eyeImage: CGImage, targetSize: CGSize = CGSize(width: 64, height: 64)) -> CVPixelBuffer? {
        // This function would preprocess eye images for CoreML input
        // For future implementation
        return nil
    }
    
    private func updateEyeState(isOpen: Bool) {
        // Only dispatch to main thread if the state is actually changing
        if self.isEyeOpen != isOpen {
            DispatchQueue.main.async {
                self.isEyeOpen = isOpen
            }
        }
    }
    
    // MARK: - Prediction Smoothing
    
    private func smoothPrediction(_ isOpen: Bool) -> Bool {
        // Convert boolean to double
        let predictionValue = isOpen ? 1.0 : 0.0
        
        // Add to recent predictions
        recentEyeStates.append(predictionValue)
        
        // Keep only the last N predictions
        if recentEyeStates.count > smoothingWindowSize {
            recentEyeStates.removeFirst()
        }
        
        // If we don't have enough samples yet, just return the current prediction
        guard recentEyeStates.count == smoothingWindowSize else {
            return isOpen
        }
        
        // Calculate the average
        let average = recentEyeStates.reduce(0.0, +) / Double(recentEyeStates.count)
        
        // Consider the eye open if the average is greater than 0.5
        // This means that if majority of recent frames show open eyes, we consider it open
        return average > 0.5
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopTracking()
    }
} 