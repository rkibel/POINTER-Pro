//
//  ScanCameraManager.swift
//  Pointer
//
//  Created by Ron Kibel on 10/22/25.
//

import AVFoundation
import UIKit
import Combine

/// Manages camera capture for object scanning - optimized for fast startup
@MainActor
class ScanCameraManager: NSObject, ObservableObject {
    
    @Published var capturedImages: [UIImage] = []
    @Published var captureSession: AVCaptureSession?
    @Published var errorMessage: String?
    @Published var captureProgress: Float = 0.0
    
    private var photoOutput: AVCapturePhotoOutput?
    private let maxPhotos = 5
    
    var photosRemaining: Int { max(0, maxPhotos - capturedImages.count) }
    var isComplete: Bool { capturedImages.count >= maxPhotos }
    
    // MARK: - Public Methods
    
    func startCapture() async {
        cleanup()
        
        guard await checkCameraPermission() else {
            errorMessage = "Camera permission denied. Please enable camera access in Settings."
            return
        }
        
        await setupCamera()
    }
    
    func stopCapture() { cleanup() }
    
    func capturePhoto() {
        guard let photoOutput, capturedImages.count < maxPhotos else { return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func removePhoto(at index: Int) {
        guard index < capturedImages.count else { return }
        capturedImages.remove(at: index)
        captureProgress = Float(capturedImages.count) / Float(maxPhotos)
    }
    
    func clearAllPhotos() {
        capturedImages.removeAll()
        captureProgress = 0
    }
    
    // MARK: - Private Methods
    
    private func checkCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
    
    private func setupCamera() async {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            errorMessage = "Failed to access camera"
            return
        }
        
        let session = AVCaptureSession()
        
        // Setup off main thread for fast startup
        let result: (Bool, AVCapturePhotoOutput?, String?) = await Task.detached(priority: .userInitiated) {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    return (false, nil, "Cannot add camera input")
                }
                session.addInput(input)
                
                let output = AVCapturePhotoOutput()
                output.maxPhotoQualityPrioritization = .quality
                
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    return (false, nil, "Cannot add photo output")
                }
                session.addOutput(output)
                
                session.commitConfiguration()
                session.startRunning()
                
                return (true, output, nil)
            } catch {
                session.commitConfiguration()
                return (false, nil, "Failed to setup camera: \(error.localizedDescription)")
            }
        }.value
        
        if result.0 {
            captureSession = session
            photoOutput = result.1
            errorMessage = nil
        } else {
            errorMessage = result.2
        }
    }
    
    private func cleanup() {
        captureSession?.stopRunning()
        captureSession = nil
        photoOutput = nil
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension ScanCameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            Task { @MainActor in
                self.errorMessage = error?.localizedDescription ?? "Failed to process photo"
            }
            return
        }
        
        Task { @MainActor in
            self.capturedImages.append(image)
            self.captureProgress = Float(self.capturedImages.count) / Float(self.maxPhotos)
        }
    }
}
