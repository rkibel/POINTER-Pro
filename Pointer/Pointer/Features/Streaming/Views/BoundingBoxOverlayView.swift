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
                           data.imageSize.count == 2 {
                            let maskHeight = data.imageSize[1]
                            let maskWidth = data.imageSize[0]
                            
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
                            
                            // Draw corner points and labels
                            for (index, point) in scaledPoints.enumerated() {
                                drawCornerPoint(context: context, at: point, index: index)
                                drawCornerLabel(context: context, at: point, index: index)
                            }
                            
                            // Draw orientation vectors
                            if let rotation = data.getRotationQuaternion() {
                                drawOrientationVectors(context: context, 
                                                     scaledPoints: scaledPoints,
                                                     rotation: rotation)
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func drawCornerLabel(context: GraphicsContext, at point: CGPoint, index: Int) {
        let text = "\(index)"
        
        // Draw label background
        let labelRect = CGRect(x: point.x + 8, y: point.y - 12, width: 20, height: 20)
        context.fill(Path(roundedRect: labelRect, cornerRadius: 4), with: .color(.black.opacity(0.7)))
        
        // Draw index number
        var textContext = context
        textContext.draw(
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white),
            at: CGPoint(x: point.x + 18, y: point.y - 2)
        )
    }
    
    private func drawOrientationVectors(context: GraphicsContext, scaledPoints: [CGPoint], 
                                       rotation: (x: Double, y: Double, z: Double, w: Double)) {
        // Calculate center of the bounding box
        let center = scaledPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let origin = CGPoint(x: center.x / CGFloat(scaledPoints.count), 
                           y: center.y / CGFloat(scaledPoints.count))
        
        // Convert quaternion to rotation matrix
        let (x, y, z, w) = rotation
        
        // Rotation matrix from quaternion
        let r00 = 1 - 2*y*y - 2*z*z
        let r01 = 2*x*y - 2*z*w
        let r02 = 2*x*z + 2*y*w
        
        let r10 = 2*x*y + 2*z*w
        let r11 = 1 - 2*x*x - 2*z*z
        let r12 = 2*y*z - 2*x*w
        
        let r20 = 2*x*z - 2*y*w
        let r21 = 2*y*z + 2*x*w
        let r22 = 1 - 2*x*x - 2*y*y
        
        // Define basis vectors in object space
        // Normal to top face (up vector in object space)
        let upVector = (x: 0.0, y: 0.0, z: 1.0)  // Positive Z is up/forward
        // Right face normal (right vector in object space)
        let rightVector = (x: 1.0, y: 0.0, z: 0.0)  // Positive X is right
        // Far face normal (forward vector in object space)
        let forwardVector = (x: 0.0, y: -1.0, z: 0.0)  // Negative Y is forward/far
        
        // Transform vectors by rotation matrix
        let upRotated = (
            x: r00 * upVector.x + r01 * upVector.y + r02 * upVector.z,
            y: r10 * upVector.x + r11 * upVector.y + r12 * upVector.z,
            z: r20 * upVector.x + r21 * upVector.y + r22 * upVector.z
        )
        
        let rightRotated = (
            x: r00 * rightVector.x + r01 * rightVector.y + r02 * rightVector.z,
            y: r10 * rightVector.x + r11 * rightVector.y + r12 * rightVector.z,
            z: r20 * rightVector.x + r21 * rightVector.y + r22 * rightVector.z
        )
        
        let forwardRotated = (
            x: r00 * forwardVector.x + r01 * forwardVector.y + r02 * forwardVector.z,
            y: r10 * forwardVector.x + r11 * forwardVector.y + r12 * forwardVector.z,
            z: r20 * forwardVector.x + r21 * forwardVector.y + r22 * forwardVector.z
        )
        
        let vectorLength: CGFloat = 100
        
        // Draw Up vector (normal to top face) - Blue (+Z)
        let upEnd = CGPoint(
            x: origin.x + CGFloat(upRotated.x) * vectorLength,
            y: origin.y + CGFloat(upRotated.y) * vectorLength
        )
        drawArrow(context: context, from: origin, to: upEnd, color: .blue)
        context.draw(
            Text("+Z")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.blue),
            at: upEnd
        )
        
        // Draw Right vector (normal to right face) - Red (+X)
        let rightEnd = CGPoint(
            x: origin.x + CGFloat(rightRotated.x) * vectorLength,
            y: origin.y + CGFloat(rightRotated.y) * vectorLength
        )
        drawArrow(context: context, from: origin, to: rightEnd, color: .red)
        context.draw(
            Text("+X")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.red),
            at: rightEnd
        )
        
        // Draw Forward vector (normal to far face) - Purple (+Y)
        let forwardEnd = CGPoint(
            x: origin.x + CGFloat(forwardRotated.x) * vectorLength,
            y: origin.y + CGFloat(forwardRotated.y) * vectorLength
        )
        drawArrow(context: context, from: origin, to: forwardEnd, color: .purple)
        context.draw(
            Text("+Y")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.purple),
            at: forwardEnd
        )
        
        // Draw origin point
        let originRect = CGRect(x: origin.x - 5, y: origin.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: originRect), with: .color(.white))
        context.stroke(Path(ellipseIn: originRect), with: .color(.black), lineWidth: 2)
        context.draw(
            Text("Origin")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white),
            at: CGPoint(x: origin.x, y: origin.y - 15)
        )
    }
    
    private func drawArrow(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        // Draw line
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: 3)
        
        // Draw arrowhead
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        let arrowLength: CGFloat = 12
        let arrowAngle: CGFloat = .pi / 6
        
        let point1 = CGPoint(
            x: to.x - arrowLength * cos(angle - arrowAngle),
            y: to.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: to.x - arrowLength * cos(angle + arrowAngle),
            y: to.y - arrowLength * sin(angle + arrowAngle)
        )
        
        var arrowPath = Path()
        arrowPath.move(to: to)
        arrowPath.addLine(to: point1)
        arrowPath.move(to: to)
        arrowPath.addLine(to: point2)
        context.stroke(arrowPath, with: .color(color), lineWidth: 3)
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