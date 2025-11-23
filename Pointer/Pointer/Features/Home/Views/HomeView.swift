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
    @State private var inferenceConfiguration: InferenceConfig = .demo
    @State private var isDeveloperMode = false
    @State private var isRefreshing = false
    
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
                    
                    // Scrollable content area with pull-to-refresh
                    ScrollView {
                        VStack(spacing: 0) {
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
                            
                            // Preprocessed Datasets Section - Always visible with count
                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: {
                                    if !vmManager.availableDatasets.isEmpty {
                                        showingDatasets.toggle()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 20)
                                            .rotationEffect(.degrees(showingDatasets ? 90 : 0))
                                            .animation(.easeInOut(duration: 0.2), value: showingDatasets)
                                            .opacity(vmManager.availableDatasets.isEmpty ? 0.3 : 1.0)
                                        Text("Preprocessed Objects (\(vmManager.availableDatasets.count))")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                }
                                .disabled(vmManager.availableDatasets.isEmpty)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 12)
                                
                                // Expandable list or empty message
                                if !vmManager.availableDatasets.isEmpty && showingDatasets {
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
                                    .frame(height: min(CGFloat(vmManager.availableDatasets.count) * 110, 270))
                                    .padding(.horizontal, 40)
                                } else if vmManager.availableDatasets.isEmpty {
                                    Text("No preprocessed objects yet. Scan an object to get started!")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.white.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                        .padding(.vertical, 20)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .refreshable {
                        await refreshDatasets()
                    }
                    
                    Spacer(minLength: 0)
                    
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
                        
                        // Inference Button - Enabled when a dataset is selected or in developer mode
                        ZStack {
                            // Hidden NavigationLink
                            NavigationLink(
                                destination: StreamingView(
                                    datasetId: selectedDataset?.id ?? "developer_mode",
                                    isDeveloperMode: isDeveloperMode,
                                    inferenceConfiguration: inferenceConfiguration
                                ),
                                isActive: $navigateToStreaming
                            ) {
                                EmptyView()
                            }
                            .hidden()
                            
                            // Visible button
                            Button(action: {
                                // In developer mode, allow streaming without dataset selection
                                if isDeveloperMode {
                                    navigateToStreaming = true
                                    return
                                }
                                
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
                                    (selectedDataset != nil || isDeveloperMode) ?
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
                                .foregroundColor((selectedDataset != nil || isDeveloperMode) ? .white : .white.opacity(0.4))
                                .cornerRadius(12)
                                .overlay(
                                    (selectedDataset == nil && !isDeveloperMode) ?
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1) : nil
                                )
                            }
                            .disabled((selectedDataset == nil && !isDeveloperMode) || isRunningInference)
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
                Task { await refreshDatasets() }
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
                SettingsView(inferenceConfiguration: $inferenceConfiguration, isDeveloperMode: $isDeveloperMode)
            }
        }
    }
    
    private func refreshDatasets() async {
        isRefreshing = true
        try? await vmManager.fetchAvailableDatasets()
        isRefreshing = false
    }
}

#Preview {
    HomeView()
}
