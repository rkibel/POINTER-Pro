//
//  DatasetDetailView.swift
//  Pointer
//
//  Created by Ron Kibel on 11/2/25.
//

import SwiftUI
import Combine

/// Detail view showing all images from a preprocessed dataset
struct DatasetDetailView: View {
    let dataset: PreprocessedDataset
    @StateObject private var imageLoader = DatasetImageLoader()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0 // 0 = reference, 1 = verification
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.15, blue: 0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                .padding()
                
                // Dataset info
                VStack(spacing: 8) {
                    Text(dataset.description)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 16) {
                        Label("\(dataset.imageCount) images", systemImage: "photo.stack")
                        Text(dataset.formattedDate)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    
                    Text("ID: \(dataset.id)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding()
                
                // Tab Picker
                Picker("Image Type", selection: $selectedTab) {
                    Text("Reference").tag(0)
                    Text("Verification").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Images grid
                if imageLoader.isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading images...")
                            .foregroundColor(.white)
                    }
                    Spacer()
                } else if selectedTab == 0 && !imageLoader.referenceImages.isEmpty {
                    // Reference Images
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(imageLoader.referenceImages.enumerated()), id: \.offset) { index, image in
                                VStack(spacing: 4) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                    
                                    Text(imageLoader.referenceFilenames[index])
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding()
                    }
                } else if selectedTab == 1 && !imageLoader.verificationImages.isEmpty {
                    // Verification Images
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(imageLoader.verificationImages.enumerated()), id: \.offset) { index, image in
                                VStack(spacing: 4) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                    
                                    Text(imageLoader.verificationFilenames[index])
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let error = imageLoader.error {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Failed to load images")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        Text("No images found")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(selectedTab == 0 ? "No reference images available" : "No verification images available")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await imageLoader.loadImages(for: dataset.id)
            }
        }
    }
}

/// Handles loading images from the VM API
class DatasetImageLoader: ObservableObject {
    @Published var referenceImages: [UIImage] = []
    @Published var verificationImages: [UIImage] = []
    @Published var referenceFilenames: [String] = []
    @Published var verificationFilenames: [String] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let vmManager = VMProcessingManager()
    
    func loadImages(for datasetId: String) async {
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            // First, get the list of image filenames
            let (referenceFilenames, verificationFilenames) = try await vmManager.getDatasetImageFilenames(datasetId: datasetId)
            
            // Load reference images
            var loadedReferenceImages: [UIImage] = []
            for filename in referenceFilenames {
                do {
                    let image = try await vmManager.loadDatasetImage(
                        datasetId: datasetId,
                        imageType: "reference_data",
                        filename: filename
                    )
                    loadedReferenceImages.append(image)
                } catch {
                    print("⚠️ Failed to load reference image \(filename): \(error)")
                }
            }
            
            // Load verification images
            var loadedVerificationImages: [UIImage] = []
            for filename in verificationFilenames {
                do {
                    let image = try await vmManager.loadDatasetImage(
                        datasetId: datasetId,
                        imageType: "verification",
                        filename: filename
                    )
                    loadedVerificationImages.append(image)
                } catch {
                    print("⚠️ Failed to load verification image \(filename): \(error)")
                }
            }
            
            await MainActor.run {
                self.referenceImages = loadedReferenceImages
                self.referenceFilenames = referenceFilenames
                self.verificationImages = loadedVerificationImages
                self.verificationFilenames = verificationFilenames
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
