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
    @Published var localVideoTrack: LocalVideoTrack?
    @Published var currentPoseData: PoseData?  // Pose estimation data received from server
    
    // MARK: - Properties
    private var room: Room
    private var isCapturing: Bool = false
    private var captureTask: Task<Void, Never>?
    private let jsonDecoder = JSONDecoder()
    private var lastDataReceivedTime: Date?
    private var dataTimeoutTimer: Timer?
    private let dataTimeoutInterval: TimeInterval = 0.1  // Clear data if not received for 100ms
    
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
        // Set this instance as the room delegate to receive data messages
        room.add(delegate: self)
        
        // Start timer to check for stale pose data
        startDataTimeoutTimer()
    }
    
    deinit {
        dataTimeoutTimer?.invalidate()
        captureTask?.cancel()
        Task { [room, localVideoTrack] in
            await room.disconnect()
            try? await localVideoTrack?.stop()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start camera preview and optionally streaming
    func startCapture() {
        // Cancel any existing capture task
        captureTask?.cancel()
        
        // Always create a new task to ensure fresh initialization
        captureTask = Task {
            await startCameraCapture()
        }
    }
    
    /// Stop camera capture
    func stopCapture() async {
        isCapturing = false
        captureTask?.cancel()
        captureTask = nil
        
        // Stop the video track
        if let track = localVideoTrack {
            try? await track.stop()
        }
        
        await MainActor.run {
            localVideoTrack = nil
        }
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
        // Reset capturing state for fresh start
        isCapturing = false
        
        // Stop any existing video track
        if let existingTrack = await MainActor.run(body: { self.localVideoTrack }) {
            try? await existingTrack.stop()
            await MainActor.run {
                self.localVideoTrack = nil
            }
        }
        
        // Set capturing flag
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
            
            await MainActor.run {
                self.localVideoTrack = videoTrack
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to start camera: \(error.localizedDescription)"
                self.isCapturing = false
            }
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
            // Check if configuration is available
            guard let url = Config.liveKitURL, let token = Config.liveKitToken else {
                await MainActor.run {
                    self.errorMessage = "LiveKit configuration not set. Please check your .env file with LIVEKIT_URL and LIVEKIT_TOKEN."
                    self.connectionState = .failed
                    self.isStreaming = false
                }
                return
            }
            
            // Connect to LiveKit room
            try await room.connect(url: url, token: token)
            
            let options = VideoPublishOptions(
                encoding: VideoEncoding(
                    maxBitrate: 3_000_000,
                    maxFps: 30
                ),
                simulcast: false,
                degradationPreference: .maintainResolution
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
    
    /// Start timer to periodically check if pose data has become stale
    private func startDataTimeoutTimer() {
        // Run on main thread since we're updating @Published properties
        DispatchQueue.main.async { [weak self] in
            self?.dataTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkDataTimeout()
            }
        }
    }
    
    /// Check if pose data has timed out and clear it if so
    private func checkDataTimeout() {
        guard let lastReceived = lastDataReceivedTime else {
            // No data ever received, ensure currentPoseData is nil
            if currentPoseData != nil {
                currentPoseData = nil
            }
            return
        }
        
        let timeSinceLastData = Date().timeIntervalSince(lastReceived)
        if timeSinceLastData > dataTimeoutInterval {
            // Data is stale, clear it
            if currentPoseData != nil {
                currentPoseData = nil
                lastDataReceivedTime = nil
            }
        }
    }
}

// MARK: - RoomDelegate
extension WebRTCManager: RoomDelegate {
    /// Called when data is received from a remote participant
    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: LiveKit.EncryptionType) {
        // Filter for pose_estimates topic
        guard topic == "pose_estimates" else {
            return
        }
        
        // Decode the JSON data
        do {
            let poseData = try jsonDecoder.decode(PoseData.self, from: data)
            
            // Update on main thread since this is a @Published property
            Task { @MainActor in
                self.currentPoseData = poseData
                self.lastDataReceivedTime = Date()
            }
        } catch {
            print(error.localizedDescription)
        }
    }
}
