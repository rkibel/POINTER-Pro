//
//  SettingsView.swift
//  Pointer
//
//  Created by Ron Kibel on 11/3/25.
//

import SwiftUI

/// Settings view for app configuration
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var inferenceConfiguration: InferenceConfig
    @Binding var isDeveloperMode: Bool
    
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
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Developer Mode Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Developer Mode")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Toggle(isOn: $isDeveloperMode) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enable Developer Mode")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Stream without running inference scripts")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .tint(.cyan)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isDeveloperMode ? Color.cyan : Color.white.opacity(0.2), lineWidth: isDeveloperMode ? 2 : 1)
                            )
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 30)
                        
                        // Inference Configuration Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Inference Configuration")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            
                            ForEach(InferenceConfig.allCases, id: \.self) { config in
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
                        .padding(.bottom, 30)
                    }
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

/// Inference configuration options
enum InferenceConfig: String, CaseIterable {
    case demo = "Demo"
    case light = "Smart Light"
    case designVisualization = "Design Visualization"
    case digitalWorkspace = "Digital Workspace"
    case supermarket = "Supermarket"
    case languageLearning = "Language Learning"
    case popUp = "Pop-up"
}
