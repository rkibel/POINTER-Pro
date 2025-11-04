//
//  ScanCameraManager.swift
//  Pointer
//
//  Created by Ron Kibel on 10/22/25.
//

import Foundation
import AVFoundation
import UIKit
import Combine

/// Manages camera capture for object scanning (independent from WebRTCManager)
class ScanCameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var capturedImages: [UIImage] = []
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var captureSession: AVCaptureSession?
    @Published var errorMessage: String?
    @Published var isCapturing: Bool = false
    @Published var captureProgress: Float = 0.0
    
    // MARK: - Properties
    private var photoOutput: AVCapturePhotoOutput?
    private var currentPhotoSettings: AVCapturePhotoSettings?
    private let maxPhotos = 5
    
    // MARK: - Computed Properties
    var photosRemaining: Int {
        return max(0, maxPhotos - capturedImages.count)
    }
    
    var isComplete: Bool {
        return capturedImages.count >= maxPhotos
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Public Methods
    
    /// Start camera session for scanning
    func startCapture() async {
        // Check camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = false
        
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }
        
        guard granted else {
            await MainActor.run {
                self.errorMessage = "Camera permission denied. Please enable camera access in Settings."
            }
            return
        }
        
        // Setup capture session
        await setupCaptureSession()
    }
    
    /// Stop camera session
    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        photoOutput = nil
        previewLayer = nil
        isCapturing = false
    }
    
    /// Pause camera session (keeps session alive but stops processing)
    func pauseCapture() {
        guard let session = captureSession, session.isRunning else { return }
        
        // Run on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.stopRunning()
            DispatchQueue.main.async {
                self?.isCapturing = false
            }
        }
    }
    
    /// Resume camera session
    func resumeCapture() {
        guard let session = captureSession, !session.isRunning else { return }
        
        // Run on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isCapturing = true
            }
        }
    }
    
    /// Capture a photo
    func capturePhoto() {
        guard let photoOutput = photoOutput,
              capturedImages.count < maxPhotos else {
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        
        currentPhotoSettings = settings
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    /// Remove a captured photo at index
    func removePhoto(at index: Int) {
        guard index < capturedImages.count else { return }
        capturedImages.remove(at: index)
        updateProgress()
    }
    
    /// Clear all captured photos
    func clearAllPhotos() {
        capturedImages.removeAll()
        updateProgress()
    }
    
    // MARK: - Private Methods
    
    private func setupCaptureSession() async {
        // Get back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            await MainActor.run {
                self.errorMessage = "Failed to access camera"
            }
            return
        }
        
        let session = AVCaptureSession()
        
        do {
            // Configure session on background queue for better performance
            session.beginConfiguration()
            
            // Use high quality preset for photos but optimized for faster startup
            session.sessionPreset = .high
            
            // Add camera input
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Add photo output with optimized settings
            let output = AVCapturePhotoOutput()
            output.isHighResolutionCaptureEnabled = true
            output.maxPhotoQualityPrioritization = .balanced  // Faster than .quality
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
            
            // Start session immediately on background queue (non-blocking)
            let sessionQueue = DispatchQueue(label: "com.pointer.session", qos: .userInitiated)
            sessionQueue.async {
                session.startRunning()
            }
            
            // Update UI on main thread immediately (don't wait for session to start)
            await MainActor.run {
                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                preview.connection?.videoOrientation = .portrait
                
                self.captureSession = session
                self.previewLayer = preview
                self.photoOutput = output
                self.errorMessage = nil
                self.isCapturing = true
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to setup camera: \(error.localizedDescription)"
            }
        }
    }
    
    private func updateProgress() {
        captureProgress = Float(capturedImages.count) / Float(maxPhotos)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension ScanCameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to capture photo: \(error.localizedDescription)"
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to process photo"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.capturedImages.append(image)
            self.updateProgress()
        }
    }
}
