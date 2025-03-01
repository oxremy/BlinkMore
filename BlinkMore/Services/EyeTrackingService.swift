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
    
    // Eye Aspect Ratio (EAR) threshold
    private let earThreshold: Double = 0.2 // Threshold below which eyes are considered closed
    
    override init() {
        super.init()
        faceLandmarksRequest.constellation = .constellation76Points // Use more detailed landmarks if available
    }
    
    deinit {
        print("EyeTrackingService being deinitialized")
        
        // Make sure to clean up resources on the main thread
        if Thread.isMainThread {
            self.cleanupResources()
        } else {
            DispatchQueue.main.sync {
                self.cleanupResources()
            }
        }
    }
    
    private func cleanupResources() {
        // Stop tracking and release capture session resources
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
        
        // Remove sample buffer delegate to avoid potential retain cycles
        videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        
        // Release references
        videoDataOutput = nil
        captureSession = nil
        
        print("EyeTrackingService resources cleaned up")
    }
    
    // MARK: - Setup and Configuration
    
    func startTracking() {
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
        // Stop the capture session on a background queue
        captureSessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
                
                DispatchQueue.main.async {
                    self.isActive = false
                    self.isEyeOpen = false // Reset eye state
                }
                
                print("Eye tracking stopped")
            }
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
} 