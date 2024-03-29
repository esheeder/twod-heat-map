//
//  HeatMapGenerator.swift
//  twod-heat-map
//
//  Created by Eric on 2/6/23.
//

import Foundation
import UIKit
import CoreGraphics



public class HeatMapGenerator {
    
    // Values needed for image generation, thanks stack overflow
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    let bitsPerComponent = 8
    let bitsPerPixel = 32
    
    // Values passed in on what the mapping area is. x and y in millimeters. Can be changed at any time
    var graphMinX : Int = 0
    var graphMaxX : Int = 0
    var graphMinY : Int = 0
    var graphMaxY : Int = 0
    var zFloor: Double? = nil
    var zCeil: Double? = nil
    var dangerGap: Double
    
    var resolution : Int = 1 // pixels per millimeter, larger = higher resolution
    var interpSquareSize: Int = 20 // millimeters
    
    // Calculated values based on actual data passed in. x and y in millimeters
    public var minX : Double = Double.greatestFiniteMagnitude
    public var maxX : Double = 1.0 - Double.greatestFiniteMagnitude
    public var minY : Double = Double.greatestFiniteMagnitude
    public var maxY : Double = 1.0 - Double.greatestFiniteMagnitude
    public var minZ : Double = Double.greatestFiniteMagnitude
    public var maxZ : Double = 1.0 - Double.greatestFiniteMagnitude
    
    // Different arrays for holding data
    
    // A storage of all of the data we've seen
    var rawData: [SensorData?] = Array(repeating: nil, count: 250000)
    var pointsAdded = 0
    var lowPointsDiscarded = 0
    var highPointsDiscarded = 0
    var zCsvIndex: Int
    
    var lastXIndex: Int = 0
    var lastYIndex: Int = 0
    
    // The data points from above plotted on x, y coordinates. For any collisions, we add them to a running average at the point
    var realDataValues: [[WeightedDataPoint?]] = [[]]
    
    // Spliners in 4 directions
    var horizontalSpliners: [HeatMapSpline] = []
    var verticalSpliners: [HeatMapSpline] = []
    var upleftSpliners: [HeatMapSpline] = []
    var uprightSpliners: [HeatMapSpline] = []
    
    // Stored weighted values of the above spliners
    var splinerWeightedAvg: [[WeightedDataPoint]] = [[]]
    
    // Single arrays for live action since idk how to get parallel working with arrays in a map yet
    var theOneSquareAverageArray: [[WeightedDataPoint]] = [[]]
    var theOneBicubArray: [[WeightedDataPoint]] = [[]]
    
    var pixelsArray: [PixelData] = []
    
    var zValDict: [String: Double] = [:]
    
    
    
    
    
    
    
    // For each square size, need a square average array and bicub interp array
    var squareAverageSizes: [Int] = [3, 4]
    var squareAverageSizeToArray: [Int: [[WeightedDataPoint]]] = [:]
    var bicubInterpSizeToArray: [Int: [[WeightedDataPoint?]]] = [:]
    

    
    // Contain pre-calculated square and cubic values for numbers between 0 and 1 based on interpSquareSize.
    // Useful for the bicubic function to make it faster
    var precalcStepSquared: [Double] = []
    var precalcStepCubed: [Double] = []
    
    // IMAGE GENERATION ONLY
    var unconstrainedHorizontal: [[InterpolatedDataPoint?]] = [[]]
    var unconstrainedVertical: [[InterpolatedDataPoint?]] = [[]]
    var unconstrainedDownright: [[InterpolatedDataPoint?]] = [[]]
    var unconstrainedDownleft: [[InterpolatedDataPoint?]] = [[]]

    var constrainedHorizontal: [[InterpolatedDataPoint?]] = [[]]
    var constrainedVertical: [[InterpolatedDataPoint?]] = [[]]
    var constrainedDownright: [[InterpolatedDataPoint?]] = [[]]
    var constrainedDownleft: [[InterpolatedDataPoint?]] = [[]]

    var horizontalLinear: [[InterpolatedDataPoint?]] = [[]]
    var verticalLinear: [[InterpolatedDataPoint?]] = [[]]
    var downrightDiagonalLinear: [[InterpolatedDataPoint?]] = [[]]
    var downleftDiagonalLinear: [[InterpolatedDataPoint?]] = [[]]
    
    var firstOrderWeightedUnconstrained: [[InterpolatedDataPoint?]] = [[]]
    var secondOrderWeightedUnconstrained: [[InterpolatedDataPoint?]] = [[]]
    var thirdOrderWeightedUnconstrained: [[InterpolatedDataPoint?]] = [[]]

    var firstOrderWeightedConstrained: [[InterpolatedDataPoint?]] = [[]]
    var secondOrderWeightedConstrained: [[InterpolatedDataPoint?]] = [[]]
    var thirdOrderWeightedConstrained: [[InterpolatedDataPoint?]] = [[]]

    var firstOrderWeightedLinear: [[InterpolatedDataPoint?]] = [[]]
    var secondOrderWeightedLinear: [[InterpolatedDataPoint?]] = [[]]
    var thirdOrderWeightedLinear: [[InterpolatedDataPoint?]] = [[]]
    
    var pointsSet : Int = 0
    
    // x/y values should be in millimeters, resolution is pixels / millimeters, interpSquareSize is millimeters
    init(minX: Int, maxX: Int, minY: Int, maxY: Int, resolution : Int, interpSquareSizes: [Int], dangerGap: Double, zCsvIndex: Int, zFloor: Double?, zCeil: Double?) {
        self.graphMinX = minX
        self.graphMinY = minY
        self.graphMaxX = maxX
        self.graphMaxY = maxY
        self.resolution = resolution
        self.squareAverageSizes = interpSquareSizes
        self.interpSquareSize = interpSquareSizes[0]
        self.dangerGap = dangerGap
        self.zCsvIndex = zCsvIndex
        self.zFloor = zFloor
        self.zCeil = zCeil
        
        resetArrays()
        precalcCubicValues(step: self.interpSquareSize)
    }
    
    // Call this when an input parameter changes
    public func regeneratePlots() {
        resetArrays()

        for dataPoint in rawData {
            if dataPoint != nil {
                addDataPointToHeatMap(dataPoint: dataPoint!)
            }
        }
        
        //processData()
    }
    
 
    
    private func resetArrays(resetPlotted: Bool = true) {
        // IMPORTANT ONES
        let pixelWidth = (graphMaxX - graphMinX) * resolution
        let pixelHeight = (graphMaxY - graphMinY) * resolution
        
        if resetPlotted {
            realDataValues = [[WeightedDataPoint?]](repeating: [WeightedDataPoint?](repeating: nil, count: pixelWidth), count: pixelHeight)
            pointsSet = 0
        }

        // TODO: Add diagonals here
        if resetPlotted {
            horizontalSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelWidth), count: pixelHeight)
            for i in 0..<pixelHeight {
                horizontalSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelWidth)
            }
            verticalSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelHeight), count: pixelWidth)
            for i in 0..<pixelWidth {
                verticalSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelHeight)
            }
            /*
                Say you have a 400 wide x 200 tall array:
             
                upleftSpliners[0-399] will start bottom left, going right
                   [0]             [200]          [399]
                . . . . .       . \ . . .       . . . \ .
                . . . . .   ->  . .\. . .   ->  . . . .\.
                \ . . . .       . . \ . .       . . . . \
             
                upleftSpliners[400-599] will start from bottom right, going up
                   [400]           [500]          [598]
                 . . . \ .       . . . .\.      . . . . \
                 . . . .\.   ->  . . . . \  ->  . . . . .
                 . . . . \       . . . . .      . . . . .
             
                 uprightSpliners[0-199] will start top left, going right
                    [0]             [100]          [199]
                 / . . . .       ./. . . .       . / . . .
                 . . . . .   ->  / . . . .   ->  ./. . . .
                 . . . . .       . . . . .       / . . . .
             
                uprightSpliners[200-599] will start from bottom left, going right
                    [200]           [400]          [598]
                  . / . . .       . . . / .      . . . . .
                  ./. . . .   ->  . . ./. .  ->  . . . . .
                  / . . . .       . . / . .      . . . . /
             
                Technically there is a duplication in each direction from the corner but that's ok
                because the added work is negligible and it makes the code much easier to handle
             */
            // TODO: indexCount on these can be computed to save memory
            upleftSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight)), count: pixelWidth + pixelHeight)
            uprightSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight)), count: pixelWidth + pixelHeight)
            for i in 0..<upleftSpliners.count {
                upleftSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight))
                uprightSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight))
            }
        } else {
            // TODO: Can recreate these by looking at t indices without looping through everything to find where the data points are
            // TODO: Need to implement some sort of "updateZVals" in the HeatMapSpliner class, shouldn't be hard at all
        }
        
        splinerWeightedAvg = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: pixelWidth), count: pixelHeight)
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                splinerWeightedAvg[y][x] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
            }
        }
        
        theOneSquareAverageArray = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: (graphMaxX - graphMinX) / self.interpSquareSize), count: (graphMaxY - graphMinY) / self.interpSquareSize)
        for i in 0..<theOneSquareAverageArray.count {
            for j in 0..<theOneSquareAverageArray[0].count {
                theOneSquareAverageArray[i][j] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
            }
        }
        
        theOneBicubArray = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: pixelWidth), count: pixelHeight)
        for i in 0..<theOneBicubArray.count {
            for j in 0..<theOneBicubArray[0].count {
                theOneBicubArray[i][j] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
            }
        }
        
        // Mag factor of 2
        pixelsArray = [PixelData](repeating: PixelData(a: 255, r: 0, g: 0, b: 0), count: pixelWidth * pixelHeight * 2 * 2)
        for i in 0..<pixelsArray.count {
            pixelsArray[i] = PixelData(a: 255, r: 0, g: 0, b: 0)
        }

        for squareSize in squareAverageSizes {
            squareAverageSizeToArray[squareSize] = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: (graphMaxX - graphMinX) / squareSize), count: (graphMaxY - graphMinY) / squareSize)
            var daArray = squareAverageSizeToArray[squareSize]!
            for i in 0..<daArray.count {
                for j in 0..<daArray[0].count {
                    daArray[i][j] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
                }
            }
            bicubInterpSizeToArray[squareSize] = [[WeightedDataPoint?]](repeating: [WeightedDataPoint?](repeating: nil, count: pixelWidth), count: pixelHeight)
            var daOtherArray = bicubInterpSizeToArray[squareSize]!
            for i in 0..<daOtherArray.count {
                for j in 0..<daOtherArray[0].count {
                    daOtherArray[i][j] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
                }
            }
        }
               
        // IMAGE GENERATION ONLY
//        constrainedHorizontal = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        constrainedVertical = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        constrainedDownleft = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        constrainedDownright = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
//        horizontalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        verticalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        downrightDiagonalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        downleftDiagonalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
//        unconstrainedHorizontal = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        unconstrainedVertical = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        unconstrainedDownleft = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        unconstrainedDownright = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
//        firstOrderWeightedLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        secondOrderWeightedLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        thirdOrderWeightedLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
//        firstOrderWeightedUnconstrained = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        secondOrderWeightedUnconstrained = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
//        thirdOrderWeightedUnconstrained = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
//        thirdOrderWeightedConstrained = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
    }
    

    
    // PROCESS DATA HERE
    public func processData(doInterp: Bool = true) {
//        print("pointsAdded=", pointsAdded)
//        print("lowPointsDiscarded=", lowPointsDiscarded)
//        print("highPointsDiscarded=", highPointsDiscarded)
        if doInterp {
            
//            print("minZ=", self.minZ)
//            print("maxZ=", self.maxZ)
            let totalStart = Date()
            
            let dispatchSplineStart = Date()
            performDispatchQueueSplineInterpolation()
            let dispatchSplineEnd = Date()
            //print("dispatch queue spline:", Int(dispatchSplineEnd.timeIntervalSince(dispatchSplineStart) * 1000), "ms")
            
//            let splineStart = Date()
//            performSplineInterpolation()
//            let splineEnd = Date()
//            print("old spline:", Int(splineEnd.timeIntervalSince(splineStart) * 1000), "ms")
            
            let weightedStart = Date()
            performWeightedAverage()
            let weightedEnd = Date()
            //print("weighted:", Int(weightedEnd.timeIntervalSince(weightedStart) * 1000), "ms")
            
            
            let avgStart = Date()
            createSquareAverages(squareSize: self.interpSquareSize)
            let avgEnd = Date()
            //print("square average:", Int(avgEnd.timeIntervalSince(avgStart) * 1000), "ms")
            
            let bicubStart = Date()
            performBicubicInterpolation(squareSizeInMm: self.interpSquareSize)
            let bicubEnd = Date()
            //print("bicubic:", Int(bicubEnd.timeIntervalSince(bicubStart) * 1000), "ms")
            
//            let oldImageStart = Date()
//            createHeatMapImageFromDataArray(dataArray: theOneBicubArray)
//            let oldImageEnd = Date()
//            print("old image creation time:", Int(oldImageEnd.timeIntervalSince(oldImageStart) * 1000), "ms")
            
//            let imageStart = Date()
//            createLiveImage()
//            let imageEnd = Date()
//            print("image creation time:", Int(imageEnd.timeIntervalSince(imageStart) * 1000), "ms")
            
//            for size in squareAverageSizes {
//                self.interpSquareSize = size
//            }
            let totalEnd = Date()
            //print("TOTAL TIME:", Int(totalEnd.timeIntervalSince(totalStart) * 1000), "ms")
            
        } else {
            print("no interp performed")
            print("minX=", self.minX)
            print("maxX=", self.maxX)
            print("minY=", self.minY)
            print("maxY=", self.maxY)
        }
    }
    
    public func performDispatchQueueSplineInterpolation() {
        let pixelWidth = self.realDataValues[0].count
        let pixelHeight = self.realDataValues.count
        DispatchQueue.concurrentPerform(iterations: pixelHeight) {y in
            // Horizontal
            self.cubicSplineInterpolateLine(startX: 0, startY: y, xDir: 1, yDir: 0, spliner: self.horizontalSpliners[y])
            // Up left
            self.cubicSplineInterpolateLine(startX: pixelWidth - 1, startY: y, xDir: -1, yDir: 1, spliner: self.upleftSpliners[pixelWidth + y])
            // Up right
            self.cubicSplineInterpolateLine(startX: 0, startY: (pixelHeight - 1 - y), xDir: 1, yDir: 1, spliner: self.uprightSpliners[y])
        }
        DispatchQueue.concurrentPerform(iterations: pixelWidth) {x in
            // Vertical
            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 0, yDir: 1, spliner: self.verticalSpliners[x])
            // Up left
            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: -1, yDir: 1, spliner: self.upleftSpliners[x])
            // Up right
            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 1, yDir: 1, spliner: self.uprightSpliners[pixelHeight + x])
        }
    }
    
    // startX and startY should be index values
    public func cubicSplineInterpolateLine(startX: Int, startY: Int, xDir: Int, yDir: Int, spliner: HeatMapSpline) {
        //print("START x: \(startX), y: \(startY), xDir: \(xDir), yDir: \(yDir)")
        if !spliner.shouldUpdate {
            return
        }
        var tPoints : [Double] = []
        var zValues : [Double] = []
//        var minT = 10000000
//        var maxT = 0
        var lastT = -10
        // TODO: Clean this up, can do something like spliner.maxIndex once those are computed
        for t in 0..<100000 {
            let xCoord = startX + t * xDir
            let yCoord = startY + t * yDir
            if xCoord >= self.realDataValues[0].count || yCoord >= self.realDataValues.count || xCoord < 0 || yCoord < 0 {
                break
            }
            let val = self.realDataValues[yCoord][xCoord]?.value
            // Only add values that are more than 2mm away from the previous one
            if val != nil && (t - lastT) > 2 * self.resolution {
                tPoints.append(Double(t))
                zValues.append(val!)
                lastT = t
                //maxT = t
//                if minT == 10000000 {squareAverageSizeToArray
//                    minT = t
//                }
            }
        }
        
        spliner.setPoints(newTs: tPoints, newZs: zValues)
        spliner.shouldUpdate = false
        
        //print("END x: \(startX), y: \(startY), xDir: \(xDir), yDir: \(yDir)")
    }
    
    public func performWeightedAverage() {
        let imageWidth = realDataValues[0].count
        let imageHeight = realDataValues.count
        
        DispatchQueue.concurrentPerform(iterations: imageWidth * imageHeight) {i in
            weightPixel(x: i % imageWidth, y: i / imageWidth, imageHeight: imageHeight, imageWidth: imageWidth)
        }
    }
    
    public func weightPixel(x: Int, y: Int, imageHeight: Int, imageWidth: Int) {
        var numerator = 0.0
        var denominator = 0.0
        var valuesUsed = 0

        if let verticalInfo = verticalSpliners[x].zCalcs[y] {
            valuesUsed += 1
            let cubed = pow(verticalInfo.distance, 3)
            numerator += verticalInfo.value / cubed
            denominator += 1.0 / cubed
        }
        if let horizontalInfo = horizontalSpliners[y].zCalcs[x] {
            valuesUsed += 1
            let cubed = pow(horizontalInfo.distance, 3)
            numerator += horizontalInfo.value / cubed
            denominator += 1.0 / cubed
        }
        // Upleft spliners that start at bottom
        if x + y <= imageWidth {
            if let diag1Val = upleftSpliners[x + y].zCalcs[y] {
                valuesUsed += 1
                let cubed = pow(diag1Val.distance * 1.41, 3) // 1.41 = sqrt(2) approx
                numerator += diag1Val.value / cubed
                denominator += 1.0 / cubed
            }
        } else {
            // Upleft spliners that start on the right
            if let diag1Val = upleftSpliners[x + y + 1].zCalcs[imageWidth - x - 1] {
                valuesUsed += 1
                let cubed = pow(diag1Val.distance * 1.41, 3) // 1.41 = sqrt(2) approx
                numerator += diag1Val.value / cubed
                denominator += 1.0 / cubed
            }
        }
        
        // Upright spliners that start at left
        if y >= x {
            if let diag2Val = uprightSpliners[Int(imageHeight - 1 + x - y)].zCalcs[x] {
                valuesUsed += 1
                let cubed = pow(diag2Val.distance * 1.41, 3)
                numerator += diag2Val.value / cubed
                denominator += 1.0 / cubed
            }
        } else {
            // Upright spliners that start on the bottom
            if let diag2Val = uprightSpliners[Int(imageHeight + x - y)].zCalcs[y] {
                valuesUsed += 1
                let cubed = pow(diag2Val.distance * 1.41, 3)
                numerator += diag2Val.value / cubed
                denominator += 1.0 / cubed
            }
        }
        if valuesUsed > 0 {
            splinerWeightedAvg[y][x] = WeightedDataPoint(value: numerator / denominator, samplesTaken: valuesUsed)
        }
    }
    
    
    public func createSquareAverages(squareSize: Int) {
        let horizontalIterations = (graphMaxX - graphMinX) / squareSize
        let verticalIterations = (graphMaxY - graphMinY) / squareSize
        
        DispatchQueue.concurrentPerform(iterations: horizontalIterations * verticalIterations) {i in
            averageSquare(x: i % horizontalIterations, y: i / horizontalIterations, squareSize: squareSize)
        }
        
//        for x in 0..<horizontalIterations {
//            for y in 0..<verticalIterations {
//                averageSquare(x: x, y: y, squareSize: squareSize)
//            }
//        }
    }
    
    // Loop through data in chunks of size x size and set the corresponding pixel in the squareAverageArray
    private func averageSquare(x: Int, y: Int, squareSize: Int) {
        var localSum : Double = 0.0
        var pointsTallied = 0
        // Loop over square to sum values
        for i in 0..<squareSize * resolution {
            for j in 0..<squareSize * resolution {
                let z = splinerWeightedAvg[y * squareSize * resolution + j][x * squareSize * resolution + i]
                if z.samplesTaken > 0 {
                    localSum += z.value
                    pointsTallied += 1
                }
            }
        }
        //print("pointsTallied=", pointsTallied)
        if pointsTallied > 0 {
            let average = localSum / Double(pointsTallied)
            theOneSquareAverageArray[y][x] = WeightedDataPoint(value: average, samplesTaken: pointsTallied)
        } else {
            theOneSquareAverageArray[y][x] = WeightedDataPoint(value: self.minZ, samplesTaken: 0)
        }
    }
    
    // TODO: Some sort of recursive function that fills in empty squares based on neighbor values
    private func fillInSquareAverages(squareSize: Int) {
        var daArray = theOneSquareAverageArray
        for x in 0..<daArray[0].count {
            for y in 0..<daArray.count {
                if daArray[y][x].samplesTaken == 0 {
                    let newPoint = WeightedDataPoint(value: self.minZ, samplesTaken: 0)
                    daArray[y][x] = newPoint
                }
            }
        }
    }
    
//    public func performBlahblah() {
//        for i in 0..<horizontalSpliners.count {
//            let daSpliner = horizontalSpliners[i]
//            if daSpliner.t.count > 3 {
//                for j in Int(daSpliner.t.first!)..<Int(daSpliner.t.last!) {
//                    print daSpliner.zCalcs[j]
//                }
//            }
//
//        }
//    }
    
    public func getSplinerForPixel(xIndex: Int, yIndex: Int, direction: String) -> HeatMapSpline {
        if direction == "horizontal" {
            return horizontalSpliners[yIndex]
        } else if direction == "vertical" {
            return verticalSpliners[xIndex]
        } else if direction == "upleft" {
            if xIndex + yIndex < realDataValues[0].count {
                return upleftSpliners[xIndex + yIndex]
            }
            return upleftSpliners[xIndex + yIndex + 1]
        } else if direction == "upright" {
            if yIndex >= xIndex {
                return uprightSpliners[realDataValues.count - 1 + xIndex - yIndex]
            }
            return uprightSpliners[realDataValues.count + xIndex - yIndex]
        }
        print("hmmm, probably shouldn't be here")
        return horizontalSpliners[0]
    }
    

    
    // Print out raw x, y, z coordinates for CSV
    public func printRawData() {
        print("")
        for i in 0..<realDataValues[0].count {
            for j in 0..<realDataValues.count {
                let value = realDataValues[j][i]?.value
                if value != nil {
                    print(getAbsoluteXCoordInMmFromI(i), ",", getAbsoluteYCoordInMmFromJ(j) , ",", abs(Float(value!)), separator: "")
                }
            }
        }
    }
    
    public func processNewDataPoint(dataPoint: SensorData) {
        //rawData[pointsAdded] = dataPoint
        pointsAdded += 1
        addDataPointToHeatMap(dataPoint: dataPoint)
    }
    
    private func addDataPointToHeatMap(dataPoint: SensorData) -> Void {
        let xIndex = getXIndexFromXCoord(dataPoint.x)
        let yIndex = getYIndexFromYCoord(dataPoint.y)
        
        self.minX = Double.minimum(self.minX, dataPoint.x)
        self.maxX = Double.maximum(self.maxX, dataPoint.x)
        
        self.minY = Double.minimum(self.minY, dataPoint.y)
        self.maxY = Double.maximum(self.maxY, dataPoint.y)
        
        if xIndex < 0 || xIndex >= realDataValues[0].count || yIndex < 0 || yIndex >= realDataValues.count {
//            print("trying to plot point outside chart range at x=", dataPoint.x, "y=", dataPoint.y)
//            print("xIndex=", xIndex, "yIndex=", yIndex)
//            print("realDataValues[0].count=", realDataValues[0].count)
//            print("realDataValues.count=", realDataValues.count)
            return
        }
        
        self.lastXIndex = xIndex
        self.lastYIndex = yIndex
        
        
        //print(dataPoint.z)
        
        if self.zFloor != nil && dataPoint.z < self.zFloor! {
            lowPointsDiscarded += 1
            return
        } else if self.zCeil != nil && dataPoint.z > self.zCeil! {
            highPointsDiscarded += 1
            return
        }

        
        //print("xPos is", xPos, "yPos is", yPos)
        let weightedPoint = realDataValues[yIndex][xIndex]
        if weightedPoint == nil {
            realDataValues[yIndex][xIndex] = WeightedDataPoint(value: dataPoint.z, samplesTaken: 1)
            pointsSet += 1
        } else {
            let newVal = (weightedPoint!.value * Double(weightedPoint!.samplesTaken) + dataPoint.z) / Double(weightedPoint!.samplesTaken + 1)
            realDataValues[yIndex][xIndex] = WeightedDataPoint(value: newVal, samplesTaken: weightedPoint!.samplesTaken + 1)
        }
        

        verticalSpliners[xIndex].shouldUpdate = true
        horizontalSpliners[yIndex].shouldUpdate = true
        getSplinerForPixel(xIndex: xIndex, yIndex: yIndex, direction: "upleft").shouldUpdate = true
        getSplinerForPixel(xIndex: xIndex, yIndex: yIndex, direction: "upright").shouldUpdate = true
        self.minZ = Double.minimum(self.minZ, dataPoint.z)
        self.maxZ = Double.maximum(self.maxZ, dataPoint.z)
    }
    
    
    public func performOperationSplineInterpolation() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8  // a max of 4 tasks at a time

//        let completion = BlockOperation {
//            print("operations all done")
//        }
        let pixelWidth = self.realDataValues[0].count
        for y in 0..<realDataValues.count{
            let operation = BlockOperation {
                // Horizontal
                self.cubicSplineInterpolateLine(startX: 0, startY: y, xDir: 1, yDir: 0, spliner: self.horizontalSpliners[y])
                // Down right
                self.cubicSplineInterpolateLine(startX: 0, startY: y, xDir: 1, yDir: 1, spliner: self.upleftSpliners[pixelWidth + y])
                // Down left
                self.cubicSplineInterpolateLine(startX: pixelWidth - 1, startY: y, xDir: -1, yDir: 1, spliner: self.uprightSpliners[pixelWidth + y])
            }
//            }
            
            queue.addOperation(operation)
        }
        
//        queue.addBarrierBlock {
//            DispatchQueue.main.async {
//                print("y all done")
//            }
//        }
        
        for x in 0..<realDataValues[0].count {
            let operation = BlockOperation {
                // Vertical
                self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 0, yDir: 1, spliner: self.verticalSpliners[x])
                // Down right
                self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 1, yDir: 1, spliner: self.upleftSpliners[x])
                // Down left
                self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: -1, yDir: 1, spliner: self.uprightSpliners[x])
            }
            queue.addOperation(operation)

        }

        queue.addBarrierBlock {
            print("operationQueue all done")
        }
        queue.waitUntilAllOperationsAreFinished()
    }
    
    // THESE SPLINER INDICES ARE OLD/WRONG
//    public func performSplineInterpolation() {
//        let pixelWidth = self.realDataValues[0].count
//        for y in 0..<realDataValues.count {
//            // Horizontal
//            self.cubicSplineInterpolateLine(startX: 0, startY: y, xDir: 1, yDir: 0, spliner: self.horizontalSpliners[y])
//            // Down right
//            self.cubicSplineInterpolateLine(startX: 0, startY: y, xDir: 1, yDir: 1, spliner: self.upleftSpliners[pixelWidth + y])
//            // Down left
//            self.cubicSplineInterpolateLine(startX: pixelWidth - 1, startY: y, xDir: -1, yDir: 1, spliner: self.downleftSpliners[pixelWidth + y])
//        }
//        for x in 0..<realDataValues[0].count {
//            // Vertical
//            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 0, yDir: 1, spliner: self.verticalSpliners[x])
//            // Down right
//            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 1, yDir: 1, spliner: self.upleftSpliners[x])
//            // Down left
//            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: -1, yDir: 1, spliner: self.downleftSpliners[x])
//        }
//
//    }


    
    private func precalcCubicValues(step: Int) {
        precalcStepSquared = Array(repeating: 0.0, count: step * resolution)
        precalcStepCubed = Array(repeating: 0.0, count: step * resolution)
        for i in 0..<step * resolution {
            let doubleStep = Double(i) / Double(step * resolution)
            precalcStepSquared[i] = doubleStep * doubleStep
            precalcStepCubed[i] = doubleStep * doubleStep * doubleStep
        }
    }
    
    private func performBicubicInterpolation(squareSizeInMm: Int) {
        let xCount = theOneSquareAverageArray[0].count
        let yCount = theOneSquareAverageArray.count

        DispatchQueue.concurrentPerform(iterations: xCount * yCount) {i in
            bicubInterpSquare(xStartIndex: i % xCount, yStartIndex: i / xCount, squareSizeMm: squareSizeInMm)
        }
    }
    
    // startX and startY are locations in pixels
    // Dots are CENTER points of square averages, 0 is our origin, 1 is where we interp to
    // This function only works right if you pass in xStartIndex and yStartIndex as the center point, otherwise
    // you get shifting in the output image
    /*
     [. . . .
      . 0 . .
      . . 1 .
      . . . .]
     */
    // Square size in pixels
    private func bicubInterpSquare(xStartIndex: Int, yStartIndex: Int, squareSizeMm: Int) {
//        if xStartIndex > realDataValues[0].count || yStartIndex > realDataValues.count {
//            return
//        }
        
        let squareSizePx = squareSizeMm * self.resolution
        let mapValues = theOneSquareAverageArray
        
        if mapValues[yStartIndex][xStartIndex].samplesTaken <= 0 {
            // TODO: Fill in this square with just the raw color?
            return
        }
        
        let xMaxIndex = mapValues[0].count - 1
        let yMaxIndex = mapValues.count - 1
        
        
        var x1Index = xStartIndex - 1
        let x2Index = xStartIndex
        var x3Index = xStartIndex + 1
        var x4Index = xStartIndex + 2
        
        if x1Index < 0 {
            x1Index = x2Index
        }
        if x3Index > xMaxIndex {
            x3Index = x2Index
        }
        if x4Index > xMaxIndex {
            x4Index = x3Index
        }
        
        var y1Index = yStartIndex - 1
        let y2Index = yStartIndex
        var y3Index = yStartIndex + 1
        var y4Index = yStartIndex + 2
        
        if y3Index > yMaxIndex {
            y3Index = y2Index
        }
        if y4Index > yMaxIndex {
            y4Index = y3Index
        }

        if y1Index < 0 {
            y1Index = y2Index
        }
        
        let p : [[Double]] = [
            [mapValues[y1Index][x1Index].value, mapValues[y2Index][x1Index].value, mapValues[y3Index][x1Index].value, mapValues[y4Index][x1Index].value],
            [mapValues[y1Index][x2Index].value, mapValues[y2Index][x2Index].value, mapValues[y3Index][x2Index].value, mapValues[y4Index][x2Index].value],
            [mapValues[y1Index][x3Index].value, mapValues[y2Index][x3Index].value, mapValues[y3Index][x3Index].value, mapValues[y4Index][x3Index].value],
            [mapValues[y1Index][x4Index].value, mapValues[y2Index][x4Index].value, mapValues[y3Index][x4Index].value, mapValues[y4Index][x4Index].value]
        ]
        
        var a : [[Double]] = [
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0]
        ]
        
        // https://www.paulinternet.nl/?page=bicubic
        a[0][0] = p[1][1];
        a[0][1] = -0.5*p[1][0] + 0.5*p[1][2];
        a[0][2] = p[1][0] - 2.5*p[1][1] + 2*p[1][2] - 0.5*p[1][3];
        a[0][3] = -0.5*p[1][0] + 1.5*p[1][1] - 1.5*p[1][2] + 0.5*p[1][3];
        a[1][0] = -0.5*p[0][1] + 0.5*p[2][1];
        a[1][1] = 0.25*p[0][0] - 0.25*p[0][2] - 0.25*p[2][0] + 0.25*p[2][2];
        a[1][2] = -0.5*p[0][0] + 1.25*p[0][1] - p[0][2] + 0.25*p[0][3] + 0.5*p[2][0] - 1.25*p[2][1] + p[2][2] - 0.25*p[2][3];
        a[1][3] = 0.25*p[0][0] - 0.75*p[0][1] + 0.75*p[0][2] - 0.25*p[0][3] - 0.25*p[2][0] + 0.75*p[2][1] - 0.75*p[2][2] + 0.25*p[2][3];
        a[2][0] = p[0][1] - 2.5*p[1][1] + 2*p[2][1] - 0.5*p[3][1];
        a[2][1] = -0.5*p[0][0] + 0.5*p[0][2] + 1.25*p[1][0] - 1.25*p[1][2] - p[2][0] + p[2][2] + 0.25*p[3][0] - 0.25*p[3][2];
        a[2][2] = p[0][0] - 2.5*p[0][1] + 2*p[0][2] - 0.5*p[0][3] - 2.5*p[1][0] + 6.25*p[1][1] - 5*p[1][2] + 1.25*p[1][3] + 2*p[2][0] - 5*p[2][1] + 4*p[2][2] - p[2][3] - 0.5*p[3][0] + 1.25*p[3][1] - p[3][2] + 0.25*p[3][3];
        a[2][3] = -0.5*p[0][0] + 1.5*p[0][1] - 1.5*p[0][2] + 0.5*p[0][3] + 1.25*p[1][0] - 3.75*p[1][1] + 3.75*p[1][2] - 1.25*p[1][3] - p[2][0] + 3*p[2][1] - 3*p[2][2] + p[2][3] + 0.25*p[3][0] - 0.75*p[3][1] + 0.75*p[3][2] - 0.25*p[3][3];
        a[3][0] = -0.5*p[0][1] + 1.5*p[1][1] - 1.5*p[2][1] + 0.5*p[3][1];
        a[3][1] = 0.25*p[0][0] - 0.25*p[0][2] - 0.75*p[1][0] + 0.75*p[1][2] + 0.75*p[2][0] - 0.75*p[2][2] - 0.25*p[3][0] + 0.25*p[3][2];
        a[3][2] = -0.5*p[0][0] + 1.25*p[0][1] - p[0][2] + 0.25*p[0][3] + 1.5*p[1][0] - 3.75*p[1][1] + 3*p[1][2] - 0.75*p[1][3] - 1.5*p[2][0] + 3.75*p[2][1] - 3*p[2][2] + 0.75*p[2][3] + 0.5*p[3][0] - 1.25*p[3][1] + p[3][2] - 0.25*p[3][3];
        a[3][3] = 0.25*p[0][0] - 0.75*p[0][1] + 0.75*p[0][2] - 0.25*p[0][3] - 0.75*p[1][0] + 2.25*p[1][1] - 2.25*p[1][2] + 0.75*p[1][3] + 0.75*p[2][0] - 2.25*p[2][1] + 2.25*p[2][2] - 0.75*p[2][3] - 0.25*p[3][0] + 0.75*p[3][1] - 0.75*p[3][2] + 0.25*p[3][3];
        

//        print("p=", p)
//        print("a=", a)
        
        // Loop x and y from "0 to 1" by steps based on square size
        for i in 0..<squareSizePx {
            let xIndex = xStartIndex * squareSizePx + squareSizePx / 2 + i
            if xIndex >= realDataValues[0].count {
                break
            }
            
            let x1: Double = Double(i) / Double(interpSquareSize * resolution)
            let x2 = precalcStepSquared[i]
            let x3 = precalcStepCubed[i]

            
            for j in 0..<squareSizePx {
                let yIndex = yStartIndex * squareSizePx + squareSizePx / 2 + j
                if yIndex >= realDataValues.count {
                    break
                }
                
                let y1 = Double(j) / Double(interpSquareSize * resolution)
                let y2 = precalcStepSquared[j]
                let y3 = precalcStepCubed[j]

                
                var interpValue = a[0][0] + a[0][1] * y1 + a[0][2] * y2 + a[0][3] * y3
                interpValue += (a[1][0] + a[1][1] * y1 + a[1][2] * y2 + a[1][3] * y3) * x1
                interpValue += (a[2][0] + a[2][1] * y1 + a[2][2] * y2 + a[2][3] * y3) * x2
                interpValue += (a[3][0] + a[3][1] * y1 + a[3][2] * y2 + a[3][3] * y3) * x3
                //print("interpValue=", interpValue)
//                minZ = Float.minimum(minZ, interpValue)
//                maxZ = Float.maximum(maxZ, interpValue)
                
                // When storing, need to inverse the y values
                // When y=0, mathmatically that is the bottom of our square
                //print(xIndex, yIndex)
                theOneBicubArray[yIndex][xIndex] = WeightedDataPoint(value: interpValue, samplesTaken: 1)
                
            }
        }
//        
//        
    }
    
    public func getAbsoluteXCoordInMmFromI(_ i: Int) -> Double {
        return Double(graphMinX) + (Double(i) / Double(resolution))
    }
    
    public func getAbsoluteYCoordInMmFromJ(_ j: Int) -> Double {
        return Double(graphMinY) + (Double(j) / Double(resolution))
    }
    
    public func getXIndexFromXCoord(_ x: Double) -> Int {
        return Int(round((x - Double(graphMinX)) * Double(resolution)))
    }
    
    public func getYIndexFromYCoord(_ y: Double) -> Int {
        return Int(round((y - Double(graphMinY)) * Double(resolution)))
    }
    
    
    func calculateError(interpArray: [[DataPoint?]], gaussians: [Gaussian], xMin: Int, xMax: Int, yMin: Int, yMax: Int) {
        var totalError: Double = 0.0
        var totalAbsError: Double = 0.0
        var totalErrorSquared: Double = 0.0
        var totalErrorPercent: Double = 0.0
        var pointsComputed: Int = 0
        
        let xMinIndex = getXIndexFromXCoord(Double(xMin))
        let xMaxIndex = getXIndexFromXCoord(Double(xMax))
        let yMinIndex = getYIndexFromYCoord(Double(yMax))
        let yMaxIndex = getYIndexFromYCoord(Double(yMin))
        
//        print("xMin=", xMin, "xMinIndex=", xMinIndex)
//        print("xMin=", xMax, "xMinIndex=", xMaxIndex)
//        print("yMin=", yMin, "xMinIndex=", yMinIndex)
//        print("yMax=", yMax, "xMinIndex=", yMaxIndex)
        
        for i in xMinIndex..<xMaxIndex {
            for j in yMinIndex..<yMaxIndex {
                let interpVal = interpArray[j][i]?.value
                if interpVal != nil {
                    var realVal: Double = 0.0
                    for gaussian in gaussians {
                        realVal -= gaussian.getVal(getAbsoluteXCoordInMmFromI(i), getAbsoluteYCoordInMmFromJ(j))
                    }
                    let error =  realVal - interpVal!
                    totalError += error
                    totalAbsError += abs(error)
                    totalErrorPercent += 100.0 * abs(error) / abs(realVal)
                    totalErrorSquared += error * error
                    pointsComputed += 1
                }
            }
        }
        //let avgError = totalError / Double(pointsComputed)
        let avgErrorPercent = totalErrorPercent / Double(pointsComputed)
        let avgAbsError = totalAbsError / Double(pointsComputed)
        let standardDeviation = sqrt(totalErrorSquared / Double(pointsComputed))
        //print("pointsComputed is", pointsComputed)
        //print("average error =", avgError)
        print("average error percent=", avgErrorPercent)
        print("average absolute error =", avgAbsError)
        print("standard deviation = ", standardDeviation)
    }
    
    // IMAGE GENERATION ONLY
//    public func performUnconstrainedSplineWeightedAverage() {
//        for x in 0..<realDataValues[0].count {
//            for y in 0..<realDataValues.count {
//                let verticalVal = unconstrainedVertical[y][x]
//                let horizontalVal = unconstrainedHorizontal[y][x]
//                let diag1Val = unconstrainedDownright[y][x]
//                let diag2Val = unconstrainedDownleft[y][x]
//
//                // Linear, Square, Cubic
//                var numerators: [Double] = [0.0, 0.0, 0.0]
//                var denominators: [Double] = [0.0, 0.0, 0.0]
//                var haveAVal = false
//
//                if verticalVal != nil {
//                    haveAVal = true
//                    let myVal = verticalVal!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//                if horizontalVal != nil {
//                    haveAVal = true
//                    let myVal = horizontalVal!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//                if diag1Val != nil {
//                    haveAVal = true
//                    let myVal = diag1Val!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//                if diag2Val != nil {
//                    haveAVal = true
//                    let myVal = diag2Val!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//
//                if haveAVal {
//                    let linWeightedVal = numerators[0] / denominators[0]
//                    let squareWeightedVal = numerators[1] / denominators[1]
//                    let cubeWeightedVal = numerators[2] / denominators[2]
//
//                    firstOrderWeightedUnconstrained[y][x] = InterpolatedDataPoint(value: linWeightedVal, distance: 0.0)
//                    secondOrderWeightedUnconstrained[y][x] = InterpolatedDataPoint(value: squareWeightedVal, distance: 0.0)
//                    thirdOrderWeightedUnconstrained[y][x] = InterpolatedDataPoint(value: cubeWeightedVal, distance: 0.0)
//                }
//            }
//        }
//    }
    
    // Print (x, z) values for a row of data
    public func printRowData(dataArray: [[DataPoint?]], yInMm: Double) {
        let yIndex = getYIndexFromYCoord(yInMm)
        for x in 0..<dataArray[0].count {
            let val = dataArray[yIndex][x]?.value
            if val != nil {
                print(getAbsoluteXCoordInMmFromI(x), ",", val!, ",", separator: "")
            }
            
        }
    }
    
    // Print (y, z) values for a column of data
    public func printColumnData(dataArray: [[DataPoint?]], xInMm: Double) {
        let xIndex = getXIndexFromXCoord(xInMm)
        for y in 0..<dataArray.count {
            let val = dataArray[y][xIndex]?.value
            if val != nil {
                print(getAbsoluteYCoordInMmFromJ(y), ",", val!, ",", separator: "")
            }
            
        }
    }
    
    // Faster function that is more restrained
    public func createLiveImage(magFactor: Int = 2) -> UIImage {
        let start = Date()
        let xCount = theOneBicubArray[0].count
        let yCount = theOneBicubArray.count
        let zDiff = abs(abs(self.maxZ) - abs(self.minZ))
        
        //print(zDiff)
        DispatchQueue.concurrentPerform(iterations: xCount * yCount) {i in
            fillInPixels(smallX: i % xCount, smallY: i / xCount, zDiff: zDiff, magFactor: magFactor)
        }
        
        fillInPointerPixels(magFactor: magFactor)
        
//        for y in stride(from: 0, to: yCount * magFactor, by: magFactor) {
//            //fillInPixelRow(y: y, zDiff: zDiff, magFactor: magFactor)
//            for x in stride(from: 0, to: xCount * magFactor, by: magFactor) {
//                fillInPixels(x: x, y: y, zDiff: zDiff, magFactor: magFactor)
//            }
//        }
        let end = Date()
        //print("live image array time:", Int(end.timeIntervalSince(start) * 1000), "ms")
        return generateImageFromPixels(pixelData: pixelsArray, width: xCount * magFactor, height: yCount * magFactor)
    }
    
    // Directly write values to pixelsArray in a small chunk
    private func fillInPixels(smallX: Int, smallY: Int, zDiff: Double, magFactor: Int) {
        var pixel: PixelData? = nil
        let x = smallX * magFactor
        let y = smallY * magFactor
        
        // White/Green pixels centimeter locations
        if ((x % (10 * self.resolution * magFactor) == 0 && y % (10 * self.resolution * magFactor) == 0)) {
            pixel = PixelData(a: 255, r: 255, g: 255, b: 255)
        } else {
            let mahPoint = self.theOneBicubArray[y / magFactor][x / magFactor]
            if mahPoint.samplesTaken > 0 {
                let z = mahPoint.value
                var ratio = Int(round(255 * (abs(abs(z) - abs(minZ))) / zDiff))
                if ratio < 0 {
                    ratio = 0
                }
                if ratio > 255 {
                    ratio = 255
                }
                //print("ratio=", ratio)
                let daColor = mPlasmaColormap[ratio]
                   pixel = PixelData(a: 255, r: daColor.r, g: daColor.g, b: daColor.b)
            }
        }
        if pixel != nil {
            for j in 0..<magFactor {
                for i in 0..<magFactor {
                    let oneDIndex = (x+i) + ((j + (self.theOneBicubArray.count-1) * magFactor)-y) * self.theOneBicubArray[0].count * magFactor
                    self.pixelsArray[oneDIndex] = pixel!
                }
            }
        }
    }
    
    private func fillInPointerPixels(magFactor: Int) {
        
        var pixel = PixelData(a: 255, r: 0, g: 0, b: 0)
        let x = lastXIndex * magFactor
        let y = lastYIndex * magFactor
        
        for j in 0..<magFactor {
            for i in 0..<magFactor {
                let oneDIndex = (x+i) + ((j + (self.theOneBicubArray.count-1) * magFactor)-y) * self.theOneBicubArray[0].count * magFactor
                self.pixelsArray[oneDIndex] = pixel
            }
        }
    }
    
    public func createLinearArrays() {
        unconstrainedHorizontal = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        unconstrainedVertical = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        unconstrainedDownleft = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        unconstrainedDownright = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        
        let imageWidth = realDataValues[0].count
        let imageHeight = realDataValues.count
        
        for x in 0..<imageWidth {
            for y in 0..<imageHeight {
                
                // Vertical spliners
                if let verticalInfo = verticalSpliners[x].zCalcs[y] {
                    unconstrainedVertical[y][x] = verticalInfo
                }
                
                // Horizontal spliners
                if let horizontalInfo = horizontalSpliners[y].zCalcs[x] {
                    unconstrainedHorizontal[y][x] = horizontalInfo
                }
                
                // Upleft spliners
                if x + y <= imageWidth {
                    if let diag1Val = upleftSpliners[x + y].zCalcs[y] {
                        unconstrainedDownright[y][x] = diag1Val
                    }
                } else {
                    // Upleft spliners that start on the right
                    if let diag1Val = upleftSpliners[x + y + 1].zCalcs[imageWidth - x - 1] {
                        unconstrainedDownright[y][x] = diag1Val
                    }
                }
                
                // Upright spliners
                if y >= x {
                    if let diag2Val = uprightSpliners[Int(imageHeight - 1 + x - y)].zCalcs[x] {
                        unconstrainedDownleft[y][x] = diag2Val
                    }
                } else {
                    // Upright spliners that start on the bottom
                    if let diag2Val = uprightSpliners[Int(imageHeight + x - y)].zCalcs[y] {
                        unconstrainedDownleft[y][x] = diag2Val
                    }
                }
            }
        }
    }
    
    // Directly write values to pixelsArray in a small chunk
//    private func fillInPixelRow(y: Int, zDiff: Double, magFactor: Int) {
//        var pixel: PixelData? = nil
//        for x in stride(from: 0, to: theOneBicubArray[0].count * magFactor, by: magFactor) {
//            // White/Green pixels centimeter locations
//            if ((x % (10 * resolution * magFactor) == 0 && y % (10 * resolution * magFactor) == 0)) {
//                pixel = PixelData(a: 255, r: 255, g: 255, b: 255)
//            } else if let weightedPoint = theOneBicubArray[y / magFactor][x / magFactor] {
//                let z = weightedPoint.value
//                var ratio = Int(round(255 * (abs(abs(z) - abs(minZ))) / zDiff))
//                if ratio < 0 {
//                    ratio = 0
//                }
//                if ratio > 255 {
//                    ratio = 255
//                }
//                //print("ratio=", ratio)
//                let daColor = mPlasmaColormap[ratio]
//                   pixel = PixelData(a: 255, r: daColor.r, g: daColor.g, b: daColor.b)
//            }
//            if pixel != nil {
//                for j in 0..<magFactor {
//                    for i in 0..<magFactor {
//                        let oneDIndex = (x+i) + ((j + (theOneBicubArray.count-1) * magFactor)-y) * theOneBicubArray[0].count * magFactor
//                        pixelsArray[oneDIndex] = pixel!
//                    }
//                }
//            }
//        }
//    }
    


    // Run through the data and set color values based on the z value of each square compared to the min/max
    // Note: Converts data array to 1D for the sake of creating the image
    public func createHeatMapImageFromDataArray(dataArray : [[DataPoint?]], showSquares: Bool = true, magFactor: Int = 1, alphaFactor: UInt8 = 255) -> UIImage {
        let xCount = dataArray[0].count
        let yCount = dataArray.count
        //print("xCount=", xCount, "yCount=", yCount)
        
        var pixels: [PixelData] = Array(repeating: PixelData(a: alphaFactor, r: 0, g: 0, b: 0), count: xCount * yCount * magFactor * magFactor)
        
        let zDiff = abs(abs(self.maxZ) - abs(self.minZ))
        
        //print(zDiff)
        let start = Date()
        
        for y in stride(from: 0, to: yCount * magFactor, by: magFactor) {
                for x in stride(from: 0, to: xCount * magFactor, by: magFactor) {
                    
                    var pixel: PixelData? = nil
                    
                    // White/Green pixels centimeter locations
                    if showSquares && ((x % (10 * resolution * magFactor) == 0 && y % (10 * resolution * magFactor) == 0)) {
                        if x % (20 * resolution * magFactor) == 0 {
                            pixel = PixelData(a: alphaFactor, r: 255, g: 0, b: 0)
                        } else {
                            pixel = PixelData(a: alphaFactor, r: 255, g: 255, b: 255)
                        }
                        
                    } else if let weightedPoint = dataArray[y / magFactor][x / magFactor] {
                        let z = weightedPoint.value
                        if z != 0 {
                            var ratio = Int(round(255 * (abs(abs(z) - abs(minZ))) / zDiff))
                            if ratio < 0 {
                                ratio = 0
                            }
                            if ratio > 255 {
                                ratio = 255
                            }
                            //print("ratio=", ratio)
                            let daColor = mPlasmaColormap[ratio]
                               pixel = PixelData(a: alphaFactor, r: daColor.r, g: daColor.g, b: daColor.b)
                        }

                    }
                    if pixel != nil {
                        for j in 0..<magFactor {
                            for i in 0..<magFactor {
                                let oneDIndex = (x+i) + ((j + (yCount-1) * magFactor)-y) * xCount * magFactor
                                pixels[oneDIndex] = pixel!
                            }
                        }
                    }
                }

        }
        let end = Date()
        //print("old image array time:", Int(end.timeIntervalSince(start) * 1000), "ms")
        return generateImageFromPixels(pixelData: pixels, width: xCount * magFactor, height: yCount * magFactor)
    }
    
    
    

    
//    public func generateUiImageMap(measurementData: [Float], width: Int, height: Int) -> UIImage {
//        var pixels: [PixelData] = Array(repeating: PixelData(a: 255, r: 255, g: 0, b: 0), count: width * height)
//        for y in 0..<height {
//                for x in 0..<width {
//                    let z = measurementData[x + y * width]
//                    let ratio = Int(round(255 * (z - 0.005) / 0.008))
//                    //print(ratio)
//                    let daColor = mPlasmaColormap[ratio]
//                        pixels[x + y * width] = PixelData(a: 255, r: daColor.r, g: daColor.g, b: daColor.b)
//                }
//        }
//        return generateImageFromPixels(pixelData: pixels, width: width, height: height)
//    }
   
    
    public func generateImageFromPixels(pixelData: [PixelData], width: Int, height: Int) -> UIImage {
        var data = pixelData
        let providerRef = CGDataProvider(data: NSData(bytes: &data, length: data.count * MemoryLayout<PixelData>.size))!
        
        let cgim = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: width * MemoryLayout<PixelData>.size,
                space: rgbColorSpace,
                bitmapInfo: bitmapInfo,
                provider: providerRef,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
        )!
        return UIImage(cgImage: cgim)
    }
    
    // Called once all interp is done to free up memory
    public func clearArrays() {
        for someVal in squareAverageSizes {
            squareAverageSizeToArray[someVal] = [[]]
            bicubInterpSizeToArray[someVal] = [[]]
        }
        
        splinerWeightedAvg = [[]]
        
        // IMAGE GENERATION ONLY
//        constrainedHorizontal = [[]]
//        constrainedVertical = [[]]
//        constrainedDownleft = [[]]
//        constrainedDownright = [[]]
                
//        firstOrderWeightedUnconstrained = [[]]
//        secondOrderWeightedUnconstrained = [[]]
//        thirdOrderWeightedUnconstrained = [[]]
                
        //        thirdOrderWeightedConstrained = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
                
        //        horizontalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        verticalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        downrightDiagonalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        downleftDiagonalLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
                
        //        unconstrainedHorizontal = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        unconstrainedVertical = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        unconstrainedDownleft = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        unconstrainedDownright = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
                
        //        firstOrderWeightedLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        secondOrderWeightedLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        //        thirdOrderWeightedLinear = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
    }
    
    
    public func performLinearInterpolation() {
        //linearInterpolateLine(xStart: 50, yStart: 0, xDir: 0, yDir: 1)
        for x in 0..<realDataValues[0].count {
            // Interpolate down
            linearInterpolateLine(xStart: x, yStart: 0, xDir: 0, yDir: 1)
            // Down right
            linearInterpolateLine(xStart: x, yStart: 0, xDir: 1, yDir: 1)
            // Down left
            linearInterpolateLine(xStart: realDataValues[0].count - 1 - x, yStart: 0, xDir: -1, yDir: 1)
        }
        for y in 0..<realDataValues.count {
            // Interpolate right
            linearInterpolateLine(xStart: 0, yStart: y, xDir: 1, yDir: 0)
            // Down right
            linearInterpolateLine(xStart: 0, yStart: y, xDir: 1, yDir: 1)
            // Down left
            linearInterpolateLine(xStart: realDataValues[0].count - 1, yStart: y, xDir: -1, yDir: 1)
        }
        performWeightedLinearInterpolation()
    }

    // IMAGE GENERATION ONLY
    public func performWeightedLinearInterpolation() {
//        for x in 0..<realDataValues[0].count {
//            for y in 0..<realDataValues.count {
//                let verticalVal = verticalLinear[y][x]
//                let horizontalVal = horizontalLinear[y][x]
//                let diag1Val = downrightDiagonalLinear[y][x]
//                let diag2Val = downleftDiagonalLinear[y][x]
//
//                // Linear, Square, Cubic
//                var numerators: [Double] = [0.0, 0.0, 0.0]
//                var denominators: [Double] = [0.0, 0.0, 0.0]
//                var haveAVal = false
//
//                if verticalVal != nil {
//                    haveAVal = true
//                    let myVal = verticalVal!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//                if horizontalVal != nil {
//                    haveAVal = true
//                    let myVal = horizontalVal!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//                if diag1Val != nil {
//                    haveAVal = true
//                    let myVal = diag1Val!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//                if diag2Val != nil {
//                    haveAVal = true
//                    let myVal = diag2Val!
//                    numerators[0] += myVal.value / myVal.distance
//                    numerators[1] += myVal.value / pow(myVal.distance, 2)
//                    numerators[2] += myVal.value / pow(myVal.distance, 3)
//
//                    denominators[0] += 1.0 / myVal.distance
//                    denominators[1] += 1.0 / pow(myVal.distance, 2)
//                    denominators[2] += 1.0 / pow(myVal.distance, 3)
//                }
//
//                if haveAVal {
//                    let linWeightedVal = numerators[0] / denominators[0]
//                    let squareWeightedVal = numerators[1] / denominators[1]
//                    let cubeWeightedVal = numerators[2] / denominators[2]
//
//                    linearWeightLinearInterpolatedDataArray[y][x] = InterpolatedDataPoint(value: linWeightedVal, distance: 0.0)
//                    squareWeightLinearInterpolatedDataArray[y][x] = InterpolatedDataPoint(value: squareWeightedVal, distance: 0.0)
//                    thirdOrderWeightedLinear[y][x] = InterpolatedDataPoint(value: cubeWeightedVal, distance: 0.0)
//                }
//            }
//        }
    }
    
    //    IMAGE GENERATION ONLY
    //    public func performUnconstrainedSplineWeightedAverage() {
    //        for x in 0..<realDataValues[0].count {
    //            for y in 0..<realDataValues.count {
    //                let verticalVal = unconstrainedVertical[y][x]
    //                let horizontalVal = unconstrainedHorizontal[y][x]
    //                let diag1Val = unconstrainedDownright[y][x]
    //                let diag2Val = unconstrainedDownleft[y][x]
    //
    //                // Linear, Square, Cubic
    //                var numerators: [Double] = [0.0, 0.0, 0.0]
    //                var denominators: [Double] = [0.0, 0.0, 0.0]
    //                var haveAVal = false
    //
    //                if verticalVal != nil {
    //                    haveAVal = true
    //                    let myVal = verticalVal!
    //                    numerators[0] += myVal.value / myVal.distance
    //                    numerators[1] += myVal.value / pow(myVal.distance, 2)
    //                    numerators[2] += myVal.value / pow(myVal.distance, 3)
    //
    //                    denominators[0] += 1.0 / myVal.distance
    //                    denominators[1] += 1.0 / pow(myVal.distance, 2)
    //                    denominators[2] += 1.0 / pow(myVal.distance, 3)
    //                }
    //                if horizontalVal != nil {
    //                    haveAVal = true
    //                    let myVal = horizontalVal!
    //                    numerators[0] += myVal.value / myVal.distance
    //                    numerators[1] += myVal.value / pow(myVal.distance, 2)
    //                    numerators[2] += myVal.value / pow(myVal.distance, 3)
    //
    //                    denominators[0] += 1.0 / myVal.distance
    //                    denominators[1] += 1.0 / pow(myVal.distance, 2)
    //                    denominators[2] += 1.0 / pow(myVal.distance, 3)
    //                }
    //                if diag1Val != nil {
    //                    haveAVal = true
    //                    let myVal = diag1Val!
    //                    numerators[0] += myVal.value / myVal.distance
    //                    numerators[1] += myVal.value / pow(myVal.distance, 2)
    //                    numerators[2] += myVal.value / pow(myVal.distance, 3)
    //
    //                    denominators[0] += 1.0 / myVal.distance
    //                    denominators[1] += 1.0 / pow(myVal.distance, 2)
    //                    denominators[2] += 1.0 / pow(myVal.distance, 3)
    //                }
    //                if diag2Val != nil {
    //                    haveAVal = true
    //                    let myVal = diag2Val!
    //                    numerators[0] += myVal.value / myVal.distance
    //                    numerators[1] += myVal.value / pow(myVal.distance, 2)
    //                    numerators[2] += myVal.value / pow(myVal.distance, 3)
    //
    //                    denominators[0] += 1.0 / myVal.distance
    //                    denominators[1] += 1.0 / pow(myVal.distance, 2)
    //                    denominators[2] += 1.0 / pow(myVal.distance, 3)
    //                }
    //
    //                if haveAVal {
    //                    let linWeightedVal = numerators[0] / denominators[0]
    //                    let squareWeightedVal = numerators[1] / denominators[1]
    //                    let cubeWeightedVal = numerators[2] / denominators[2]
    //
    //                    firstOrderWeightedUnconstrained[y][x] = InterpolatedDataPoint(value: linWeightedVal, distance: 0.0)
    //                    secondOrderWeightedUnconstrained[y][x] = InterpolatedDataPoint(value: squareWeightedVal, distance: 0.0)
    //                    thirdOrderWeightedUnconstrained[y][x] = InterpolatedDataPoint(value: cubeWeightedVal, distance: 0.0)
    //                }
    //            }
    //        }
    //    }
    
    // IMAGE GENERATION ONLY
    public func linearInterpolateLine(xStart: Int, yStart: Int, xDir: Int, yDir: Int) {
//        for i in 0...1000000 {
//            let xCoord = xStart + i * xDir
//            let yCoord = yStart + i * yDir
//            let neighborX = xCoord + xDir
//            let neighborY = yCoord + yDir
//            if isOutOfBounds(x: neighborX, y: neighborY) {
//                //print("oob", neighborX, neighborY)
//                break
//            }
//            let currentVal = realDataValues[yCoord][xCoord]
//            let neighbor = realDataValues[neighborY][neighborX]
//            if currentVal != nil && neighbor != nil {
//                let trueVal = InterpolatedDataPoint(value: currentVal!.value, distance: 0.01)
//                verticalLinear[yCoord][xCoord] = trueVal
//                horizontalLinear[yCoord][xCoord] = trueVal
//                downrightDiagonalLinear[yCoord][xCoord] = trueVal
//                downleftDiagonalLinear[yCoord][xCoord] = trueVal
//            }
//            if currentVal != nil && neighbor == nil {
//                let closestExisting = findNextNeighbor(xStart: xCoord, yStart: yCoord, xDir: xDir, yDir: yDir)
//                if closestExisting != nil {
//                    let zDiff = closestExisting!.value - currentVal!.value
//                    for t in 0...closestExisting!.distance {
//                        let interpValue = currentVal!.value + zDiff * Double(t) / Double(closestExisting!.distance)
//                        var distance: Double = Double(closestExisting!.distance)
//                        if xDir != 0 && yDir != 0 {
//                            distance *= sqrt(2)
//                        }
//                        let newPoint = InterpolatedDataPoint(value: interpValue, distance: distance)
//                        if xDir == 0 {
//                            verticalLinear[yCoord + yDir * t][xCoord + xDir * t] = newPoint
//                        } else if yDir == 0 {
//                            horizontalLinear[yCoord + yDir * t][xCoord + xDir * t] = newPoint
//                        } else if xDir * yDir > 0 {
//                            downrightDiagonalLinear[yCoord + yDir * t][xCoord + xDir * t] = newPoint
//                        }  else if xDir * yDir < 0 {
//                            downleftDiagonalLinear[yCoord + yDir * t][xCoord + xDir * t] = newPoint
//                        }
//                    }
//                }
//            }
//        }
    }
    
    public func findNextNeighbor(xStart: Int, yStart: Int, xDir: Int, yDir: Int) -> (value: Double, distance: Int)? {
        for t in 1...1000000 {
            let xToCheck = xStart + t * xDir
            let yToCheck = yStart + t * yDir
            if isOutOfBounds(x: xToCheck, y: yToCheck) {
                break
            }
            let checkedVal = realDataValues[yToCheck][xToCheck]
            if checkedVal != nil {
//                let distance: Double
//                if xDir == 0 || yDir == 0 {
//                    distance = Double(t)
//                } else {
//                    distance = Double(t) * sqrt(2)
//                }
                return (checkedVal!.value, t)
            }
        }
        return nil
    }
    
    public func isOutOfBounds(x: Int, y: Int) -> Bool {
        return x < 0 || y < 0 || x >= realDataValues[0].count || y >= realDataValues.count
    }
    
}

//public func generateScale(measurementData: [Float], width: Int) -> UIImage {
////        var max = 1 - Float.greatestFiniteMagnitude
////        var min = Float.greatestFiniteMagnitude
////        for val in measurementData {
////            max = Float.maximum(val, max)
////            min = Float.minimum(val, min)
////        }
//
//    var pixels: [PixelData] = Array(repeating: PixelData(a: 255, r: 255, g: 0, b: 0), count: width * 256)
//
//    for y in 0..<256 {
//        for x in 0..<width {
//            pixels[x + y * width] = PixelData(a: 255, r: mPlasmaColormap[255 - y].r, g: mPlasmaColormap[255 - y].g, b: mPlasmaColormap[255 - y].b)
//        }
//    }
//
//    return generateImageFromPixels(pixelData: pixels, width: width, height: 256)
//
//}

let mPlasmaColormap : [PixelData] = [
    PixelData(a: 255, r: 12, g: 7, b: 135),PixelData(a: 255, r: 16, g: 7, b: 136),
    PixelData(a: 255, r: 19, g: 6, b: 137),PixelData(a: 255, r: 22, g: 6, b: 138),
    PixelData(a: 255, r: 24, g: 6, b: 140),PixelData(a: 255, r: 27, g: 6, b: 141),
    PixelData(a: 255, r: 29, g: 6, b: 142),PixelData(a: 255, r: 31, g: 5, b: 143),
    PixelData(a: 255, r: 33, g: 5, b: 144),PixelData(a: 255, r: 35, g: 5, b: 145),
    PixelData(a: 255, r: 38, g: 5, b: 146),PixelData(a: 255, r: 40, g: 5, b: 146),
    PixelData(a: 255, r: 42, g: 5, b: 147),PixelData(a: 255, r: 43, g: 5, b: 148),
    PixelData(a: 255, r: 45, g: 4, b: 149),PixelData(a: 255, r: 47, g: 4, b: 150),
    PixelData(a: 255, r: 49, g: 4, b: 151),PixelData(a: 255, r: 51, g: 4, b: 151),
    PixelData(a: 255, r: 53, g: 4, b: 152),PixelData(a: 255, r: 54, g: 4, b: 153),
    PixelData(a: 255, r: 56, g: 4, b: 154),PixelData(a: 255, r: 58, g: 4, b: 154),
    PixelData(a: 255, r: 60, g: 3, b: 155),PixelData(a: 255, r: 61, g: 3, b: 156),
    PixelData(a: 255, r: 63, g: 3, b: 156),PixelData(a: 255, r: 65, g: 3, b: 157),
    PixelData(a: 255, r: 66, g: 3, b: 158),PixelData(a: 255, r: 68, g: 3, b: 158),
    PixelData(a: 255, r: 70, g: 3, b: 159),PixelData(a: 255, r: 71, g: 2, b: 160),
    PixelData(a: 255, r: 73, g: 2, b: 160),PixelData(a: 255, r: 75, g: 2, b: 161),
    PixelData(a: 255, r: 76, g: 2, b: 161),PixelData(a: 255, r: 78, g: 2, b: 162),
    PixelData(a: 255, r: 80, g: 2, b: 162),PixelData(a: 255, r: 81, g: 1, b: 163),
    PixelData(a: 255, r: 83, g: 1, b: 163),PixelData(a: 255, r: 84, g: 1, b: 164),
    PixelData(a: 255, r: 86, g: 1, b: 164),PixelData(a: 255, r: 88, g: 1, b: 165),
    PixelData(a: 255, r: 89, g: 1, b: 165),PixelData(a: 255, r: 91, g: 0, b: 165),
    PixelData(a: 255, r: 92, g: 0, b: 166),PixelData(a: 255, r: 94, g: 0, b: 166),
    PixelData(a: 255, r: 95, g: 0, b: 166),PixelData(a: 255, r: 97, g: 0, b: 167),
    PixelData(a: 255, r: 99, g: 0, b: 167),PixelData(a: 255, r: 100, g: 0, b: 167),
    PixelData(a: 255, r: 102, g: 0, b: 167),PixelData(a: 255, r: 103, g: 0, b: 168),
    PixelData(a: 255, r: 105, g: 0, b: 168),PixelData(a: 255, r: 106, g: 0, b: 168),
    PixelData(a: 255, r: 108, g: 0, b: 168),PixelData(a: 255, r: 110, g: 0, b: 168),
    PixelData(a: 255, r: 111, g: 0, b: 168),PixelData(a: 255, r: 113, g: 0, b: 168),
    PixelData(a: 255, r: 114, g: 0, b: 169),PixelData(a: 255, r: 116, g: 0, b: 169),
    PixelData(a: 255, r: 117, g: 0, b: 169),PixelData(a: 255, r: 119, g: 1, b: 168),
    PixelData(a: 255, r: 120, g: 1, b: 168),PixelData(a: 255, r: 122, g: 1, b: 168),
    PixelData(a: 255, r: 123, g: 2, b: 168),PixelData(a: 255, r: 125, g: 2, b: 168),
    PixelData(a: 255, r: 126, g: 3, b: 168),PixelData(a: 255, r: 128, g: 3, b: 168),
    PixelData(a: 255, r: 129, g: 4, b: 167),PixelData(a: 255, r: 131, g: 4, b: 167),
    PixelData(a: 255, r: 132, g: 5, b: 167),PixelData(a: 255, r: 134, g: 6, b: 167),
    PixelData(a: 255, r: 135, g: 7, b: 166),PixelData(a: 255, r: 136, g: 7, b: 166),
    PixelData(a: 255, r: 138, g: 8, b: 166),PixelData(a: 255, r: 139, g: 9, b: 165),
    PixelData(a: 255, r: 141, g: 11, b: 165),PixelData(a: 255, r: 142, g: 12, b: 164),
    PixelData(a: 255, r: 144, g: 13, b: 164),PixelData(a: 255, r: 145, g: 14, b: 163),
    PixelData(a: 255, r: 146, g: 15, b: 163),PixelData(a: 255, r: 148, g: 16, b: 162),
    PixelData(a: 255, r: 149, g: 17, b: 161),PixelData(a: 255, r: 150, g: 18, b: 161),
    PixelData(a: 255, r: 152, g: 19, b: 160),PixelData(a: 255, r: 153, g: 20, b: 160),
    PixelData(a: 255, r: 155, g: 21, b: 159),PixelData(a: 255, r: 156, g: 23, b: 158),
    PixelData(a: 255, r: 157, g: 24, b: 157),PixelData(a: 255, r: 158, g: 25, b: 157),
    PixelData(a: 255, r: 160, g: 26, b: 156),PixelData(a: 255, r: 161, g: 27, b: 155),
    PixelData(a: 255, r: 162, g: 28, b: 154),PixelData(a: 255, r: 164, g: 29, b: 154),
    PixelData(a: 255, r: 165, g: 30, b: 153),PixelData(a: 255, r: 166, g: 32, b: 152),
    PixelData(a: 255, r: 167, g: 33, b: 151),PixelData(a: 255, r: 169, g: 34, b: 150),
    PixelData(a: 255, r: 170, g: 35, b: 149),PixelData(a: 255, r: 171, g: 36, b: 149),
    PixelData(a: 255, r: 172, g: 37, b: 148),PixelData(a: 255, r: 173, g: 38, b: 147),
    PixelData(a: 255, r: 175, g: 40, b: 146),PixelData(a: 255, r: 176, g: 41, b: 145),
    PixelData(a: 255, r: 177, g: 42, b: 144),PixelData(a: 255, r: 178, g: 43, b: 143),
    PixelData(a: 255, r: 179, g: 44, b: 142),PixelData(a: 255, r: 180, g: 45, b: 141),
    PixelData(a: 255, r: 181, g: 46, b: 140),PixelData(a: 255, r: 183, g: 47, b: 139),
    PixelData(a: 255, r: 184, g: 49, b: 138),PixelData(a: 255, r: 185, g: 50, b: 137),
    PixelData(a: 255, r: 186, g: 51, b: 137),PixelData(a: 255, r: 187, g: 52, b: 136),
    PixelData(a: 255, r: 188, g: 53, b: 135),PixelData(a: 255, r: 189, g: 54, b: 134),
    PixelData(a: 255, r: 190, g: 55, b: 133),PixelData(a: 255, r: 191, g: 57, b: 132),
    PixelData(a: 255, r: 192, g: 58, b: 131),PixelData(a: 255, r: 193, g: 59, b: 130),
    PixelData(a: 255, r: 194, g: 60, b: 129),PixelData(a: 255, r: 195, g: 61, b: 128),
    PixelData(a: 255, r: 196, g: 62, b: 127),PixelData(a: 255, r: 197, g: 63, b: 126),
    PixelData(a: 255, r: 198, g: 64, b: 125),PixelData(a: 255, r: 199, g: 66, b: 124),
    PixelData(a: 255, r: 200, g: 67, b: 123),PixelData(a: 255, r: 201, g: 68, b: 122),
    PixelData(a: 255, r: 202, g: 69, b: 122),PixelData(a: 255, r: 203, g: 70, b: 121),
    PixelData(a: 255, r: 204, g: 71, b: 120),PixelData(a: 255, r: 205, g: 72, b: 119),
    PixelData(a: 255, r: 206, g: 73, b: 118),PixelData(a: 255, r: 207, g: 75, b: 117),
    PixelData(a: 255, r: 208, g: 76, b: 116),PixelData(a: 255, r: 208, g: 77, b: 115),
    PixelData(a: 255, r: 209, g: 78, b: 114),PixelData(a: 255, r: 210, g: 79, b: 113),
    PixelData(a: 255, r: 211, g: 80, b: 112),PixelData(a: 255, r: 212, g: 81, b: 112),
    PixelData(a: 255, r: 213, g: 83, b: 111),PixelData(a: 255, r: 214, g: 84, b: 110),
    PixelData(a: 255, r: 215, g: 85, b: 109),PixelData(a: 255, r: 215, g: 86, b: 108),
    PixelData(a: 255, r: 216, g: 87, b: 107),PixelData(a: 255, r: 217, g: 88, b: 106),
    PixelData(a: 255, r: 218, g: 89, b: 105),PixelData(a: 255, r: 219, g: 91, b: 105),
    PixelData(a: 255, r: 220, g: 92, b: 104),PixelData(a: 255, r: 220, g: 93, b: 103),
    PixelData(a: 255, r: 221, g: 94, b: 102),PixelData(a: 255, r: 222, g: 95, b: 101),
    PixelData(a: 255, r: 223, g: 96, b: 100),PixelData(a: 255, r: 224, g: 98, b: 99),
    PixelData(a: 255, r: 224, g: 99, b: 98),PixelData(a: 255, r: 225, g: 100, b: 98),
    PixelData(a: 255, r: 226, g: 101, b: 97),PixelData(a: 255, r: 227, g: 102, b: 96),
    PixelData(a: 255, r: 227, g: 104, b: 95),PixelData(a: 255, r: 228, g: 105, b: 94),
    PixelData(a: 255, r: 229, g: 106, b: 93),PixelData(a: 255, r: 230, g: 107, b: 92),
    PixelData(a: 255, r: 230, g: 108, b: 92),PixelData(a: 255, r: 231, g: 110, b: 91),
    PixelData(a: 255, r: 232, g: 111, b: 90),PixelData(a: 255, r: 232, g: 112, b: 89),
    PixelData(a: 255, r: 233, g: 113, b: 88),PixelData(a: 255, r: 234, g: 114, b: 87),
    PixelData(a: 255, r: 235, g: 116, b: 86),PixelData(a: 255, r: 235, g: 117, b: 86),
    PixelData(a: 255, r: 236, g: 118, b: 85),PixelData(a: 255, r: 237, g: 119, b: 84),
    PixelData(a: 255, r: 237, g: 121, b: 83),PixelData(a: 255, r: 238, g: 122, b: 82),
    PixelData(a: 255, r: 238, g: 123, b: 81),PixelData(a: 255, r: 239, g: 124, b: 80),
    PixelData(a: 255, r: 240, g: 126, b: 80),PixelData(a: 255, r: 240, g: 127, b: 79),
    PixelData(a: 255, r: 241, g: 128, b: 78),PixelData(a: 255, r: 241, g: 129, b: 77),
    PixelData(a: 255, r: 242, g: 131, b: 76),PixelData(a: 255, r: 242, g: 132, b: 75),
    PixelData(a: 255, r: 243, g: 133, b: 74),PixelData(a: 255, r: 244, g: 135, b: 73),
    PixelData(a: 255, r: 244, g: 136, b: 73),PixelData(a: 255, r: 245, g: 137, b: 72),
    PixelData(a: 255, r: 245, g: 139, b: 71),PixelData(a: 255, r: 246, g: 140, b: 70),
    PixelData(a: 255, r: 246, g: 141, b: 69),PixelData(a: 255, r: 247, g: 143, b: 68),
    PixelData(a: 255, r: 247, g: 144, b: 67),PixelData(a: 255, r: 247, g: 145, b: 67),
    PixelData(a: 255, r: 248, g: 147, b: 66),PixelData(a: 255, r: 248, g: 148, b: 65),
    PixelData(a: 255, r: 249, g: 149, b: 64),PixelData(a: 255, r: 249, g: 151, b: 63),
    PixelData(a: 255, r: 249, g: 152, b: 62),PixelData(a: 255, r: 250, g: 154, b: 61),
    PixelData(a: 255, r: 250, g: 155, b: 60),PixelData(a: 255, r: 251, g: 156, b: 60),
    PixelData(a: 255, r: 251, g: 158, b: 59),PixelData(a: 255, r: 251, g: 159, b: 58),
    PixelData(a: 255, r: 251, g: 161, b: 57),PixelData(a: 255, r: 252, g: 162, b: 56),
    PixelData(a: 255, r: 252, g: 164, b: 55),PixelData(a: 255, r: 252, g: 165, b: 54),
    PixelData(a: 255, r: 252, g: 166, b: 54),PixelData(a: 255, r: 253, g: 168, b: 53),
    PixelData(a: 255, r: 253, g: 169, b: 52),PixelData(a: 255, r: 253, g: 171, b: 51),
    PixelData(a: 255, r: 253, g: 172, b: 50),PixelData(a: 255, r: 253, g: 174, b: 49),
    PixelData(a: 255, r: 254, g: 175, b: 49),PixelData(a: 255, r: 254, g: 177, b: 48),
    PixelData(a: 255, r: 254, g: 178, b: 47),PixelData(a: 255, r: 254, g: 180, b: 46),
    PixelData(a: 255, r: 254, g: 181, b: 46),PixelData(a: 255, r: 254, g: 183, b: 45),
    PixelData(a: 255, r: 254, g: 185, b: 44),PixelData(a: 255, r: 254, g: 186, b: 43),
    PixelData(a: 255, r: 254, g: 188, b: 43),PixelData(a: 255, r: 254, g: 189, b: 42),
    PixelData(a: 255, r: 254, g: 191, b: 41),PixelData(a: 255, r: 254, g: 192, b: 41),
    PixelData(a: 255, r: 254, g: 194, b: 40),PixelData(a: 255, r: 254, g: 195, b: 40),
    PixelData(a: 255, r: 254, g: 197, b: 39),PixelData(a: 255, r: 254, g: 199, b: 39),
    PixelData(a: 255, r: 253, g: 200, b: 38),PixelData(a: 255, r: 253, g: 202, b: 38),
    PixelData(a: 255, r: 253, g: 203, b: 37),PixelData(a: 255, r: 253, g: 205, b: 37),
    PixelData(a: 255, r: 253, g: 207, b: 37),PixelData(a: 255, r: 252, g: 208, b: 36),
    PixelData(a: 255, r: 252, g: 210, b: 36),PixelData(a: 255, r: 252, g: 212, b: 36),
    PixelData(a: 255, r: 251, g: 213, b: 36),PixelData(a: 255, r: 251, g: 215, b: 36),
    PixelData(a: 255, r: 251, g: 217, b: 36),PixelData(a: 255, r: 250, g: 218, b: 36),
    PixelData(a: 255, r: 250, g: 220, b: 36),PixelData(a: 255, r: 249, g: 222, b: 36),
    PixelData(a: 255, r: 249, g: 223, b: 36),PixelData(a: 255, r: 248, g: 225, b: 37),
    PixelData(a: 255, r: 248, g: 227, b: 37),PixelData(a: 255, r: 247, g: 229, b: 37),
    PixelData(a: 255, r: 247, g: 230, b: 37),PixelData(a: 255, r: 246, g: 232, b: 38),
    PixelData(a: 255, r: 246, g: 234, b: 38),PixelData(a: 255, r: 245, g: 235, b: 38),
    PixelData(a: 255, r: 244, g: 237, b: 39),PixelData(a: 255, r: 244, g: 239, b: 39),
    PixelData(a: 255, r: 243, g: 241, b: 39),PixelData(a: 255, r: 242, g: 242, b: 38),
    PixelData(a: 255, r: 242, g: 244, b: 38),PixelData(a: 255, r: 241, g: 246, b: 37),
    PixelData(a: 255, r: 241, g: 247, b: 36),PixelData(a: 255, r: 240, g: 249, b: 33)
]
