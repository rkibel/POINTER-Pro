//
//  PoseData.swift
//  Pointer
//
//  Created by Ron Kibel on 10/23/25.
//

import Foundation
import CoreGraphics

/// Pose estimation data received from the server
struct PoseData: Codable {
    let frameCount: Int
    let timestamp: String
    let projectedPoints2d: [[Double]]  // 8 corners × 2 coordinates (x, y)
    let imageSize: [Int]  // [width, height]
    let detectionBox: [Int]?  // [x1, y1, x2, y2] - two corner points of detection bounding box from YOLO
    let maskRle: [Int]?  // RLE-encoded segmentation mask from SAM2
    let maskShape: [Int]?  // [height, width] of the mask
    
    enum CodingKeys: String, CodingKey {
        case frameCount = "frame_count"
        case timestamp
        case projectedPoints2d = "projected_points_2d"
        case imageSize = "image_size"
        case detectionBox = "detection_box"
        case maskRle = "mask_rle"
        case maskShape = "mask_shape"
    }
    
    /// Get all 8 corners of the bounding box as CGPoints
    func getProjectedBoundingBox() -> [CGPoint] {
        return projectedPoints2d.compactMap { point in
            guard point.count == 2 else { return nil }
            return CGPoint(x: CGFloat(point[0]), y: CGFloat(point[1]))
        }
    }
    
    /// Get the detection box as a CGRect
    func getDetectionBox() -> CGRect? {
        guard let box = detectionBox, box.count == 4 else { return nil }
        // Box format is [x1, y1, x2, y2] from the detection model
        let x1 = CGFloat(box[0])
        let y1 = CGFloat(box[1])
        let x2 = CGFloat(box[2])
        let y2 = CGFloat(box[3])
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }
    
    /// Decode RLE mask to binary mask array
    func decodeMask() -> [UInt8]? {
        guard let rle = maskRle, let shape = maskShape, shape.count == 2 else {
            return nil
        }
        
        let height = shape[0]
        let width = shape[1]
        let totalPixels = height * width
        
        var mask = [UInt8](repeating: 0, count: totalPixels)
        
        // RLE format: [start1, length1, start2, length2, ...]
        // Even indices are start positions, odd indices are lengths
        // Only regions with value 1 are encoded
        for i in stride(from: 0, to: rle.count - 1, by: 2) {
            let start = rle[i]
            let length = rle[i + 1]
            
            // Fill the mask with 1s for this run
            for j in 0..<length {
                let idx = start + j
                if idx < totalPixels {
                    mask[idx] = 1
                }
            }
        }
        
        return mask
    }
}