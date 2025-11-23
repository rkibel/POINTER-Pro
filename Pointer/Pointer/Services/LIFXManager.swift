//
//  LIFXManager.swift
//  Pointer
//
//  Created by Ron Kibel on 11/11/25.
//

import Foundation
import Combine

/// Manager for controlling LIFX lightbulbs based on object pose data
@MainActor
class LIFXManager: ObservableObject {
    @Published var isEnabled = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var isLightOn = false  // Track current light state
    
    private var lifxToken: String?
    private let baseURL = "https://api.lifx.com/v1"
    private var cancellables = Set<AnyCancellable>()
    
    // Rate limiting and smoothing
    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval = 0.15 // Update every 150ms (less frequent = smoother)
    
    // Track last known pose state
    private var lastPoseData: PoseData?
    private var pendingLightState: Bool?  // Track if we have a pending state change
    
    // Smoothing for brightness to reduce flickering
    private var currentBrightness: Double = 0.5
    private let brightnessSmoothing: Double = 0.3  // Lower = smoother, higher = more responsive
    
    init() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        // Try to load LIFX token from .env file or environment
        if let envPath = Bundle.main.path(forResource: ".env", ofType: nil),
           let envContents = try? String(contentsOfFile: envPath, encoding: .utf8) {
            
            envContents.enumerateLines { line, _ in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("LIFX_TOKEN=") {
                    self.lifxToken = String(trimmed.dropFirst("LIFX_TOKEN=".count))
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        
        // Check if token is available
        if lifxToken != nil && lifxToken != "YOUR_LIFX_TOKEN_HERE" {
            isConnected = true
        } else {
            errorMessage = "LIFX token not configured"
        }
    }
    
    /// Update LIFX bulb based on 6DOF pose data (or lack thereof)
    func updateFromPose(_ poseData: PoseData?) {
        guard isEnabled, isConnected else { return }
        
        // Handle state transitions
        if poseData == nil && lastPoseData != nil {
            // Object just disappeared - turn off immediately
            print("🔴 LIFX: Object lost, turning off")
            turnOff()
            lastPoseData = nil
            return
        }
        
        if poseData != nil && lastPoseData == nil {
            // Object just appeared - turn on immediately
            print("🟢 LIFX: Object detected, turning on")
            turnOn()
            lastPoseData = poseData
            // Don't update colors yet, let the light turn on first
            return
        }
        
        // If no pose data and already off, nothing to do
        guard let poseData = poseData else {
            return
        }
        
        // We have pose data and light is on - update colors/brightness
        lastPoseData = poseData
        
        // Rate limiting - only update every 150ms to reduce API calls and flickering
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = now
        
        // Extract 6DOF data
        guard let position = poseData.getPosition() else {
            return
        }
        
        // Map pose to light parameters
        // Brightness: Based on Z distance (closer = brighter)
        // Range: 0.5m (bright) to 2.0m (dim)
        let distance = abs(position.z)
        let targetBrightness = mapValue(distance, from: (0.5, 2.0), to: (1.0, 0.3))
        
        // Smooth brightness changes to reduce flickering
        currentBrightness = currentBrightness * (1.0 - brightnessSmoothing) + targetBrightness * brightnessSmoothing
        
        // Hue: Based on X position (left-right movement)
        // Range: -0.5m (red) to +0.5m (blue)
        let hue = mapValue(position.x, from: (-0.5, 0.5), to: (0.0, 240.0))
        
        // Saturation: Based on Y position (up-down movement)
        // Range: -0.5m (low saturation) to +0.5m (high saturation)
        let saturation = mapValue(position.y, from: (-0.5, 0.5), to: (0.4, 1.0))
        
        // Only send update if light should be on
        guard isLightOn else { return }
        
        // Send update to LIFX with smoothed brightness
        sendLightUpdate(
            hue: hue,
            saturation: saturation,
            brightness: currentBrightness,
            duration: 0.2
        )
    }
    
    /// Map a value from one range to another, with clamping
    private func mapValue(_ value: Double, from: (Double, Double), to: (Double, Double)) -> Double {
        let clamped = max(from.0, min(from.1, value))
        let normalized = (clamped - from.0) / (from.1 - from.0)
        return to.0 + normalized * (to.1 - to.0)
    }
    
    /// Send light state update to LIFX API
    private func sendLightUpdate(hue: Double, saturation: Double, brightness: Double, duration: Double) {
        guard let token = lifxToken else { return }
        
        guard let url = URL(string: "\(baseURL)/lights/all/state") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "color": "hue:\(Int(hue)) saturation:\(saturation) brightness:\(brightness)",
            "duration": duration,
            "fast": true
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "LIFX update failed: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse,
                          !(200...299).contains(httpResponse.statusCode) {
                    self?.errorMessage = "LIFX API error: \(httpResponse.statusCode)"
                } else {
                    self?.errorMessage = nil
                }
            }
        }.resume()
    }
    
    /// Turn lights on when starting
    func turnOn() {
        guard let token = lifxToken else { return }
        
        // Set state immediately to prevent multiple calls
        isLightOn = true
        
        guard let url = URL(string: "\(baseURL)/lights/all/state") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "power": "on",
            "brightness": 0.5,
            "duration": 0.3
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                print("❌ LIFX turn on failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isLightOn = false  // Revert state on failure
                }
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                print("❌ LIFX turn on error: \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    self?.isLightOn = false  // Revert state on failure
                }
            } else {
                print("✅ LIFX turned on")
            }
        }.resume()
    }
    
    /// Turn lights off when stopping
    func turnOff() {
        guard let token = lifxToken else { return }
        
        // Set state immediately to prevent multiple calls
        isLightOn = false
        
        guard let url = URL(string: "\(baseURL)/lights/all/state") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "power": "off",
            "duration": 0.3
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                print("❌ LIFX turn off failed: \(error.localizedDescription)")
                // Don't revert state on turn off failure - better to be off than stuck on
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                print("❌ LIFX turn off error: \(httpResponse.statusCode)")
            } else {
                print("✅ LIFX turned off")
            }
        }.resume()
    }
}
