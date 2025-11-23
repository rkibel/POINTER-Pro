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
    @StateObject private var vmManager = VMProcessingManager()
    @State private var showingExportOptions = false
    @State private var showingImageViewer = false
    @State private var selectedImageIndex: Int?
    @State private var exportSuccess = false
    @State private var exportError: String?
    @State private var objectDescription = ""
    @State private var isProcessingOnVM = false
    
    var body: some View {
        ZStack {
            cameraPreview
            ScanGuideOverlay()
            
            VStack {
                topBar
                instructionsOrDescriptionField
                Spacer()
                statusMessages
                Spacer()
                if !scanManager.capturedImages.isEmpty { thumbnailGallery }
                bottomControls
            }
        }
        .navigationBarHidden(true)
        .onAppear { Task { await scanManager.startCapture() } }
        .onDisappear { scanManager.stopCapture() }
        .onChange(of: scanManager.capturedImages.count) { _, newValue in
            if newValue < 5 && !objectDescription.isEmpty {
                withAnimation { objectDescription = "" }
            }
        }
        .confirmationDialog("Export Photos", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("Process on VM") { processOnVM() }
            Button("Save to Photos") { saveToPhotos() }
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
    
    // MARK: - View Components
    
    private var cameraPreview: some View {
        GeometryReader { geometry in
            if let session = scanManager.captureSession {
                ScanCameraPreviewView(session: session)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .id(ObjectIdentifier(session))
            } else {
                Color.black.overlay(
                    VStack(spacing: 16) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                        Text("Initializing camera...").foregroundColor(.white).font(.headline)
                    }
                )
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Label("Back", systemImage: "chevron.left")
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
            }
            Spacer()
            Label("\(scanManager.capturedImages.count)/5", systemImage: "camera.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(scanManager.isComplete ? Color.green.opacity(0.8) : Color.black.opacity(0.5))
                .cornerRadius(20)
        }
        .padding()
    }
    
    private var instructionsOrDescriptionField: some View {
        Group {
            if !scanManager.isComplete {
                VStack(spacing: 8) {
                    Text("Capture your object from different angles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(scanManager.photosRemaining) photos remaining")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12).padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Object Description")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft").foregroundColor(.cyan).font(.system(size: 16))
                        TextField("Describe your object (e.g., red mug, laptop)", text: $objectDescription)
                            .font(.system(size: 16)).foregroundColor(.white)
                            .autocapitalization(.none).disableAutocorrection(true).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(objectDescription.isEmpty ? Color.white.opacity(0.3) : Color.cyan.opacity(0.6), lineWidth: 1.5)
                    )
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.black.opacity(0.7))
                .cornerRadius(12).padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var statusMessages: some View {
        VStack(spacing: 12) {
            if let error = scanManager.errorMessage {
                StatusBadge(icon: "exclamationmark.triangle.fill", text: error, color: .red)
            }
            if exportSuccess {
                StatusBadge(icon: "checkmark.circle.fill", 
                           text: isProcessingOnVM ? "Processing complete!" : "Photos saved successfully!",
                           color: .green)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if vmManager.isProcessing {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.2)
                    Text(vmManager.processingProgress).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                }
                .padding(20).background(Color.black.opacity(0.8)).cornerRadius(12).padding()
            }
            if let error = exportError {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 24))
                        Text("Error").font(.system(size: 16, weight: .semibold))
                    }
                    Text(error).font(.system(size: 14)).multilineTextAlignment(.center)
                }
                .foregroundColor(.white).padding().background(Color.red.opacity(0.8)).cornerRadius(8).padding()
            }
        }
    }
    
    private var thumbnailGallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(scanManager.capturedImages.enumerated()), id: \.offset) { index, image in
                    ThumbnailView(image: image, onTap: {
                        selectedImageIndex = index
                        showingImageViewer = true
                    }, onDelete: {
                        withAnimation { scanManager.removePhoto(at: index) }
                    })
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .frame(height: 76)
        .background(Color.black.opacity(0.4))
        .cornerRadius(10).padding(.horizontal).padding(.bottom, 8)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 20) {
            if !scanManager.capturedImages.isEmpty {
                ControlButton(icon: "trash", text: "Clear", color: .red) {
                    withAnimation {
                        scanManager.clearAllPhotos()
                        objectDescription = ""
                        exportSuccess = false
                    }
                }
            }
            
            if !scanManager.isComplete {
                Button(action: { scanManager.capturePhoto() }) {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 70, height: 70)
                        Circle().fill(Color.white).frame(width: 60, height: 60)
                    }
                }
                .disabled(scanManager.captureSession == nil)
            }
            
            if scanManager.isComplete {
                Button(action: { showingExportOptions = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 20))
                        Text("Export").font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white).frame(width: 150).padding(.vertical, 16)
                    .background(
                        Group {
                            if objectDescription.trimmingCharacters(in: .whitespaces).isEmpty {
                                Color.gray.opacity(0.5)
                            } else {
                                LinearGradient(gradient: Gradient(colors: [Color.green, Color.cyan]), startPoint: .leading, endPoint: .trailing)
                            }
                        }
                    )
                    .cornerRadius(12)
                }
                .disabled(objectDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.bottom, 30)
    }
    
    // MARK: - Export Functions
    
    private func processOnVM() {
        Task {
            do {
                isProcessingOnVM = true
                exportError = nil
                _ = try await vmManager.processImages(scanManager.capturedImages, description: objectDescription)
                
                await MainActor.run { isProcessingOnVM = false; exportSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { exportSuccess = false }
                    dismiss()
                }
            } catch {
                await MainActor.run { isProcessingOnVM = false; exportError = error.localizedDescription }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { exportError = nil }
                }
            }
        }
    }
    
    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { exportError = "Photos access denied" }
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                for image in scanManager.capturedImages {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    if success {
                        withAnimation { exportSuccess = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { exportSuccess = false }
                        }
                    } else {
                        exportError = "Failed to save photos"
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

// MARK: - Helper Views

struct StatusBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 24))
            Text(text).font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.white).padding()
        .background(color.opacity(0.8)).cornerRadius(8).padding()
    }
}

struct ThumbnailView: View {
    let image: UIImage
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Button(action: onDelete) {
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

struct ControlButton: View {
    let icon: String
    let text: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 24))
                Text(text).font(.system(size: 12))
            }
            .foregroundColor(.white).frame(width: 70).padding(.vertical, 12)
            .background(color.opacity(0.7)).cornerRadius(12)
        }
    }
}

/// Visual guide overlay for object scanning
struct ScanGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width * 0.9
            
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(LinearGradient(gradient: Gradient(colors: [Color.cyan.opacity(0.8), Color.green.opacity(0.8)]),
                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                    .frame(width: size, height: size)
                
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

struct CornerBracket: View {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    
    let corner: Corner
    let length: CGFloat = 40
    let thickness: CGFloat = 5
    
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
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background(Color.black)
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
                        .foregroundColor(.white).font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
        }
    }
}

#Preview { ScanObjectsView() }