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
    
    // MARK: - Error Types
    
    enum VMError: LocalizedError {
        case notConfigured
        case connectionFailed(String)
        case uploadFailed(String)
        case processingFailed(String)
        case noImages
        case invalidDescription
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "VM API is not configured. Please add VM_API_URL to .env file."
            case .connectionFailed(let msg):
                return "Connection failed: \(msg)"
            case .uploadFailed(let msg):
                return "Upload failed: \(msg)"
            case .processingFailed(let msg):
                return "Processing failed: \(msg)"
            case .noImages:
                return "No images to process"
            case .invalidDescription:
                return "Please provide a valid object description"
            case .invalidResponse:
                return "Invalid response from server"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Upload images to VM and trigger preprocessing via API
    /// - Parameters:
    ///   - images: Array of UIImages to process
    ///   - description: Text description of the object
    /// - Returns: Dataset ID if successful
    func processImages(_ images: [UIImage], description: String) async throws -> String {
        guard !images.isEmpty else {
            throw VMError.noImages
        }
        
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw VMError.invalidDescription
        }
        
        guard let apiURL = Config.vmApiURL else {
            throw VMError.notConfigured
        }
        
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = "Preparing images..."
        }
        
        do {
            // Prepare request
            let url = URL(string: "\(apiURL)/preprocess")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600 // 10 minute timeout for processing
            
            // Convert images to base64
            await MainActor.run {
                self.processingProgress = "Encoding images..."
            }
            
            var imageDataArray: [[String: Any]] = []
            for (index, image) in images.enumerated() {
                guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
                    throw VMError.uploadFailed("Failed to convert image \(index) to JPEG")
                }
                let base64String = jpegData.base64EncodedString()
                imageDataArray.append([
                    "index": index,
                    "data": base64String
                ])
            }
            
            // Create request body
            let requestBody: [String: Any] = [
                "description": description,
                "images": imageDataArray
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Upload and process
            await MainActor.run {
                self.processingProgress = "Uploading to VM..."
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VMError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorDict["error"] as? String {
                    throw VMError.processingFailed(errorMessage)
                }
                throw VMError.processingFailed("HTTP \(httpResponse.statusCode)")
            }
            
            // Parse response
            guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let datasetId = responseDict["dataset_id"] as? String else {
                throw VMError.invalidResponse
            }
            
            // Save dataset metadata locally
            let dataset = PreprocessedDataset(
                id: datasetId,
                description: description,
                imageCount: images.count
            )
            await saveDataset(dataset)
            
            await MainActor.run {
                self.isProcessing = false
                self.processingProgress = ""
            }
            
            return datasetId
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.processingProgress = ""
            }
            throw error
        }
    }
    
    /// Fetch list of available datasets from VM
    func fetchAvailableDatasets() async throws {
        guard let apiURL = Config.vmApiURL else {
            // If no API configured, just load from local storage
            let datasets = loadLocalDatasets()
            await MainActor.run {
                self.availableDatasets = datasets
            }
            return
        }
        
        await MainActor.run {
            self.processingProgress = "Fetching datasets..."
        }
        
        do {
            let url = URL(string: "\(apiURL)/datasets")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw VMError.connectionFailed("Failed to fetch datasets")
            }
            
            let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let datasetsArray = responseDict?["datasets"] as? [[String: Any]] else {
                throw VMError.invalidResponse
            }
            
            var datasets: [PreprocessedDataset] = []
            for dict in datasetsArray {
                if let id = dict["id"] as? String,
                   let description = dict["description"] as? String,
                   let timestampString = dict["timestamp"] as? String,
                   let imageCount = dict["imageCount"] as? Int {
                    
                    let formatter = ISO8601DateFormatter()
                    let timestamp = formatter.date(from: timestampString) ?? Date()
                    
                    let dataset = PreprocessedDataset(
                        id: id,
                        description: description,
                        timestamp: timestamp,
                        imageCount: imageCount
                    )
                    datasets.append(dataset)
                }
            }
            
            // Merge with local datasets
            let localDatasets = loadLocalDatasets()
            let allDatasets = mergeDatasetsUnique(remote: datasets, local: localDatasets)
            
            await MainActor.run {
                self.availableDatasets = allDatasets
                self.processingProgress = ""
            }
            
        } catch {
            // Fall back to local datasets on error
            let datasets = loadLocalDatasets()
            await MainActor.run {
                self.availableDatasets = datasets
                self.processingProgress = ""
            }
        }
    }

    /// Delete a dataset from the VM and local storage
    func deleteDataset(id datasetId: String) async throws {
        // If API configured, call DELETE endpoint
        if let apiURL = Config.vmApiURL, let url = URL(string: "\(apiURL)/dataset/\(datasetId)") {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw VMError.processingFailed("Failed to delete dataset on server")
            }
        }

        // Remove from local storage
        var datasets = loadLocalDatasets()
        datasets.removeAll { $0.id == datasetId }
        if let encoded = try? JSONEncoder().encode(datasets) {
            UserDefaults.standard.set(encoded, forKey: "preprocessed_datasets")
        }

        await MainActor.run {
            self.availableDatasets = datasets
        }
    }
    
    /// Update the description (text prompt) of a dataset
    func updateDatasetDescription(id datasetId: String, description: String) async throws {
        guard let apiURL = Config.vmApiURL,
              let url = URL(string: "\(apiURL)/dataset/\(datasetId)/text_prompt") else {
            throw VMError.notConfigured
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = ["text_prompt": description]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw VMError.processingFailed("Failed to update description on server")
        }
        
        // Update local storage
        var datasets = loadLocalDatasets()
        if let index = datasets.firstIndex(where: { $0.id == datasetId }) {
            datasets[index] = PreprocessedDataset(
                id: datasetId,
                description: description,
                timestamp: datasets[index].timestamp,
                imageCount: datasets[index].imageCount
            )
            
            if let encoded = try? JSONEncoder().encode(datasets) {
                UserDefaults.standard.set(encoded, forKey: "preprocessed_datasets")
            }
            
            await MainActor.run {
                self.availableDatasets = datasets.sorted { $0.timestamp > $1.timestamp }
            }
        }
    }
    
    /// Run inference on a preprocessed dataset
    /// - Parameter datasetId: The ID of the dataset to run inference on
    /// - Returns: Success message or throws error
    func runInference(datasetId: String) async throws -> String {
        guard let apiURL = Config.vmApiURL else {
            throw VMError.notConfigured
        }
        
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = "Starting inference..."
        }
        
        do {
            let url = URL(string: "\(apiURL)/inference/\(datasetId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 600 // 10 minute timeout
            
            await MainActor.run {
                self.processingProgress = "Running inference on VM..."
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VMError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = errorResponse["error"] as? String {
                    throw VMError.processingFailed(errorMsg)
                }
                throw VMError.processingFailed("HTTP \(httpResponse.statusCode)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? String else {
                throw VMError.invalidResponse
            }
            
            await MainActor.run {
                self.isProcessing = false
                self.processingProgress = ""
            }
            
            return message
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.processingProgress = ""
            }
            throw error
        }
    }
    
    /// Start inference in background for a dataset
    /// - Parameter datasetId: The ID of the dataset to run inference on
    /// - Returns: Success message or throws error
    func startInference(datasetId: String) async throws -> String {
        guard let apiURL = Config.vmApiURL else {
            throw VMError.notConfigured
        }
        
        do {
            let url = URL(string: "\(apiURL)/inference/\(datasetId)/start")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VMError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = errorResponse["error"] as? String {
                    throw VMError.processingFailed(errorMsg)
                }
                throw VMError.processingFailed("HTTP \(httpResponse.statusCode)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? String else {
                throw VMError.invalidResponse
            }
            
            return message
            
        } catch {
            throw error
        }
    }
    
    /// Stop running inference for a dataset
    /// - Parameter datasetId: The ID of the dataset to stop inference for
    /// - Returns: Success message or throws error
    func stopInference(datasetId: String) async throws -> String {
        guard let apiURL = Config.vmApiURL else {
            throw VMError.notConfigured
        }
        
        do {
            let url = URL(string: "\(apiURL)/inference/\(datasetId)/stop")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VMError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = errorResponse["error"] as? String {
                    throw VMError.processingFailed(errorMsg)
                }
                throw VMError.processingFailed("HTTP \(httpResponse.statusCode)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? String else {
                throw VMError.invalidResponse
            }
            
            return message
            
        } catch {
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func mergeDatasetsUnique(remote: [PreprocessedDataset], local: [PreprocessedDataset]) -> [PreprocessedDataset] {
        var merged: [String: PreprocessedDataset] = [:]
        
        // Add local first
        for dataset in local {
            merged[dataset.id] = dataset
        }
        
        // Add remote (overwriting local if same ID)
        for dataset in remote {
            merged[dataset.id] = dataset
        }
        
        return merged.values.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Local Storage
    
    private func saveDataset(_ dataset: PreprocessedDataset) async {
        var datasets = loadLocalDatasets()
        
        // Remove existing dataset with same ID
        datasets.removeAll { $0.id == dataset.id }
        
        // Add new dataset
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
