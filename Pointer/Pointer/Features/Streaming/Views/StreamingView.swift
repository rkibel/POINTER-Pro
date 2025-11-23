//
//  StreamingView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/20/25.
//

import SwiftUI
import LiveKit
import Combine

/// Main streaming interface view
struct StreamingView: View {
    let datasetId: String
    let isDeveloperMode: Bool
    let inferenceConfiguration: InferenceConfig
    @StateObject private var webRTCManager = WebRTCManager()
    @StateObject private var vmManager = VMProcessingManager()
    @StateObject private var lifxManager = LIFXManager()
    @State private var showDetectionBox = false
    @State private var showSegmentation = false
    @State private var showPoseEstimation = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if !Config.isConfigured {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("Configuration Required")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("LiveKit credentials are not configured.\n\nPlease ensure your .env file contains:\n• LIVEKIT_URL\n• LIVEKIT_TOKEN")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                
                Spacer()
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.15, blue: 0.25)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .ignoresSafeArea()
        } else {
            streamingContent
        }
    }
    
    var streamingContent: some View {
        ZStack {
            // Camera preview (full screen)
            CameraPreviewView(videoTrack: webRTCManager.localVideoTrack)
                .edgesIgnoringSafeArea(.all)
            
            // Overlays based on inference configuration
            if let poseData = webRTCManager.currentPoseData {
                if inferenceConfiguration == .designVisualization {
                    // AR Prop mode: Show virtual 3D model
                    ARPropOverlayView(
                        poseData: poseData,
                        imageSize: CGSize(
                            width: CGFloat(poseData.imageSize[0]),
                            height: CGFloat(poseData.imageSize[1])
                        )
                    )
                    .edgesIgnoringSafeArea(.all)
                    
                    // Also show bounding box overlay if toggles are enabled
                    GeometryReader { geometry in
                        BoundingBoxOverlayView(
                            poseData: poseData,
                            imageSize: CGSize(
                                width: CGFloat(poseData.imageSize[0]),
                                height: CGFloat(poseData.imageSize[1])
                            ),
                            showDetectionBox: showDetectionBox,
                            showSegmentation: showSegmentation,
                            showPoseEstimation: showPoseEstimation
                        )
                    }
                    .edgesIgnoringSafeArea(.all)
                } else {
                    // Demo/Light modes: Show 3D bounding box overlay
                    GeometryReader { geometry in
                        BoundingBoxOverlayView(
                            poseData: poseData,
                            imageSize: CGSize(
                                width: CGFloat(poseData.imageSize[0]),
                                height: CGFloat(poseData.imageSize[1])
                            ),
                            showDetectionBox: showDetectionBox,
                            showSegmentation: showSegmentation,
                            showPoseEstimation: showPoseEstimation
                        )
                    }
                    .edgesIgnoringSafeArea(.all)
                }
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
                // Bottom controls: absolutely center the start/stop button
                ZStack {
                    // Centered start/stop button
                    Button(action: toggleStreaming) {
                        Image(systemName: webRTCManager.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(webRTCManager.isStreaming ? .red : .white)
                    }
                    // Toggle buttons in triangular layout aligned to bottom right
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            // Top button: Pose Estimation
                            PoseEstimationToggle(isEnabled: $showPoseEstimation)
                                .frame(width: 36, height: 36)
                            // Bottom row: Detection and Segmentation
                            HStack(spacing: 12) {
                                DetectionBoxToggle(isEnabled: $showDetectionBox)
                                    .frame(width: 36, height: 36)
                                SegmentationToggle(isEnabled: $showSegmentation)
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.trailing, 30)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            webRTCManager.startCapture()
            
            // Enable LIFX if in light mode (light will turn on when object is detected)
            if inferenceConfiguration == .light {
                lifxManager.isEnabled = true
            }
        }
        .onDisappear {
            Task {
                await webRTCManager.stopCapture()
                webRTCManager.stopStreaming()
                
                // Turn off LIFX if it was enabled
                if lifxManager.isEnabled {
                    lifxManager.turnOff()
                    lifxManager.isEnabled = false
                }
                
                // Stop inference when leaving the view (skip if in developer mode)
                if !isDeveloperMode {
                    try? await vmManager.stopInference(datasetId: datasetId)
                }
            }
        }
        .onChange(of: webRTCManager.currentPoseData) { _, newPoseData in
            // Update LIFX based on pose data (turns on when detected, off when not)
            if inferenceConfiguration == .light {
                lifxManager.updateFromPose(newPoseData)
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

/// Detection box toggle indicator
struct DetectionBoxToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            Image(systemName: "viewfinder")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.green : Color.black.opacity(0.5))
                )
                .overlay(
                    Circle()
                        .stroke(isEnabled ? Color.green : Color.white.opacity(0.3), lineWidth: 2)
                )
        }
    }
}

/// Segmentation mask toggle indicator
struct SegmentationToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.yellow : Color.black.opacity(0.5))
                )
                .overlay(
                    Circle()
                        .stroke(isEnabled ? Color.yellow : Color.white.opacity(0.3), lineWidth: 2)
                )
        }
    }
}

/// Pose estimation toggle indicator
struct PoseEstimationToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.cyan : Color.black.opacity(0.5))
                )
                .overlay(
                    Circle()
                        .stroke(isEnabled ? Color.cyan : Color.white.opacity(0.3), lineWidth: 2)
                )
        }
    }
}

#Preview {
    StreamingView(datasetId: "dataset_preview", isDeveloperMode: false, inferenceConfiguration: .light)
}
