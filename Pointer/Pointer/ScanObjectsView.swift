//
//  ScanObjectsView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/22/25.
//

import SwiftUI
import Photos

/// Preprocessing view for scanning and capturing objects
struct ScanObjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanManager = ScanCameraManager()
    @State private var showingExportOptions = false
    @State private var showingImageViewer = false
    @State private var selectedImageIndex: Int?
    @State private var exportSuccess = false
    @State private var exportError: String?
    
    var body: some View {
        ZStack {
            // Camera preview (full screen)
            GeometryReader { geometry in
                if let session = scanManager.captureSession {
                    ScanCameraPreviewView(session: session)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(ObjectIdentifier(session))
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
            .edgesIgnoringSafeArea(.all)
            
            // Scan guide overlay
            ScanGuideOverlay()
            
            // UI Overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)
                    }
                    
                    Spacer()
                    
                    // Progress indicator
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("\(scanManager.capturedImages.count)/5")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(scanManager.isComplete ? Color.green.opacity(0.8) : Color.black.opacity(0.5))
                    .cornerRadius(20)
                }
                .padding()
                
                // Instructions - moved to top
                if !scanManager.isComplete {
                    VStack(spacing: 8) {
                        Text("Capture your object from different angles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(scanManager.photosRemaining) photos remaining")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Error message
                if let error = scanManager.errorMessage {
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding()
                }
                
                // Export success message
                if exportSuccess {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                        Text("Photos saved successfully!")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(8)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // Thumbnail gallery - smaller and positioned just above bottom controls
                if !scanManager.capturedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(scanManager.capturedImages.enumerated()), id: \.offset) { index, image in
                                Button(action: {
                                    selectedImageIndex = index
                                    showingImageViewer = true
                                }) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        
                                        // Delete button
                                        Button(action: {
                                            withAnimation {
                                                scanManager.removePhoto(at: index)
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.red))
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 76)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Bottom controls
                HStack(spacing: 20) {
                    // Clear all button
                    if !scanManager.capturedImages.isEmpty {
                        Button(action: {
                            withAnimation {
                                scanManager.clearAllPhotos()
                                exportSuccess = false
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))
                                Text("Clear")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.white)
                            .frame(width: 70)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.7))
                            .cornerRadius(12)
                        }
                    }
                    
                    // Capture button
                    if !scanManager.isComplete {
                        Button(action: {
                            scanManager.capturePhoto()
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 70, height: 70)
                                
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        .disabled(!scanManager.isCapturing)
                    }
                    
                    // Export button
                    if scanManager.isComplete {
                        Button(action: {
                            showingExportOptions = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20))
                                Text("Export")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(width: 150)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green, Color.cyan]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await scanManager.startCapture()
            }
        }
        .onDisappear {
            scanManager.stopCapture()
        }
        .confirmationDialog("Export Photos", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("Save to Photos") {
                saveToPhotos()
            }
            Button("Share...", action: sharePhotos)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how to export your \(scanManager.capturedImages.count) captured photos")
        }
        .sheet(isPresented: $showingImageViewer) {
            if let index = selectedImageIndex {
                ImageViewerSheet(images: scanManager.capturedImages, selectedIndex: index)
            }
        }
    }
    
    // MARK: - Export Functions
    
    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    exportError = "Photos access denied"
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                for image in scanManager.capturedImages {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        withAnimation {
                            exportSuccess = true
                        }
                        // Hide success message after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                exportSuccess = false
                            }
                        }
                    } else {
                        exportError = error?.localizedDescription ?? "Failed to save photos"
                    }
                }
            }
        }
    }
    
    private func sharePhotos() {
        let activityVC = UIActivityViewController(activityItems: scanManager.capturedImages, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

/// Visual guide overlay for object scanning
struct ScanGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            // Make it almost the full width (90% of screen width)
            let size = geometry.size.width * 0.9
            
            ZStack {
                // Center square guide
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.cyan.opacity(0.8), Color.green.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: size, height: size)
                
                // Corner brackets
                VStack {
                    HStack {
                        CornerBracket(corner: .topLeft)
                        Spacer()
                        CornerBracket(corner: .topRight)
                    }
                    Spacer()
                    HStack {
                        CornerBracket(corner: .bottomLeft)
                        Spacer()
                        CornerBracket(corner: .bottomRight)
                    }
                }
                .frame(width: size - 20, height: size - 20)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

/// Corner bracket for scan guide
struct CornerBracket: View {
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    let corner: Corner
    let length: CGFloat = 40  // Increased from 30
    let thickness: CGFloat = 5  // Increased from 4
    
    var body: some View {
        ZStack {
            switch corner {
            case .topLeft:
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Color.cyan).frame(width: length, height: thickness)
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.cyan).frame(width: thickness, height: length - thickness)
                        Spacer()
                    }
                }
            case .topRight:
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle().fill(Color.cyan).frame(width: length, height: thickness)
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(Color.cyan).frame(width: thickness, height: length - thickness)
                    }
                }
            case .bottomLeft:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.cyan).frame(width: thickness, height: length - thickness)
                        Spacer()
                    }
                    Rectangle().fill(Color.cyan).frame(width: length, height: thickness)
                }
            case .bottomRight:
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(Color.cyan).frame(width: thickness, height: length - thickness)
                    }
                    Rectangle().fill(Color.cyan).frame(width: length, height: thickness)
                }
            }
        }
        .frame(width: length, height: length)
    }
}

/// Full-screen image viewer
struct ImageViewerSheet: View {
    let images: [UIImage]
    let selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    
    init(images: [UIImage], selectedIndex: Int) {
        self.images = images
        self.selectedIndex = selectedIndex
        _currentIndex = State(initialValue: selectedIndex)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        ZStack {
                            Color.black
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(currentIndex + 1) of \(images.count)")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
        }
    }
}

#Preview {
    ScanObjectsView()
}

