//
//  WebRTCManager.swift
//  Pointer
//
//  Created by Ron Kibel on 10/20/25.
//

import Foundation
import AVFoundation
import Combine
import LiveKit

/// Manages WebRTC streaming to LiveKit server
class WebRTCManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isStreaming: Bool = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var errorMessage: String?
    @Published var localVideoTrack: LocalVideoTrack?  // Changed: Publish the track directly
    
    // MARK: - Properties
    private var room: Room
    private var isCapturing: Bool = false
    private var captureTask: Task<Void, Never>?
    
    // MARK: - Connection States
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed
        
        var description: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .failed: return "Connection Failed"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        room = Room()
        captureTask = Task {
            await startCameraCapture()
        }
    }
    
    deinit {
        captureTask?.cancel()
        Task { [weak self] in
            _ = await self?.stopCapture()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start camera preview and optionally streaming
    func startCapture() {
        guard !isCapturing, captureTask == nil || captureTask?.isCancelled == true else {
            return
        }
        
        captureTask = Task {
            await startCameraCapture()
        }
    }
    
    /// Stop camera capture
    func stopCapture() async {
        isCapturing = false
        captureTask?.cancel()
        captureTask = nil
        localVideoTrack = nil
    }
    
    /// Start streaming to the LiveKit server
    func startStreaming() {
        Task {
            await connectToEndpoint()
        }
    }
    
    /// Stop streaming
    func stopStreaming() {
        Task {
            await room.disconnect()
            await MainActor.run {
                isStreaming = false
                connectionState = .disconnected
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startCameraCapture() async {
        if isCapturing { return }
        isCapturing = true
        
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
                self.connectionState = .failed
                self.isCapturing = false
            }
            return
        }
        
        // Create and start camera track
        let options = CameraCaptureOptions(
            position: .back,
            dimensions: .h720_169,
            fps: 30
        )
        
        let videoTrack = LocalVideoTrack.createCameraTrack(options: options)
        
        do {
            try await videoTrack.start()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to start camera: \(error.localizedDescription)"
                self.isCapturing = false
            }
            return
        }
        
        await MainActor.run {
            self.localVideoTrack = videoTrack
            self.errorMessage = nil
        }
    }
    
    private func connectToEndpoint() async {
        guard let track = localVideoTrack else {
            await MainActor.run {
                self.errorMessage = "Camera not initialized"
            }
            return
        }
        
        await MainActor.run {
            self.connectionState = .connecting
        }
        
        do {
            // Get LiveKit connection details from Config
            let url = Config.liveKitURL
            let token = Config.liveKitToken
            
            // Connect to LiveKit room
            try await room.connect(url: url, token: token)
            
            // Publish local video track with options
            let options = VideoPublishOptions(
                encoding: VideoEncoding(
                    maxBitrate: 2_000_000,
                    maxFps: 30
                )
            )
            
            try await room.localParticipant.publish(videoTrack: track, options: options)
            
            await MainActor.run {
                self.connectionState = .connected
                self.isStreaming = true
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to connect: \(error.localizedDescription)"
                self.connectionState = .failed
                self.isStreaming = false
            }
        }
    }
}
