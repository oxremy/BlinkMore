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
import IOKit.ps

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
    // Fix QoS thread inversion by ensuring processingQueue uses the same QoS as the main thread
    private var processingQueue = DispatchQueue(label: "com.oxremy.blinkmore.videoprocessing", qos: .userInteractive)
    
    // Add a dedicated queue for Vision processing to avoid priority inversion
    private var visionQueue = DispatchQueue(label: "com.oxremy.blinkmore.visionprocessing", qos: .userInteractive, autoreleaseFrequency: .workItem)
    
    // Replace simple image caching with a proper buffer pool
    private let maxBufferPoolSize = 3
    private var pixelBufferPool: [CVPixelBuffer] = []
    private var ciImagePool: [CIImage] = []
    private var pixelBufferPoolLock = NSLock()
    private var ciImagePoolLock = NSLock()
    
    // Add back the direct reference properties for current frame data
    private var currentFrameBuffer: CVPixelBuffer?
    private var currentFrameCIImage: CIImage?
    
    // Frame processing control - Now adaptive based on CPU load and power state
    private var frameCount: Int = 0
    private var frameSkip: Int = 2 // Dynamic frame skipping - will adjust based on system load
    private var frameSkipAdjustmentCounter: Int = 0
    private let frameSkipAdjustmentInterval: Int = 30 // Check for adjustment every 30 frames processed
    
    // Reusable CIContext for image processing
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Power state tracking
    private var isOnBattery: Bool = false
    private var lastPowerCheckTime = Date()
    private let powerCheckInterval: TimeInterval = 30.0 // Check power state every 30 seconds
    
    // Batch UI updates to reduce thread switching
    private var pendingStateUpdates = [(String, Any)]()
    private var isStateUpdatePending = false
    private let stateUpdateDelay: TimeInterval = 0.1 // 100ms debounce for UI updates
    
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
    
    // Add region of interest tracking
    private var lastFaceRegion: CGRect?
    private var faceConfidence: Float = 0.0
    private var faceDetectionInterval: Int = 0
    private let maxFaceDetectionInterval: Int = 15 // Check full frame every 15 processed frames
    
    // Cache for previous face detection results
    private var lastFaceObservation: VNFaceObservation?
    private var lastFaceDetectionTime = Date()
    private let faceCacheDuration: TimeInterval = 0.1 // 100ms cache validity
    
    // Confidence thresholds for processing
    private let faceDetectionConfidenceThreshold: Float = 0.7
    private let landmarksConfidenceThreshold: Float = 0.8
    
    // Memory pressure monitoring
    private var isUnderMemoryPressure: Bool = false
    
    // Initialize the service
    override init() {
        super.init()
        
        setupVision()
        checkPowerState() // Initial power state check
        checkPermissionsAndSetupCamera()
        
        // Add memory pressure monitoring - fix notification name
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(didReceiveMemoryWarning), 
            name: NSApplication.didChangeScreenParametersNotification, // Using a standard macOS notification instead
            object: nil
        )
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
    
    // Check device power state (battery vs plugged in)
    private func checkPowerState() {
        // Don't check too frequently
        let now = Date()
        if now.timeIntervalSince(lastPowerCheckTime) < powerCheckInterval {
            return
        }
        
        lastPowerCheckTime = now
        
        let powerSourceInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo).takeRetainedValue()
        
        var batteryState = false
        
        // Fix conditional cast warning
        let sourcesList = powerSources as NSArray
        if sourcesList.count > 0 {
            let powerSource = sourcesList[0]
            if let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource as CFTypeRef).takeUnretainedValue() as? [String: Any],
               let isPlugged = description[kIOPSPowerSourceStateKey] as? String {
                batteryState = (isPlugged != kIOPSACPowerValue)
            }
        }
        
        if isOnBattery != batteryState {
            isOnBattery = batteryState
            adjustFrameSkipRate()
            print("Power state changed, now \(isOnBattery ? "on battery" : "plugged in")")
        }
    }
    
    // Dynamically adjust frame skip rate based on system load and power state
    private func adjustFrameSkipRate() {
        // When on battery, skip more frames to save power
        if isOnBattery {
            frameSkip = max(frameSkip, 3) // Skip at least every 3rd frame on battery
        } else {
            // Default frame skip rate when plugged in
            frameSkip = 2
        }
        
        // Fixed unused variable warning
        // Further adjust based on current CPU load - This is a simplified approach
        // A more sophisticated implementation would call host_processor_info to get actual CPU load
        let taskInfo = Thread.isMainThread ? 0.8 : 0.5 // Simplified load estimation
        
        // Adjust frame skip rate based on estimated load
        if taskInfo > 0.7 { // High load
            frameSkip = min(frameSkip + 1, 5) // Skip more frames, max 5
        } else if taskInfo < 0.3 && !isOnBattery && frameSkip > 1 { // Low load and plugged in
            frameSkip = max(frameSkip - 1, 1) // Skip fewer frames, min 1
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
        
        // Clean up resources when stopping
        clearBufferPools()
    }
    
    // MARK: - Vision Setup
    
    private func setupVision() {
        // Vision requests are configured using lazy vars above
    }
    
    // MARK: - AVCapture Setup
    
    private func setupCaptureSession() {
        // Run setup on a background queue to not block the UI
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            // Create capture session
            let session = AVCaptureSession()
            // Use lower resolution for better performance
            session.sessionPreset = .vga640x480 // Lower resolution but sufficient for eye detection
            
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
        // Use autoreleasepool to manage memory better
        autoreleasepool {
            // Periodically check power state and adjust frame skip rate
            frameSkipAdjustmentCounter += 1
            if frameSkipAdjustmentCounter >= frameSkipAdjustmentInterval {
                checkPowerState()
                adjustFrameSkipRate()
                frameSkipAdjustmentCounter = 0
            }
            
            // Skip frames for efficiency using dynamic frame skip rate
            frameCount += 1
            guard frameCount % frameSkip == 0 else { return }
            
            // Get pixel buffer from sample buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            // Store current frame in buffer pool and direct references
            storePixelBuffer(pixelBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            storeCIImage(ciImage)
            
            // Set direct references
            currentFrameBuffer = pixelBuffer
            currentFrameCIImage = ciImage
            
            // Process the frame
            processVideoFrame(pixelBuffer)
        }
    }
    
    // MARK: - Video Frame Processing
    
    private func processVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        // Skip processing if under memory pressure (more aggressively)
        if isUnderMemoryPressure && frameCount % (frameSkip * 2) != 0 {
            return
        }
        
        // Reuse cached face if detection was recent enough
        let now = Date()
        if let lastFace = lastFaceObservation, 
           now.timeIntervalSince(lastFaceDetectionTime) < faceCacheDuration {
            // Process the cached face for landmarks instead of doing full detection
            processFaceLandmarks(for: lastFace, in: pixelBuffer)
            return
        }
        
        // Determine if we should use region of interest or full frame
        let options: [VNImageOption: Any] = [:]
        let imageRequestHandler: VNImageRequestHandler
        
        // Skip full face detection if we have a recent face region
        if let _ = lastFaceRegion, faceConfidence > faceDetectionConfidenceThreshold, faceDetectionInterval < maxFaceDetectionInterval {
            // Processing with the last known face region
            faceDetectionInterval += 1
        } else {
            // Reset interval counter for full frame detection
            faceDetectionInterval = 0
        }
        
        // Create standard handler without regionOfInterest
        imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: options
        )
        
        // Perform the face detection request
        do {
            // Use the dedicated visionQueue to avoid QoS inversions
            visionQueue.async { [weak self] in
                guard let self = self else { return }
                do {
                    try imageRequestHandler.perform([self.faceDetectionRequest])
                } catch {
                    print("Failed to perform face detection: \(error.localizedDescription)")
                    self.scheduleStateUpdate(key: "isEyeOpen", value: false)
                }
            }
        } catch {
            print("Failed to set up face detection: \(error.localizedDescription)")
            scheduleStateUpdate(key: "isEyeOpen", value: false)
        }
    }
    
    // Process face landmarks using provided face observation
    private func processFaceLandmarks(for face: VNFaceObservation, in pixelBuffer: CVPixelBuffer) {
        // Create a request specifically for landmarks on the known face
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleFaceLandmarks(request: request, error: error)
        }
        
        // Create a handler without regionOfInterest as it's not supported in this context
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            try handler.perform([faceLandmarksRequest])
        } catch {
            print("Failed to process landmarks: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Vision Request Handlers
    
    private func handleFaceDetection(request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Face detection error: \(error!.localizedDescription)")
            scheduleStateUpdate(key: "faceDetected", value: false)
            scheduleStateUpdate(key: "multipleFacesDetected", value: false)
            scheduleStateUpdate(key: "isEyeOpen", value: false)
            
            // Clear the face region when detection fails
            lastFaceRegion = nil
            faceConfidence = 0.0
            lastFaceObservation = nil
            return
        }
        
        guard let observations = request.results as? [VNFaceObservation] else { return }
        
        // Update face detection time
        lastFaceDetectionTime = Date()
        
        // Batch state updates instead of multiple main thread dispatches
        if observations.count == 1 {
            if let observation = observations.first {
                // Cache the detected face for future frames
                lastFaceObservation = observation
                lastFaceRegion = observation.boundingBox
                faceConfidence = observation.confidence
                
                // Only process high-confidence faces
                if observation.confidence > faceDetectionConfidenceThreshold {
                    scheduleStateUpdate(key: "faceDetected", value: true)
                    scheduleStateUpdate(key: "multipleFacesDetected", value: false)
                    
                    // Process the face landmarks
                    if let currentBuffer = currentFrameBuffer {
                        processFaceLandmarks(for: observation, in: currentBuffer)
                    }
                } else {
                    // Low confidence face
                    scheduleStateUpdate(key: "faceDetected", value: false)
                    scheduleStateUpdate(key: "eyesVisible", value: false)
                    scheduleStateUpdate(key: "isEyeOpen", value: false)
                }
            }
        } else if observations.count > 1 {
            // Multiple faces detected
            scheduleStateUpdate(key: "faceDetected", value: true)
            scheduleStateUpdate(key: "multipleFacesDetected", value: true)
            scheduleStateUpdate(key: "eyesVisible", value: false)
            scheduleStateUpdate(key: "isEyeOpen", value: false)
            
            // Clear face region since we have multiple faces
            lastFaceRegion = nil
            faceConfidence = 0.0
            lastFaceObservation = nil
        } else {
            // No faces detected
            scheduleStateUpdate(key: "faceDetected", value: false)
            scheduleStateUpdate(key: "multipleFacesDetected", value: false)
            scheduleStateUpdate(key: "eyesVisible", value: false)
            scheduleStateUpdate(key: "isEyeOpen", value: false)
            
            // Clear face region
            lastFaceRegion = nil
            faceConfidence = 0.0
            lastFaceObservation = nil
        }
    }
    
    private func handleFaceLandmarks(request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Landmark detection error: \(error!.localizedDescription)")
            scheduleStateUpdate(key: "eyesVisible", value: false)
            scheduleStateUpdate(key: "isEyeOpen", value: false)
            return
        }
        
        guard let observations = request.results as? [VNFaceObservation],
              let face = observations.first,
              let landmarks = face.landmarks else {
            scheduleStateUpdate(key: "eyesVisible", value: false)
            scheduleStateUpdate(key: "isEyeOpen", value: false)
            return
        }
        
        // Check if landmarks have sufficient confidence
        let hasValidLeftEye = landmarks.leftEye != nil && face.confidence > landmarksConfidenceThreshold
        let hasValidRightEye = landmarks.rightEye != nil && face.confidence > landmarksConfidenceThreshold
        let eyesAreVisible = hasValidLeftEye || hasValidRightEye
        
        // Extract eye regions if eyes are visible
        var leftEyeImage: CGImage?
        var rightEyeImage: CGImage?
        
        if eyesAreVisible {
            // Extract eye regions from the current frame
            if let ciImage = currentFrameCIImage {
                // Only extract the eye(s) with sufficient confidence
                if hasValidLeftEye {
                    leftEyeImage = extractEyeRegion(from: ciImage, faceBounds: face.boundingBox, eyePoints: landmarks.leftEye!.normalizedPoints)
                }
                
                if hasValidRightEye {
                    rightEyeImage = extractEyeRegion(from: ciImage, faceBounds: face.boundingBox, eyePoints: landmarks.rightEye!.normalizedPoints)
                }
            }
        }
        
        let areEyesUsable = eyesAreVisible && (leftEyeImage != nil || rightEyeImage != nil)
        scheduleStateUpdate(key: "eyesVisible", value: areEyesUsable)
        
        if areEyesUsable {
            // For now, use the temporary model logic until we integrate a real CoreML model
            // In a future implementation, this would pass eye images to a CoreML model
            let isOpen = detectEyeStateTemporary()
            scheduleStateUpdate(key: "isEyeOpen", value: isOpen)
        } else {
            scheduleStateUpdate(key: "isEyeOpen", value: false)
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
        
        // Use the reusable CIContext for better performance
        guard let cgImage = ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
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
    
    // MARK: - Batched State Updates
    
    private func scheduleStateUpdate(key: String, value: Any) {
        pendingStateUpdates.append((key, value))
        
        if !isStateUpdatePending {
            isStateUpdatePending = true
            // Debounce updates to UI (only send updates every stateUpdateDelay ms)
            DispatchQueue.main.asyncAfter(deadline: .now() + stateUpdateDelay) { [weak self] in
                self?.applyPendingUpdates()
            }
        }
    }
    
    @objc private func applyPendingUpdates() {
        // Make a copy of the pending updates to avoid race conditions
        let updatesToApply = pendingStateUpdates
        pendingStateUpdates.removeAll()
        isStateUpdatePending = false
        
        // Apply all state updates in one batch on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for (key, value) in updatesToApply {
                switch key {
                case "faceDetected":
                    self.faceDetected = value as! Bool
                case "multipleFacesDetected":
                    self.multipleFacesDetected = value as! Bool
                case "eyesVisible":
                    self.eyesVisible = value as! Bool
                case "isEyeOpen":
                    // Only update published property if it's actually changing
                    if self.isEyeOpen != (value as! Bool) {
                        self.isEyeOpen = value as! Bool
                    }
                default:
                    break
                }
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
    
    @objc private func didReceiveMemoryWarning() {
        isUnderMemoryPressure = true
        
        // Clear cached resources using the pool cleanup method
        clearBufferPools()
        lastFaceObservation = nil
        
        // Increase frame skipping temporarily
        let oldFrameSkip = frameSkip
        frameSkip = min(frameSkip * 2, 8)
        
        // Reset after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.isUnderMemoryPressure = false
            self?.frameSkip = oldFrameSkip
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTracking()
        clearBufferPools()
    }
    
    // Thread-safe buffer management - updated to not use manual retain/release
    private func storePixelBuffer(_ buffer: CVPixelBuffer) {
        pixelBufferPoolLock.lock()
        defer { pixelBufferPoolLock.unlock() }
        
        // In modern Swift, we don't need to manually retain CoreFoundation objects
        // Swift handles memory management automatically
        
        // Manage pool size
        if pixelBufferPool.count >= maxBufferPoolSize {
            // Remove oldest buffer
            pixelBufferPool.removeFirst()
        }
        
        pixelBufferPool.append(buffer)
    }
    
    private func storeCIImage(_ image: CIImage) {
        ciImagePoolLock.lock()
        defer { ciImagePoolLock.unlock() }
        
        // Manage pool size
        if ciImagePool.count >= maxBufferPoolSize {
            // Remove oldest image
            ciImagePool.removeFirst()
        }
        
        ciImagePool.append(image)
    }
    
    // Updated to remove manual memory management
    private func clearBufferPools() {
        pixelBufferPoolLock.lock()
        pixelBufferPool.removeAll()
        pixelBufferPoolLock.unlock()
        
        ciImagePoolLock.lock()
        ciImagePool.removeAll()
        ciImagePoolLock.unlock()
        
        // Also clear direct references
        currentFrameBuffer = nil
        currentFrameCIImage = nil
    }
} 