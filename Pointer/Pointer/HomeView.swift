//
//  HomeView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/22/25.
//

import SwiftUI

/// Main home page with navigation to different app features
struct HomeView: View {
    @State private var navigateToStreaming = false
    @State private var navigateToScanning = false
    
    var body: some View {
        NavigationStack {
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
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Logo/Title Section
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
                    .padding(.bottom, 60)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 20) {
                        // Scan Objects Button
                        NavigationLink(destination: ScanObjectsView()) {
                            HStack {
                                Image(systemName: "viewfinder.circle.fill")
                                    .font(.system(size: 20))
                                Text("Scan Objects")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green, Color.cyan]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // Inference Button
                        NavigationLink(destination: StreamingView()) {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                Text("Inference")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                    
                    // Description
                    Text("Object-centric virtual overlays using\nreal-time pose estimation")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 50)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    HomeView()
}
