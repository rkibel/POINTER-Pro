//
//  CameraPreviewView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/20/25.
//

import SwiftUI
import LiveKit

/// SwiftUI view for displaying camera preview using LiveKit
struct CameraPreviewView: View {
    let videoTrack: LocalVideoTrack?
    
    var body: some View {
        GeometryReader { geometry in
            if let track = videoTrack {
                VideoViewWrapper(videoTrack: track)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .id(ObjectIdentifier(track))
            } else {
                Color.black
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Initializing camera...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                    )
            }
        }
    }
}

struct VideoViewWrapper: UIViewRepresentable {
    let videoTrack: LocalVideoTrack
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        
        let videoView = VideoView()
        videoView.backgroundColor = .black
        videoView.layoutMode = .fit
        videoView.mirrorMode = .off
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.track = videoTrack
        
        container.addSubview(videoView)
        
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: container.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        
        context.coordinator.videoView = videoView
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let videoView = context.coordinator.videoView else { return }
        
        if videoView.track !== videoTrack {
            videoView.track = videoTrack
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var videoView: VideoView?
    }
}

#Preview {
    CameraPreviewView(videoTrack: nil)
}
