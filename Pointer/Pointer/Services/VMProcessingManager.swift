//
//  VMProcessingManager.swift
//  Pointer
//
//  Created by Ron Kibel on 11/2/25.
//

import Foundation
import UIKit
import Combine

/// Manages communication with GCloud VM API for preprocessing operations
class VMProcessingManager: ObservableObject {
    
    @Published var isProcessing = false
    @Published var processingProgress: String = ""
    @Published var availableDatasets: [PreprocessedDataset] = []
    
    enum VMError: LocalizedError {
        case notConfigured, noImages, invalidDescription, invalidResponse
        case connectionFailed(String), uploadFailed(String), processingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .notConfigured: "VM API is not configured. Please add VM_API_URL to .env file."
            case .connectionFailed(let msg): "Connection failed: \(msg)"
            case .uploadFailed(let msg): "Upload failed: \(msg)"
            case .processingFailed(let msg): "Processing failed: \(msg)"
            case .noImages: "No images to process"
            case .invalidDescription: "Please provide a valid object description"
            case .invalidResponse: "Invalid response from server"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Upload images to VM and trigger preprocessing via API
    func processImages(_ images: [UIImage], description: String) async throws -> String {
        guard !images.isEmpty else { throw VMError.noImages }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { throw VMError.invalidDescription }
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        return try await withProcessing("Preparing images...") {
            var request = URLRequest(url: URL(string: "\(apiURL)/preprocess")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600
            
            await updateProgress("Encoding images...")
            
            let imageDataArray = try images.enumerated().map { index, image -> [String: Any] in
                guard let orientedImage = image.normalizedOrientation() else {
                    throw VMError.uploadFailed("Failed to normalize orientation for image \(index)")
                }
                guard let jpegData = orientedImage.jpegData(compressionQuality: 1.0) else {
                    throw VMError.uploadFailed("Failed to convert image \(index) to JPEG")
                }
                return ["index": index, "data": jpegData.base64EncodedString(), "format": "jpg"]
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "description": description,
                "images": imageDataArray
            ])
            
            await updateProgress("Uploading to VM...")
            let responseDict = try await performRequest(request)
            
            guard let datasetId = responseDict["dataset_id"] as? String else {
                throw VMError.invalidResponse
            }
            
            await saveDataset(PreprocessedDataset(id: datasetId, description: description, imageCount: images.count))
            return datasetId
        }
    }
    
    /// Fetch list of available datasets from VM
    func fetchAvailableDatasets() async throws {
        guard let apiURL = Config.vmApiURL else {
            await MainActor.run { self.availableDatasets = loadLocalDatasets() }
            return
        }
        
        await updateProgress("Fetching datasets...")
        
        do {
            let url = URL(string: "\(apiURL)/datasets")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw VMError.connectionFailed("Failed to fetch datasets")
            }
            
            let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let datasetsArray = responseDict?["datasets"] as? [[String: Any]] else {
                throw VMError.invalidResponse
            }
            
            let formatter = ISO8601DateFormatter()
            let datasets = datasetsArray.compactMap { dict -> PreprocessedDataset? in
                guard let id = dict["id"] as? String,
                      let description = dict["description"] as? String,
                      let timestampString = dict["timestamp"] as? String,
                      let imageCount = dict["imageCount"] as? Int else { return nil }
                
                let timestamp = formatter.date(from: timestampString) ?? Date()
                return PreprocessedDataset(id: id, description: description, timestamp: timestamp, imageCount: imageCount)
            }
            
            let allDatasets = mergeDatasetsUnique(remote: datasets, local: loadLocalDatasets())
            await MainActor.run {
                self.availableDatasets = allDatasets
                self.processingProgress = ""
            }
        } catch {
            await MainActor.run {
                self.availableDatasets = loadLocalDatasets()
                self.processingProgress = ""
            }
        }
    }

    /// Delete a dataset from the VM and local storage
    func deleteDataset(id datasetId: String) async throws {
        if let apiURL = Config.vmApiURL, let url = URL(string: "\(apiURL)/dataset/\(datasetId)") {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try await performRequest(request)
        }

        var datasets = loadLocalDatasets()
        datasets.removeAll { $0.id == datasetId }
        if let encoded = try? JSONEncoder().encode(datasets) {
            UserDefaults.standard.set(encoded, forKey: "preprocessed_datasets")
        }
        await MainActor.run { self.availableDatasets = datasets }
    }
    
    /// Update the description (text prompt) of a dataset
    func updateDatasetDescription(id datasetId: String, description: String) async throws {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        var request = URLRequest(url: URL(string: "\(apiURL)/dataset/\(datasetId)/text_prompt")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text_prompt": description])
        
        _ = try await performRequest(request)
        
        var datasets = loadLocalDatasets()
        if let index = datasets.firstIndex(where: { $0.id == datasetId }) {
            datasets[index] = PreprocessedDataset(
                id: datasetId, description: description,
                timestamp: datasets[index].timestamp, imageCount: datasets[index].imageCount
            )
            
            if let encoded = try? JSONEncoder().encode(datasets) {
                UserDefaults.standard.set(encoded, forKey: "preprocessed_datasets")
            }
            await MainActor.run { self.availableDatasets = datasets.sorted { $0.timestamp > $1.timestamp } }
        }
    }
    
    /// Run inference on a preprocessed dataset
    func runInference(datasetId: String) async throws -> String {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        return try await withProcessing("Starting inference...") {
            var request = URLRequest(url: URL(string: "\(apiURL)/inference/\(datasetId)")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            
            await updateProgress("Running inference on VM...")
            let responseDict = try await performRequest(request)
            
            guard let message = responseDict["message"] as? String else {
                throw VMError.invalidResponse
            }
            return message
        }
    }
    
    /// Start inference in background for a dataset
    func startInference(datasetId: String) async throws -> String {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        var request = URLRequest(url: URL(string: "\(apiURL)/inference/\(datasetId)/start")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        
        let responseDict = try await performRequest(request)
        guard let message = responseDict["message"] as? String else {
            throw VMError.invalidResponse
        }
        return message
    }
    
    /// Stop running inference for a dataset
    func stopInference(datasetId: String) async throws -> String {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        var request = URLRequest(url: URL(string: "\(apiURL)/inference/\(datasetId)/stop")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        
        let responseDict = try await performRequest(request)
        guard let message = responseDict["message"] as? String else {
            throw VMError.invalidResponse
        }
        return message
    }
    
    // MARK: - Private Helpers
    
    /// Execute a block with processing state management
    private func withProcessing<T>(_ message: String, _ block: () async throws -> T) async rethrows -> T {
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = message
        }
        defer {
            Task { @MainActor in
                self.isProcessing = false
                self.processingProgress = ""
            }
        }
        return try await block()
    }
    
    /// Update progress message
    private func updateProgress(_ message: String) async {
        await MainActor.run { self.processingProgress = message }
    }
    
    /// Perform HTTP request and return parsed JSON response
    private func performRequest(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VMError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorDict["error"] as? String {
                throw VMError.processingFailed(errorMessage)
            }
            throw VMError.processingFailed("HTTP \(httpResponse.statusCode)")
        }
        
        guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VMError.invalidResponse
        }
        
        return responseDict
    }
    
    private func mergeDatasetsUnique(remote: [PreprocessedDataset], local: [PreprocessedDataset]) -> [PreprocessedDataset] {
        var merged: [String: PreprocessedDataset] = [:]
        local.forEach { merged[$0.id] = $0 }
        remote.forEach { merged[$0.id] = $0 }  // Remote overwrites local
        return merged.values.sorted { $0.timestamp > $1.timestamp }
    }
        
    private func saveDataset(_ dataset: PreprocessedDataset) async {
        var datasets = loadLocalDatasets()
        datasets.removeAll { $0.id == dataset.id }
        datasets.append(dataset)
        
        if let encoded = try? JSONEncoder().encode(datasets) {
            UserDefaults.standard.set(encoded, forKey: "preprocessed_datasets")
        }
        
        await MainActor.run {
            self.availableDatasets = datasets.sorted { $0.timestamp > $1.timestamp }
        }
    }
    
    private func loadLocalDatasets() -> [PreprocessedDataset] {
        guard let data = UserDefaults.standard.data(forKey: "preprocessed_datasets"),
              let datasets = try? JSONDecoder().decode([PreprocessedDataset].self, from: data) else {
            return []
        }
        return datasets.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - UIImage Extension

extension UIImage {
    /// Normalize image orientation by redrawing it correctly oriented
    /// This ensures EXIF orientation metadata is applied to the actual pixel data
    func normalizedOrientation() -> UIImage? {
        if imageOrientation == .up { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
