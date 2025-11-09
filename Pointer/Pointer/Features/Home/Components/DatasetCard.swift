//
//  DatasetCard.swift
//  Pointer
//
//  Created by Ron Kibel on 11/3/25.
//

import SwiftUI
import Combine

/// Card component to display a preprocessed dataset
struct DatasetCard: View {
    let dataset: PreprocessedDataset
    let isSelected: Bool
    let onSelect: () -> Void
    let onView: () -> Void
    @State private var navigateToDetail = false
    @StateObject private var previewLoader = DatasetPreviewLoader()
    
    var body: some View {
        ZStack {
            // Navigation link (hidden)
            NavigationLink(destination: DatasetDetailView(dataset: dataset), isActive: $navigateToDetail) {
                EmptyView()
            }
            .opacity(0)
            
            // Card content
            HStack(spacing: 12) {
                // Main content - tappable for selection
                VStack(alignment: .leading, spacing: 8) {
                    // Title
                    Text(dataset.description)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    // Metadata row
                    HStack(spacing: 16) {
                        // Image count
                        HStack(spacing: 6) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 12))
                            Text("\(dataset.imageCount) images")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Dataset ID
                    Text("ID: \(dataset.id)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                }
                
                // Single preview image (clickable) on the right
                if let previewImage = previewLoader.previewImages.first {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .onTapGesture {
                            navigateToDetail = true
                        }
                } else {
                    // Placeholder while loading
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 70, height: 70)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                                .scaleEffect(0.8)
                        )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.green : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .onAppear {
            Task {
                await previewLoader.loadPreviews(for: dataset.id)
            }
        }
    }
}

/// Handles loading preview thumbnails for dataset cards
class DatasetPreviewLoader: ObservableObject {
    @Published var previewImages: [UIImage] = []
    
    func loadPreviews(for datasetId: String) async {
        guard let apiURL = Config.vmApiURL else { return }
        
        do {
            // Fetch list of images
            let imagesListURL = URL(string: "\(apiURL)/dataset/\(datasetId)/images")!
            let (imagesData, _) = try await URLSession.shared.data(from: imagesListURL)
            
            guard let imagesList = try? JSONSerialization.jsonObject(with: imagesData) as? [String: Any],
                  let referenceFilenames = imagesList["reference_images"] as? [String] else {
                return
            }
            
            // Load first reference image for preview
            if let firstFilename = referenceFilenames.first {
                let imageURL = URL(string: "\(apiURL)/dataset/\(datasetId)/image/reference/\(firstFilename)")!
                
                let (imageData, _) = try await URLSession.shared.data(from: imageURL)
                if let image = UIImage(data: imageData) {
                    await MainActor.run {
                        self.previewImages = [image]
                    }
                }
            }
            
        } catch {
            // Silently fail for previews
            await MainActor.run {
                self.previewImages = []
            }
        }
    }
}
