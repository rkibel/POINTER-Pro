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
            
            // Overlay UI
            VStack {
                // Top bar - Status
                HStack {
                    StatusIndicator(state: webRTCManager.connectionState)
                    Spacer()
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

#Preview {
    StreamingView()
}
