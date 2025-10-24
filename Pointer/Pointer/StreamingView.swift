//
//  StreamingView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/20/25.
//

import SwiftUI
import LiveKit

/// Main streaming interface view
struct StreamingView: View {
    @StateObject private var webRTCManager = WebRTCManager()
    
    var body: some View {
        ZStack {
            // Camera preview (full screen)
            CameraPreviewView(videoTrack: webRTCManager.localVideoTrack)
                .edgesIgnoringSafeArea(.all)
            
            // Pose estimation region indicator
            GeometryReader { geometry in
                PoseEstimationOverlay(geometry: geometry)
            }
            .edgesIgnoringSafeArea(.all)
            
            // 3D Bounding box overlay
            if webRTCManager.currentPoseData != nil {
                GeometryReader { geometry in
                    BoundingBoxOverlayView(
                        poseData: webRTCManager.currentPoseData,
                        imageSize: CGSize(width: 720, height: 1280)  // Match your stream resolution
                    )
                }
                .edgesIgnoringSafeArea(.all)
            }
            
            // Overlay UI
            VStack {
                // Top bar - Status
                HStack {
                    StatusIndicator(state: webRTCManager.connectionState)
                    Spacer()
                    
                    // Pose data indicator
                    PoseDataIndicator(hasData: webRTCManager.currentPoseData != nil)
                }
                .padding()
                
                Spacer()
                
                // Error message
                if let error = webRTCManager.errorMessage {
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding()
                }
                
                // Bottom controls
                HStack(spacing: 30) {
                    // Stream toggle button
                    Button(action: toggleStreaming) {
                        Image(systemName: webRTCManager.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(webRTCManager.isStreaming ? .red : .white)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            webRTCManager.startCapture()
        }
        .onDisappear {
            Task {
                await webRTCManager.stopCapture()
                webRTCManager.stopStreaming()
            }
        }
    }
    
    private func toggleStreaming() {
        if webRTCManager.isStreaming {
            webRTCManager.stopStreaming()
        } else {
            webRTCManager.startCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webRTCManager.startStreaming()
            }
        }
    }
}

/// Status indicator showing connection state
struct StatusIndicator: View {
    let state: WebRTCManager.ConnectionState
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            Text(state.description)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
    }
    
    private var statusColor: Color {
        switch state {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }
}

/// Pose data indicator showing whether pose data is being received
struct PoseDataIndicator: View {
    let hasData: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(hasData ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            Text(hasData ? "Data Received" : "No Data")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
    }
}

/// Visual overlay indicating the center-cropped region used for pose estimation
struct PoseEstimationOverlay: View {
    let geometry: GeometryProxy
    
    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        
        // Calculate center square crop region (assuming portrait mode)
        let cropSize = width // Square crop based on width
        let topCrop = (height - cropSize) / 2
        let bottomCrop = (height - cropSize) / 2
        
        ZStack {
            // Dimmed overlay for cropped regions
            VStack(spacing: 0) {
                // Top cropped area
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(height: topCrop)
                
                // Active estimation region (transparent)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: cropSize)
                
                // Bottom cropped area
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(height: bottomCrop)
            }
            
            // Border outline for active region
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green.opacity(0.6), Color.cyan.opacity(0.6)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: width - 4, height: cropSize - 4)
                .position(x: width / 2, y: height / 2)
            
            // Corner markers for active region
            VStack {
                HStack {
                    CornerMarker(corners: [.topLeft])
                    Spacer()
                    CornerMarker(corners: [.topRight])
                }
                Spacer()
                HStack {
                    CornerMarker(corners: [.bottomLeft])
                    Spacer()
                    CornerMarker(corners: [.bottomRight])
                }
            }
            .frame(width: width - 20, height: cropSize - 20)
            .position(x: width / 2, y: height / 2)
            
            // Label at top of active region
            Text("POSE ESTIMATION REGION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .position(x: width / 2, y: topCrop + 15)
        }
    }
}

/// Corner marker view for the pose estimation region
struct CornerMarker: View {
    let corners: UIRectCorner
    let length: CGFloat = 20
    let thickness: CGFloat = 3
    
    var body: some View {
        ZStack {
            if corners.contains(.topLeft) {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: length, height: thickness)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: thickness, height: length - thickness)
                        Spacer()
                    }
                }
            }
            if corners.contains(.topRight) {
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: length, height: thickness)
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: thickness, height: length - thickness)
                    }
                }
            }
            if corners.contains(.bottomLeft) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: thickness, height: length - thickness)
                        Spacer()
                    }
                    Rectangle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: length, height: thickness)
                }
            }
            if corners.contains(.bottomRight) {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: thickness, height: length - thickness)
                    }
                    Rectangle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: length, height: thickness)
                }
            }
        }
        .frame(width: length, height: length)
    }
}

#Preview {
    StreamingView()
}
