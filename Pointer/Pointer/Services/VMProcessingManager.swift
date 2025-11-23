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
    
    private var fetchTask: Task<Void, Never>?
    private let urlSession: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: configuration)
    }
    
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
            
            await saveDataset(PreprocessedDataset(id: datasetId, description: description, timestamp: Date(), imageCount: images.count))
            return datasetId
        }
    }
    
    /// Fetch list of available datasets from VM
    func fetchAvailableDatasets() async throws {
        fetchTask?.cancel()
        
        guard let apiURL = Config.vmApiURL else {
            await MainActor.run { self.availableDatasets = [] }
            throw VMError.notConfigured
        }
        
        var thrownError: Error?
        
        fetchTask = Task {
            await updateProgress("Fetching datasets...")
            
            do {
                let url = URL(string: "\(apiURL)/datasets")!
                let (data, response) = try await urlSession.data(from: url)
                
                guard !Task.isCancelled else { return }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    thrownError = VMError.connectionFailed("Failed to fetch datasets")
                    return
                }
                
                let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let datasetsArray = responseDict?["datasets"] as? [[String: Any]] else {
                    thrownError = VMError.invalidResponse
                    return
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
                
                // Server is source of truth - sort by timestamp
                let sortedDatasets = datasets.sorted { $0.timestamp > $1.timestamp }
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.availableDatasets = sortedDatasets
                    self.processingProgress = ""
                }
            } catch is CancellationError {
                // Keep existing data on cancellation
            } catch {
                thrownError = error
                await MainActor.run {
                    self.availableDatasets = []
                    self.processingProgress = ""
                }
            }
        }
        await fetchTask?.value
        
        if let error = thrownError {
            throw error
        }
    }

    /// Delete a dataset from the VM
    func deleteDataset(id datasetId: String) async throws {
        if let apiURL = Config.vmApiURL, let url = URL(string: "\(apiURL)/dataset/\(datasetId)") {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try await performRequest(request)
        }

        // Remove from current list
        await MainActor.run { 
            self.availableDatasets.removeAll { $0.id == datasetId }
        }
    }
    
    /// Update the description (text prompt) of a dataset
    func updateDatasetDescription(id datasetId: String, description: String) async throws {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        var request = URLRequest(url: URL(string: "\(apiURL)/dataset/\(datasetId)/text_prompt")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text_prompt": description])
        
        _ = try await performRequest(request)
        
        // Update in current list
        await MainActor.run {
            if let index = self.availableDatasets.firstIndex(where: { $0.id == datasetId }) {
                self.availableDatasets[index] = PreprocessedDataset(
                    id: datasetId, 
                    description: description,
                    timestamp: self.availableDatasets[index].timestamp, 
                    imageCount: self.availableDatasets[index].imageCount
                )
            }
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
    
    /// Fetch list of image filenames for a dataset
    func getDatasetImageFilenames(datasetId: String) async throws -> (referenceImages: [String], verificationImages: [String]) {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        let url = URL(string: "\(apiURL)/dataset/\(datasetId)/images")!
        let (data, response) = try await urlSession.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VMError.connectionFailed("Failed to fetch image list")
        }
        
        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let referenceImages = responseDict["reference_images"] as? [String],
              let verificationImages = responseDict["verification_images"] as? [String] else {
            throw VMError.invalidResponse
        }
        
        return (referenceImages, verificationImages)
    }
    
    /// Load a single image from a dataset
    func loadDatasetImage(datasetId: String, imageType: String, filename: String) async throws -> UIImage {
        guard let apiURL = Config.vmApiURL else { throw VMError.notConfigured }
        
        // imageType should be "reference_data" or "verification"
        let url = URL(string: "\(apiURL)/dataset/\(datasetId)/image/\(imageType)/\(filename)")!
        let (data, response) = try await urlSession.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VMError.connectionFailed("Failed to fetch image: \(filename)")
        }
        
        guard let image = UIImage(data: data) else {
            throw VMError.invalidResponse
        }
        
        return image
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
        let (data, response) = try await urlSession.data(for: request)
        
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
        
    private func saveDataset(_ dataset: PreprocessedDataset) async {
        await MainActor.run {
            // Remove any existing entry with same ID
            self.availableDatasets.removeAll { $0.id == dataset.id }
            // Add new dataset
            self.availableDatasets.append(dataset)
            // Sort by timestamp
            self.availableDatasets.sort { $0.timestamp > $1.timestamp }
        }
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
