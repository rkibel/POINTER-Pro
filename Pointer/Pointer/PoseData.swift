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
    
    enum CodingKeys: String, CodingKey {
        case frameCount = "frame_count"
        case timestamp
        case projectedPoints2d = "projected_points_2d"
        case imageSize = "image_size"
    }
    
    /// Get all 8 corners of the bounding box as CGPoints
    func getProjectedBoundingBox() -> [CGPoint] {
        return projectedPoints2d.compactMap { point in
            guard point.count == 2 else { return nil }
            return CGPoint(x: CGFloat(point[0]), y: CGFloat(point[1]))
        }
    }
}