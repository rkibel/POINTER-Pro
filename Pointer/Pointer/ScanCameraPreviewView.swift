//
//  ScanCameraPreviewView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/22/25.
//

import SwiftUI
import AVFoundation

/// Camera preview view for object scanning using direct session reference
struct ScanCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.videoOrientation = .portrait
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session is already set in makeUIView
    }
    
    class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
}
