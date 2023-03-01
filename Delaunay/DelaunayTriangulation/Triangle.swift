//
//  Triangle.swift
//  DelaunayTriangulationSwift
//
//  Created by Alex Littlejohn on 2016/01/08.
//  Copyright © 2016 zero. All rights reserved.
//

/// A simple struct representing 3 points
public struct Triangle: Hashable {
    
    public init(point1: Point, point2: Point, point3: Point) {
        self.point1 = point1
        self.point2 = point2
        self.point3 = point3
    }
    
    public let point1: Point
    public let point2: Point
    public let point3: Point
}

extension Triangle: CustomStringConvertible {
    public var description: String {
        return "P1: (\(point1.x), \(point1.y)), P2: (\(point2.x), \(point2.y)), P3: (\(point3.x), \(point3.y))"
    }
}
