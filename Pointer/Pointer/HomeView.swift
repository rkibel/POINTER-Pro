//
//  HomeView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/22/25.
//

import SwiftUI
import Combine

/// Main home page with navigation to different app features
struct HomeView: View {
    @State private var navigateToStreaming = false
    @State private var navigateToScanning = false
    @StateObject private var vmManager = VMProcessingManager()
    @State private var showingDatasets = true
    @State private var editingDataset: PreprocessedDataset?
    @State private var editDescription = ""
    @State private var showingEditDialog = false
    @State private var datasetToDelete: PreprocessedDataset?
    @State private var showingDeleteConfirmation = false
    @State private var selectedDataset: PreprocessedDataset?
    @State private var showingInferenceAlert = false
    @State private var inferenceMessage = ""
    @State private var isRunningInference = false
    @State private var showingSettings = false
    @State private var inferenceConfiguration: InferenceConfig = .basicDemo
    
    enum InferenceConfig: String, CaseIterable {
        case basicDemo = "Basic Demo"
        case instrument = "Instrument"
        case lightbulb = "Lightbulb"
        case digitalTwin = "Digital Twin"
    }
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.1, green: 0.1, blue: 0.2),
                Color(red: 0.05, green: 0.15, blue: 0.25)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                backgroundGradient
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top bar with settings button
                    HStack {
                        Spacer()
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    
                    // Logo/Title Section - Fixed at top
                    VStack(spacing: 16) {
                        // Main title
                        Text("POINTER")
                            .font(.system(size: 56, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .tracking(4)
                        
                        // Subtitle
                        Text("Persistent Object-anchored Interactions\nand Tagging for Enriched Reality")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    
                    // Preprocessed Datasets Section - Fixed header
                    if !vmManager.availableDatasets.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: {
                                showingDatasets.toggle()
                            }) {
                                HStack {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 20)
                                        .rotationEffect(.degrees(showingDatasets ? 90 : 0))
                                        .animation(.easeInOut(duration: 0.2), value: showingDatasets)
                                    Text("Preprocessed Objects")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            
                            // Expandable list
                            if showingDatasets {
                                List {
                                    ForEach(vmManager.availableDatasets.prefix(5)) { dataset in
                                        DatasetCard(
                                            dataset: dataset,
                                            isSelected: selectedDataset?.id == dataset.id,
                                            onSelect: {
                                                selectedDataset = (selectedDataset?.id == dataset.id) ? nil : dataset
                                            },
                                            onView: {
                                                // Navigation is handled separately
                                            }
                                        )
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                datasetToDelete = dataset
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                editingDataset = dataset
                                                editDescription = dataset.description
                                                showingEditDialog = true
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                                .frame(maxHeight: 300)
                                .padding(.horizontal, 40)
                            }
                        }
                        .padding(.bottom, 30)
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 20) {
                        // Scan Objects Button
                        NavigationLink(destination: ScanObjectsView()) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                Text("Scan Objects")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // Inference Button - Enabled when a dataset is selected
                        ZStack {
                            // Hidden NavigationLink
                            if let selected = selectedDataset {
                                NavigationLink(
                                    destination: StreamingView(datasetId: selected.id),
                                    isActive: $navigateToStreaming
                                ) {
                                    EmptyView()
                                }
                                .hidden()
                            }
                            
                            // Visible button
                            Button(action: {
                                guard let selected = selectedDataset else { return }
                                Task {
                                    isRunningInference = true
                                    do {
                                        _ = try await vmManager.startInference(datasetId: selected.id)
                                        isRunningInference = false
                                        navigateToStreaming = true
                                    } catch {
                                        inferenceMessage = error.localizedDescription
                                        isRunningInference = false
                                        showingInferenceAlert = true
                                    }
                                }
                            }) {
                                HStack {
                                    if isRunningInference {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Starting...")
                                            .font(.system(size: 18, weight: .semibold))
                                    } else {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 20))
                                        Text("Inference")
                                            .font(.system(size: 18, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    selectedDataset != nil ?
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.orange, Color.red]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(selectedDataset != nil ? .white : .white.opacity(0.4))
                                .cornerRadius(12)
                                .overlay(
                                    selectedDataset == nil ?
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1) : nil
                                )
                            }
                            .disabled(selectedDataset == nil || isRunningInference)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                    
                    // Copyright text
                    Text("© 2025 POINTER")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    try? await vmManager.fetchAvailableDatasets()
                }
            }
            .alert("Edit Description", isPresented: $showingEditDialog) {
                TextField("Description", text: $editDescription)
                Button("Save") {
                    if let dataset = editingDataset {
                        Task {
                            try? await vmManager.updateDatasetDescription(
                                id: dataset.id,
                                description: editDescription
                            )
                            editingDataset = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    editingDataset = nil
                }
            } message: {
                Text("Update the description for this preprocessed object")
            }
            .alert("Delete Dataset", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let dataset = datasetToDelete {
                        Task {
                            try? await vmManager.deleteDataset(id: dataset.id)
                            datasetToDelete = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    datasetToDelete = nil
                }
            } message: {
                if let dataset = datasetToDelete {
                    Text("Are you sure you want to delete \"\(dataset.description)\"? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this dataset?")
                }
            }
            .alert("Inference Result", isPresented: $showingInferenceAlert) {
                Button("OK") {
                    inferenceMessage = ""
                }
            } message: {
                Text(inferenceMessage)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(inferenceConfiguration: $inferenceConfiguration)
            }
        }
    }
}

/// Settings view for app configuration
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var inferenceConfiguration: HomeView.InferenceConfig
    
    var body: some View {
        NavigationView {
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
                
                VStack(spacing: 30) {
                    // Inference Configuration Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Inference Configuration")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        
                        ForEach(HomeView.InferenceConfig.allCases, id: \.self) { config in
                            Button(action: {
                                inferenceConfiguration = config
                            }) {
                                HStack {
                                    Text(config.rawValue)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    if inferenceConfiguration == config {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 20))
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.white.opacity(0.3))
                                            .font(.system(size: 20))
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(inferenceConfiguration == config ? Color.green : Color.white.opacity(0.2), lineWidth: inferenceConfiguration == config ? 2 : 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 30)
                    
                    Spacer()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black.opacity(0.3), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

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

#Preview {
    HomeView()
}
