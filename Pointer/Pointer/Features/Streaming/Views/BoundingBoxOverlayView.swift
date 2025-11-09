//
//  BoundingBoxOverlayView.swift
//  Pointer
//
//  Created by Ron Kibel on 10/23/25.
//

import SwiftUI
import CoreGraphics
import UIKit

/// Overlay view to display 2D bounding box from pose estimation
struct BoundingBoxOverlayView: View {
    let poseData: PoseData?
    let imageSize: CGSize
    let showDetectionBox: Bool
    let showSegmentation: Bool
    let showPoseEstimation: Bool
    
    var body: some View {
        GeometryReader { geometry in
            if let data = poseData {
                let projectedPoints = data.getProjectedBoundingBox()
                
                if projectedPoints.count == 8 {
                    Canvas { context, size in
                        // Calculate aspect-fit scaling with letterboxing
                        // The video is 720x1280 (width x height) displayed in .fit mode
                        let imageAspect = imageSize.width / imageSize.height
                        let viewAspect = size.width / size.height
                        
                        var scale: CGFloat
                        var offsetX: CGFloat = 0
                        var offsetY: CGFloat = 0
                        
                        if viewAspect > imageAspect {
                            // View is wider than image - letterbox on left/right
                            scale = size.height / imageSize.height
                            let scaledWidth = imageSize.width * scale
                            offsetX = (size.width - scaledWidth) / 2
                        } else {
                            // View is taller than image - letterbox on top/bottom
                            scale = size.width / imageSize.width
                            let scaledHeight = imageSize.height * scale
                            offsetY = (size.height - scaledHeight) / 2
                        }
                        
                        // Draw segmentation mask if enabled
                        if showSegmentation, let maskData = data.decodeMask(), 
                           let maskShape = data.maskShape, maskShape.count == 2 {
                            let maskHeight = maskShape[0]
                            let maskWidth = maskShape[1]
                            
                            drawSegmentationMask(
                                context: &context,
                                maskData: maskData,
                                maskWidth: maskWidth,
                                maskHeight: maskHeight,
                                scale: scale,
                                offsetX: offsetX,
                                offsetY: offsetY
                            )
                        }
                        
                        // Draw detection box if enabled
                        if showDetectionBox, let detectionBox = data.getDetectionBox() {
                            let scaledRect = CGRect(
                                x: detectionBox.origin.x * scale + offsetX,
                                y: detectionBox.origin.y * scale + offsetY,
                                width: detectionBox.width * scale,
                                height: detectionBox.height * scale
                            )
                            context.stroke(
                                Path(roundedRect: scaledRect, cornerRadius: 4),
                                with: .color(.green),
                                lineWidth: 3
                            )
                        }
                        
                        // Draw 3D bounding box if enabled
                        if showPoseEstimation {
                            // Transform points accounting for letterboxing
                            let scaledPoints = projectedPoints.map { point in
                                CGPoint(
                                    x: point.x * scale + offsetX,
                                    y: point.y * scale + offsetY
                                )
                            }
                            
                            // Draw 3D bounding box edges
                            // Bottom face (points 0-3)
                            drawLine(context: context, from: scaledPoints[0], to: scaledPoints[1], color: .cyan)
                            drawLine(context: context, from: scaledPoints[1], to: scaledPoints[2], color: .cyan)
                            drawLine(context: context, from: scaledPoints[2], to: scaledPoints[3], color: .cyan)
                            drawLine(context: context, from: scaledPoints[3], to: scaledPoints[0], color: .cyan)
                            
                            // Top face (points 4-7)
                            drawLine(context: context, from: scaledPoints[4], to: scaledPoints[5], color: .green)
                            drawLine(context: context, from: scaledPoints[5], to: scaledPoints[6], color: .green)
                            drawLine(context: context, from: scaledPoints[6], to: scaledPoints[7], color: .green)
                            drawLine(context: context, from: scaledPoints[7], to: scaledPoints[4], color: .green)
                            
                            // Vertical edges connecting bottom to top
                            drawLine(context: context, from: scaledPoints[0], to: scaledPoints[4], color: .yellow)
                            drawLine(context: context, from: scaledPoints[1], to: scaledPoints[5], color: .yellow)
                            drawLine(context: context, from: scaledPoints[2], to: scaledPoints[6], color: .yellow)
                            drawLine(context: context, from: scaledPoints[3], to: scaledPoints[7], color: .yellow)
                            
                            // Draw corner points
                            for (index, point) in scaledPoints.enumerated() {
                                drawCornerPoint(context: context, at: point, index: index)
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func drawLine(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: 3)
    }
    
    private func drawCornerPoint(context: GraphicsContext, at point: CGPoint, index: Int) {
        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        let color: Color = index < 4 ? .cyan : .green
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1)
    }
    
    private func drawSegmentationMask(
        context: inout GraphicsContext,
        maskData: [UInt8],
        maskWidth: Int,
        maskHeight: Int,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) {
        // Create an image from the mask data for better performance
        guard let maskImage = createMaskImage(from: maskData, width: maskWidth, height: maskHeight) else {
            return
        }
        
        // Convert UIImage to SwiftUI Image
        let image = Image(uiImage: maskImage)
        
        // Calculate the rect for the mask with letterboxing
        let scaledRect = CGRect(
            x: offsetX,
            y: offsetY,
            width: CGFloat(maskWidth) * scale,
            height: CGFloat(maskHeight) * scale
        )
        
        // Draw the mask image with opacity
        context.draw(image, in: scaledRect, style: FillStyle())
    }
    
    private func createMaskImage(from maskData: [UInt8], width: Int, height: Int) -> UIImage? {
        // Create RGBA data with yellow color (255, 255, 0) and alpha based on mask
        var rgbaData = [UInt8](repeating: 0, count: width * height * 4)
        
        for i in 0..<maskData.count {
            let baseIdx = i * 4
            if maskData[i] == 1 {
                rgbaData[baseIdx] = 255      // R
                rgbaData[baseIdx + 1] = 255  // G
                rgbaData[baseIdx + 2] = 0    // B (yellow = R+G)
                rgbaData[baseIdx + 3] = 102  // A (40% opacity = 0.4 * 255)
            } else {
                rgbaData[baseIdx + 3] = 0    // Fully transparent
            }
        }
        
        // Create CGImage from RGBA data
        guard let dataProvider = CGDataProvider(data: Data(rgbaData) as CFData) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}