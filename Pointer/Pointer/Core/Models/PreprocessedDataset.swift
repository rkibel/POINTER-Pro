//
//  PreprocessedDataset.swift
//  Pointer
//
//  Created by Ron Kibel on 11/2/25.
//

import Foundation

/// Represents a preprocessed object dataset stored on the VM
struct PreprocessedDataset: Identifiable, Codable {
    let id: String
    let description: String
    let timestamp: Date
    let imageCount: Int
    
    /// Computed property for display date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    /// Initialize with current timestamp
    init(id: String, description: String, imageCount: Int) {
        self.id = id
        self.description = description
        self.timestamp = Date()
        self.imageCount = imageCount
    }
    
    /// Initialize with specific timestamp (for decoding)
    init(id: String, description: String, timestamp: Date, imageCount: Int) {
        self.id = id
        self.description = description
        self.timestamp = timestamp
        self.imageCount = imageCount
    }
}
