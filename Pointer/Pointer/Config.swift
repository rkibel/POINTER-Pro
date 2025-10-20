//
//  Config.swift
//  Pointer
//
//  Created by Ron Kibel on 10/20/25.
//

import Foundation

enum Config {
    /// Load configuration from .env file or environment variables
    private static let configuration: [String: String] = {
        var config: [String: String] = [:]
        
        // Try to load from .env file first
        if let envPath = Bundle.main.path(forResource: ".env", ofType: nil),
           let envContents = try? String(contentsOfFile: envPath, encoding: .utf8) {
            
            envContents.enumerateLines { line, _ in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip empty lines and comments
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
                
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    config[key] = value
                }
            }
        }
        
        // Merge with environment variables (env vars take precedence)
        for (key, value) in ProcessInfo.processInfo.environment {
            config[key] = value
        }
        
        return config
    }()
    
    /// Helper function to get environment variable
    private static func getEnvVariable(_ key: String) -> String? {
        return configuration[key]
    }
    
    /// LiveKit server URL (wss://your-server.com)
    static var liveKitURL: String {
        guard let url = getEnvVariable("LIVEKIT_URL") else {
            fatalError("LIVEKIT_URL not set in .env file")
        }
        return url
    }
    
    /// LiveKit access token
    static var liveKitToken: String {
        guard let token = getEnvVariable("LIVEKIT_TOKEN") else {
            fatalError("LIVEKIT_TOKEN not set in .env file")
        }
        return token
    }
    
    /// Room name for LiveKit
    static var roomName: String {
        return getEnvVariable("LIVEKIT_ROOM") ?? "live"
    }
}

