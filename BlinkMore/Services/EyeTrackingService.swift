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
import AppKit

class EyeTrackingService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isEyeOpen: Bool = false
    @Published var isActive: Bool = false
    
    // Cached preference values
    private var cachedEARSensitivity: Double = Constants.defaultEARSensitivity
    private var cancellables = Set<AnyCancellable>()
    
    // Camera capture components
    private var captureSession: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let captureSessionQueue = DispatchQueue(label: "com.oxremy.blinkmore.capturesession", qos: .userInitiated)
    private let videoDataOutputQueue = DispatchQueue(label: "com.oxremy.blinkmore.videodata", qos: .userInitiated)
    
    // Vision request
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    
    // Frame skipping for performance
    private var frameCounter = 0
    private let frameProcessingInterval = 2 // Process every 2nd frame
    
    // Eye Aspect Ratio (EAR) threshold - use cached value instead of direct access
    private var earThreshold: Double {
        return cachedEARSensitivity
    }
    
    // State tracking properties to prevent race conditions
    private var isCleaningUp = false
    private var isStoppingTracking = false
    private var trackingStopTime: Date?
    
    // Reference to preferences service
    private let preferencesService = PreferencesService.shared
    
    override init() {
        super.init()
        faceLandmarksRequest.constellation = .constellation76Points // Use more detailed landmarks if available
        
        // Initialize cached values
        updateCachedPreferences()
    }
    
    deinit {
        print("EyeTrackingService being deinitialized")
        
        // Clean up cancellables
        cancellables.removeAll()
        
        // Avoid potential deadlock by checking thread and using appropriate approach
        if Thread.isMainThread {
            // Only clean up if not already cleaning up
            if !isCleaningUp {
                isCleaningUp = true
                self.cleanupResources() 
            }
        } else {
            // Never use sync in deinit - use async instead
            isCleaningUp = true
            DispatchQueue.main.async {
                self.cleanupResources()
            }
        }
        
        print("EyeTrackingService deinit complete")
    }
    
    private func cleanupResources() {
        // Track cleanup start time for logging
        let startTime = Date()
        print("Starting camera resource cleanup")
        
        // Stop tracking first if needed
        if let session = captureSession, session.isRunning {
            // Try to stop on the session's queue for thread safety
            captureSessionQueue.sync {
                session.stopRunning()
            }
            print("Stopped running capture session")
        }
        
        // Explicitly set sample buffer delegate to nil
        videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        
        // Force device unlocking in case it was locked for configuration
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           (try? device.lockForConfiguration()) != nil {
            device.unlockForConfiguration()
            print("Unlocked camera device configuration")
        }
        
        // Release references
        videoDataOutput = nil
        captureSession = nil
        
        print("Camera resources cleaned up - took \(Date().timeIntervalSince(startTime)) seconds")
    }
    
    // MARK: - Setup and Configuration
    
    func startTracking() {
        // Make sure we're not in the middle of stopping
        if isStoppingTracking {
            print("Cannot start tracking while stop is in progress - try again later")
            return
        }
        
        // Update cached preferences before starting
        updateCachedPreferences()
        
        // Set up preference change listeners
        setupPreferenceListeners()
        
        // Start the camera capture session on a background queue
        captureSessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Setup camera if not already configured
            if self.captureSession == nil {
                self.setupCameraCapture()
            }
            
            // Start the session if it's not running
            if let session = self.captureSession, !session.isRunning {
                session.startRunning()
                
                DispatchQueue.main.async {
                    self.isActive = true
                }
                
                print("Eye tracking started")
            }
        }
    }
    
    func stopTracking() {
        // Prevent multiple simultaneous stop calls
        if isStoppingTracking {
            print("Stop tracking already in progress, ignoring duplicate call")
            return
        }
        
        isStoppingTracking = true
        trackingStopTime = Date()
        
        // Clear preference listeners when stopping
        cancellables.removeAll()
        
        // Stop the capture session on the session queue
        captureSessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
                
                // Add a small delay to ensure AVFoundation has time to release resources
                Thread.sleep(forTimeInterval: 0.1)
                
                DispatchQueue.main.async {
                    self.isActive = false
                    self.isEyeOpen = false // Reset eye state
                    self.isStoppingTracking = false
                    if let stopTime = self.trackingStopTime {
                        print("Eye tracking stopped - took \(Date().timeIntervalSince(stopTime)) seconds")
                    } else {
                        print("Eye tracking stopped")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isStoppingTracking = false
                }
            }
        }
    }
    
    // Public method to force synchronous cleanup for app termination
    func prepareForTermination() {
        print("Preparing eye tracking for termination")
        // Cleanup resources synchronously
        if !isCleaningUp {
            isCleaningUp = true
            
            // Cancel any pending operations
            cancellables.removeAll()
            
            // Force stop on session queue
            captureSessionQueue.sync {
                if let session = self.captureSession, session.isRunning {
                    session.stopRunning()
                    Thread.sleep(forTimeInterval: 0.1) // Brief pause for cleanup
                }
                
                // Clean up on session queue to avoid threading issues
                self.videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
                self.videoDataOutput = nil
                self.captureSession = nil
            }
            
            print("Eye tracking termination preparation complete")
        }
    }
    
    private func setupCameraCapture() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium // Lower resolution for better performance
        
        // Find front camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Failed to access front camera")
            return
        }
        
        // Create input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                print("Failed to add camera input")
                return
            }
        } catch {
            print("Failed to create camera input: \(error.localizedDescription)")
            return
        }
        
        // Create and configure video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            // Get the connection and set video orientation
            if let connection = videoOutput.connection(with: .video) {
                // Handle both newer macOS 14+ and older versions
                if #available(macOS 14.0, *) {
                    // For macOS 14.0 and newer, use videoRotationAngle
                    connection.videoRotationAngle = 0 // 0 degrees = portrait
                } else {
                    // For older versions, use the deprecated videoOrientation
                    connection.videoOrientation = .portrait
                }
                connection.isEnabled = true
            }
            
            self.videoDataOutput = videoOutput
        } else {
            print("Failed to add video output")
            return
        }
        
        self.captureSession = session
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip frames for performance
        frameCounter += 1
        if frameCounter % frameProcessingInterval != 0 {
            return
        }
        
        // Convert sample buffer to pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Create a request handler with the pixel buffer
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            // Perform the face landmarks request
            try imageRequestHandler.perform([faceLandmarksRequest])
            
            // Process the results
            processVisionResults(faceLandmarksRequest)
        } catch {
            print("Failed to perform Vision request: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Vision Results Processing
    
    private func processVisionResults(_ request: VNRequest) {
        // Get the first face observation
        guard let observations = request.results as? [VNFaceObservation], 
              let faceObservation = observations.first else {
            pauseEyeTracking(reason: "No face detected")
            return
        }
        
        // Check if we have multiple faces - if so, pause tracking
        if observations.count > 1 {
            pauseEyeTracking(reason: "Multiple faces detected")
            return
        }
        
        // Check if we have landmarks
        guard let landmarks = faceObservation.landmarks else {
            pauseEyeTracking(reason: "No face landmarks detected")
            return
        }
        
        // Check if we have both eyes
        guard let leftEyeLandmarks = landmarks.leftEye, let rightEyeLandmarks = landmarks.rightEye else {
            pauseEyeTracking(reason: "Eyes not detected")
            return
        }
        
        // Get eye points
        let leftEyePoints = leftEyeLandmarks.normalizedPoints
        let rightEyePoints = rightEyeLandmarks.normalizedPoints
        
        // Calculate EAR for both eyes
        let leftEAR = calculateEAR(points: leftEyePoints)
        let rightEAR = calculateEAR(points: rightEyePoints)
        
        // Average the EAR values
        let avgEAR = (leftEAR + rightEAR) / 2.0
        
        // Determine if eyes are open based on EAR threshold
        let eyesOpen = avgEAR > earThreshold
        
        // Debug output occasionally
        if frameCounter % 30 == 0 {
            print("Left EAR: \(leftEAR), Right EAR: \(rightEAR), Average EAR: \(avgEAR), Eyes Open: \(eyesOpen)")
        }
        
        // Update eye state directly without temporal smoothing
        updateEyeState(eyesOpen)
    }
    
    // MARK: - Eye Aspect Ratio (EAR) calculation
    
    /// Calculate the Eye Aspect Ratio (EAR) from eye landmarks
    /// EAR = (h1 + h2) / (2 * w)
    /// where h1, h2 are the vertical distances between eye landmarks, and w is the horizontal distance
    private func calculateEAR(points: [CGPoint]) -> Double {
        guard points.count >= 6 else {
            print("Insufficient eye landmarks for EAR calculation")
            return 0.0
        }
        
        // The exact indices depend on the landmark constellation used
        // These are approximate for the standard eye landmarks
        // Adjust these indices if using a different landmark constellation
        
        // For vertical distances (height)
        let h1 = distanceBetween(points[1], points[5]) // Top to bottom landmarks
        let h2 = distanceBetween(points[2], points[4]) // Top to bottom landmarks
        
        // For horizontal distance (width)
        let w = distanceBetween(points[0], points[3]) // Corner to corner landmarks
        
        // Avoid division by zero
        guard w > 0 else { return 0.0 }
        
        // Calculate EAR
        let ear = (h1 + h2) / (2.0 * w)
        return ear
    }
    
    /// Calculate Euclidean distance between two points
    private func distanceBetween(_ point1: CGPoint, _ point2: CGPoint) -> Double {
        let xDiff = point2.x - point1.x
        let yDiff = point2.y - point1.y
        return sqrt(xDiff * xDiff + yDiff * yDiff)
    }
    
    private func updateEyeState(_ currentEyeState: Bool) {
        // Update published state on main thread if changed
        DispatchQueue.main.async { [weak self] in
            if self?.isEyeOpen != currentEyeState {
                self?.isEyeOpen = currentEyeState
                print("Eye state changed to: \(currentEyeState ? "OPEN" : "CLOSED")")
            }
        }
    }
    
    private func pauseEyeTracking(reason: String) {
        // Update published state on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Only log if we're changing from open to closed
            if self.isEyeOpen {
                print("Pausing eye tracking: \(reason)")
                self.isEyeOpen = false
            }
        }
    }
    
    // Method to update all cached preference values
    private func updateCachedPreferences() {
        cachedEARSensitivity = preferencesService.earSensitivity
        
        // Map numeric EAR value to human-readable sensitivity for logging
        let sensitivityLabel: String
        let range = Constants.maxEARSensitivity - Constants.minEARSensitivity
        let step = range / 2.0
        let relative = cachedEARSensitivity - Constants.minEARSensitivity
        
        if relative < step * 0.5 {
            sensitivityLabel = "high"
        } else if relative < step * 1.5 {
            sensitivityLabel = "medium"
        } else {
            sensitivityLabel = "low"
        }
        
        print("Cached EAR sensitivity updated to: \(cachedEARSensitivity) (\(sensitivityLabel) sensitivity)")
    }
    
    // Set up listeners for preference changes
    private func setupPreferenceListeners() {
        // Cancel any existing subscriptions first
        cancellables.removeAll()
        
        // Listen for EAR sensitivity changes
        preferencesService.$earSensitivity
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.cachedEARSensitivity = newValue
                print("Updated cached EAR sensitivity to: \(newValue)")
            }
            .store(in: &cancellables)
    }
} 