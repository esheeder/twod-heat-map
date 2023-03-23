//
//  HeatMapGenerator.swift
//  twod-heat-map
//
//  Created by Eric on 2/6/23.
//

import Foundation
import UIKit
import CoreGraphics



public class LiveHeatMapGenerator {
    
    // Values needed for image generation, thanks stack overflow
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    let bitsPerComponent = 8
    let bitsPerPixel = 32
    
    // The data points from above plotted on x, y coordinates. For any collisions, we add them to a running average at the point
    var realDataValues: [[WeightedDataPoint]] = [[]]
    
    // Spliners in 4 directions computed from realDataValues
    var horizontalSpliners: [HeatMapSpline] = []
    var verticalSpliners: [HeatMapSpline] = []
    var upleftSpliners: [HeatMapSpline] = []
    var uprightSpliners: [HeatMapSpline] = []
    
    // Weighted values of the above spliners
    var splinerWeightedAvg: [[WeightedDataPoint]] = [[]]
    
    // Sparse array containing square averages of splinerWeightedAvg of NxN millimeters
    var squareAverages: [[WeightedDataPoint]] = [[]]
    
    // Bicubic interpolation array of the above
    var theOneBicubArray: [[WeightedDataPoint]] = [[]]
    
    var pixelsArray: [PixelData] = []
    var pointsPlottedPixelsArray: [PixelData] = []
    
    // Values passed in on what the mapping area is. x and y in millimeters
    var graphMinX : Int = -10
    var graphMaxX : Int = 10
    var graphMinY : Int = -10
    var graphMaxY : Int = 10
    var interpSquareSize: Int = 1
    var resolution : Int = 1 // pixels per millimeter, larger = higher resolution
    
    // Calculated values based on actual data passed in. x and y in millimeters
    public var minX: Double = Double.greatestFiniteMagnitude
    public var maxX: Double = 1.0 - Double.greatestFiniteMagnitude
    public var minY: Double = Double.greatestFiniteMagnitude
    public var maxY: Double = 1.0 - Double.greatestFiniteMagnitude
    public var minZ: Double = Double.greatestFiniteMagnitude
    public var maxZ: Double = 1.0 - Double.greatestFiniteMagnitude
    
    // TODO: Could use something like this to lower spliner time
    // Calculate these values in the spliner function before parallel
    // In the spline line function, break once you are past maxXIndex or maxYIndex
    // Can start at mins but will need to offset tVals by the min as well
//    public var minXIndex: Int = 0
//    public var maxXIndex: Int = 0
//    public var minYIndex: Int = 0
//    public var maxYIndex: Int = 0
    
    //public var minZVals: [String: Double] = Double.greatestFiniteMagnitude
    //public var maxZVals : Double = 1.0 - Double.greatestFiniteMagnitude
    
    // Used to draw cursor on screen
    var lastXIndex: Int = 0
    var lastYIndex: Int = 0
    
    var zValKey = ""
    var zBounds: [String: zBound?] = [:]
    var pointsAdded = 0
    var rawData: [MultiSensorData?] = []
    var minIndexGap: Double = 0.0
    
    var ghostPixel = PixelData(a: 50, r: 255, g: 255, b: 255)
    
    //var zValDict: [String: Double] = [:]
    
    // Contain pre-calculated square and cubic values for numbers between 0 and 1 based on interpSquareSize.
    // Useful for the bicubic function to make it faster
    var precalcStepSquared: [Double] = []
    var precalcStepCubed: [Double] = []
    
    init() {

    }
    
    // x/y values should be in millimeters, resolution is pixels / millimeters, interpSquareSize is millimeters
    init(minX: Int, maxX: Int, minY: Int, maxY: Int, resolution : Int, interpSquareSize: Int, zValKey: String, zBounds: [String: zBound?]) {
        self.graphMinX = minX
        self.graphMinY = minY
        self.graphMaxX = maxX
        self.graphMaxY = maxY
        self.resolution = resolution
        self.interpSquareSize = interpSquareSize
        self.zValKey = zValKey
        self.zBounds = zBounds
        self.rawData = [MultiSensorData?](repeating: nil, count: 200000)
        self.minIndexGap = 2.0 * Double(resolution) // Min 2 millimeters between spliner points
        
        resetArrays(resetPlotted: true)
        precalcCubicValues(step: self.interpSquareSize)
    }
    
    public func changeZVals(zKey: String) {
        self.zValKey = zKey
        self.minZ = Double.greatestFiniteMagnitude
        self.maxZ = 1.0 - Double.greatestFiniteMagnitude
        resetArrays(resetPlotted: true)
        for i in 0..<pointsAdded {
            addDataPointToHeatMap(dataPoint: SensorData(x: rawData[i]!.x, y: rawData[i]!.y, z: rawData[i]!.values[self.zValKey]!))
        }
        processData()
    }
    
    // Call this when an input parameter changes
    public func regeneratePlots() {
        resetArrays(resetPlotted: false)
        processData()
    }
    
    public func resetArrays(resetPlotted: Bool = false) {
        let pixelWidth = (graphMaxX - graphMinX) * resolution
        let pixelHeight = (graphMaxY - graphMinY) * resolution
        
        if resetPlotted {
            realDataValues = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0, samplesTaken: 0), count: pixelWidth), count: pixelHeight)
        }

        if resetPlotted {
            horizontalSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelWidth, minIndexGap: self.minIndexGap), count: pixelHeight)
            for i in 0..<pixelHeight {
                horizontalSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelWidth, minIndexGap: self.minIndexGap)
            }
            verticalSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelHeight, minIndexGap: self.minIndexGap), count: pixelWidth)
            for i in 0..<pixelWidth {
                verticalSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: pixelHeight, minIndexGap: self.minIndexGap)
            }
            /*
                Say you have a 400 wide x 200 tall array:
             
                upleftSpliners[0-399] will start bottom left, going right
                   [0]             [200]          [399]
                . . . . .       . \ . . .       . . . \ .
                . . . . .   ->  . .\. . .   ->  . . . .\.
                \ . . . .       . . \ . .       . . . . \
             
                upleftSpliners[400-599] will start 1px up from bottom right, going up
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
            // TODO: Change the count to width + height -1 and redo the math in weighted avg to make things simpler
            upleftSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight), minIndexGap: self.minIndexGap), count: pixelWidth + pixelHeight - 1)
            uprightSpliners = [HeatMapSpline](repeating: HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight), minIndexGap: self.minIndexGap), count: pixelWidth + pixelHeight - 1)
            for i in 0..<upleftSpliners.count {
                upleftSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight), minIndexGap: self.minIndexGap)
                uprightSpliners[i] = HeatMapSpline(tPoints: [], zPoints: [], indexCount: max(pixelWidth, pixelHeight), minIndexGap: self.minIndexGap)
            }
        } else {
            // TODO: Can recreate these by looking at t indices without looping through everything to find where the data points are
        }
        
        splinerWeightedAvg = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: pixelWidth), count: pixelHeight)
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                splinerWeightedAvg[y][x] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
            }
        }
        
        squareAverages = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: (graphMaxX - graphMinX) / self.interpSquareSize), count: (graphMaxY - graphMinY) / self.interpSquareSize)
        for i in 0..<squareAverages.count {
            for j in 0..<squareAverages[0].count {
                squareAverages[i][j] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
            }
        }
        
        theOneBicubArray = [[WeightedDataPoint]](repeating: [WeightedDataPoint](repeating: WeightedDataPoint(value: 0.0, samplesTaken: 0), count: pixelWidth), count: pixelHeight)
        for i in 0..<theOneBicubArray.count {
            for j in 0..<theOneBicubArray[0].count {
                theOneBicubArray[i][j] = WeightedDataPoint(value: 0.0, samplesTaken: 0)
            }
        }
        
        pixelsArray = [PixelData](repeating: PixelData(a: 255, r: 0, g: 0, b: 0), count: pixelWidth * pixelHeight)
        for i in 0..<pixelsArray.count {
            pixelsArray[i] = PixelData(a: 255, r: 0, g: 0, b: 0)
        }
        pointsPlottedPixelsArray = [PixelData](repeating: PixelData(a: 0, r: 0, g: 0, b: 0), count: pixelWidth * pixelHeight)
        // Will want to uncomment this out if writing values in parallel, will just take up more memory
//        for i in 0..<pointsPlottedPixelsArray.count {
//            pixelsArray[i] = PixelData(a: 0, r: 0, g: 0, b: 0)
//        }
    }
    
    public func processNewDataPoint(dataPoint: MultiSensorData) {
        rawData.append(dataPoint)
        pointsAdded += 1
        addDataPointToHeatMap(dataPoint: SensorData(x: dataPoint.x, y: dataPoint.y, z: dataPoint.values[self.zValKey]!))
    }
    
    private func addDataPointToHeatMap(dataPoint: SensorData) -> Void {
        let xIndex = getXIndexFromXCoord(dataPoint.x)
        let yIndex = getYIndexFromYCoord(dataPoint.y)

        if isOutOfBounds(x: xIndex, y: yIndex) {
            //print("trying to plot point outside chart range at x=", dataPoint.x, "y=", dataPoint.y)
            //print("xIndex=", xIndex, "yIndex=", yIndex)
            //print("realDataValues[0].count=", realDataValues[0].count)
            //print("realDataValues.count=", realDataValues.count)
            return
        }

        self.minX = Double.minimum(self.minX, dataPoint.x)
        self.maxX = Double.maximum(self.maxX, dataPoint.x)

        self.minY = Double.minimum(self.minY, dataPoint.y)
        self.maxY = Double.maximum(self.maxY, dataPoint.y)

        self.lastXIndex = xIndex
        self.lastYIndex = yIndex

        verticalSpliners[xIndex].shouldUpdate = true
        horizontalSpliners[yIndex].shouldUpdate = true
        upleftSpliners[xIndex + yIndex].shouldUpdate = true
        //getSplinerForPixel(xIndex: xIndex, yIndex: yIndex, direction: "upleft").shouldUpdate = true
        getSplinerForPixel(xIndex: xIndex, yIndex: yIndex, direction: "upright").shouldUpdate = true
        
        let weightedPoint = realDataValues[yIndex][xIndex]
        let newVal = (weightedPoint.value * Double(weightedPoint.samplesTaken) + dataPoint.z) / Double(weightedPoint.samplesTaken + 1)
        realDataValues[yIndex][xIndex] = WeightedDataPoint(value: newVal, samplesTaken: weightedPoint.samplesTaken + 1)
        self.minZ = Double.minimum(self.minZ, dataPoint.z)
        self.maxZ = Double.maximum(self.maxZ, dataPoint.z)
        
        pointsPlottedPixelsArray[getOneDPixelIndex(x: xIndex, y: yIndex)] = ghostPixel
    }
    
    
    // PROCESS DATA HERE
    public func processData(printBenchmarks: Bool = false) {
        let totalStart = Date()
        
        // Step 1: Fill up the cubic spliners in 4 directions and compute the interpolated values
        let splineStart = Date()
        performSplineInterpolation()
        let splineEnd = Date()
        
        // Step 2: Use the interpolated values from before to compute a weighted average for each pixel
        let weightedStart = Date()
        performWeightedAverage()
        let weightedEnd = Date()
        
        // Step 3: Do square averages over the weighted values
        let squareAvgStart = Date()
        createSquareAverages(squareSize: self.interpSquareSize)
        let squareAvgEnd = Date()
        
        // Step 4: Do bicubic interpolation/smoothing based on the square average array
        let bicubStart = Date()
        performBicubicInterpolation(squareSizeInMm: self.interpSquareSize)
        let bicubEnd = Date()

        let totalEnd = Date()
        
        if printBenchmarks {
            print("")
            print("splining:", Int(splineEnd.timeIntervalSince(splineStart) * 1000), "ms")
            print("weighted avg:", Int(weightedEnd.timeIntervalSince(weightedStart) * 1000), "ms")
            print("square avg:", Int(squareAvgEnd.timeIntervalSince(squareAvgStart) * 1000), "ms")
            print("bicub:", Int(bicubEnd.timeIntervalSince(bicubStart) * 1000), "ms")
            print("TOTAL PROCESS TIME:", Int(totalEnd.timeIntervalSince(totalStart) * 1000), "ms")
            print("")
        }
        
    }
    
    public func performSplineInterpolation() {
        let pixelWidth = self.realDataValues[0].count
        let pixelHeight = self.realDataValues.count
        
        // Loop up to top row but don't include it beacuse upleft diagonals would go out of bounds
        DispatchQueue.concurrentPerform(iterations: pixelHeight - 1) {y in
            // Horizontal
            self.cubicSplineInterpolateLine(startX: 0, startY: y, xDir: 1, yDir: 0, spliner: self.horizontalSpliners[y])
            
            // Up left spliners, starting 1 pixel up from bottom right and going up
            self.cubicSplineInterpolateLine(startX: pixelWidth - 1, startY: y + 1, xDir: -1, yDir: 1, spliner: self.upleftSpliners[pixelWidth + y])
            
            // Up right spliners, starting top left and going to bottom left
            self.cubicSplineInterpolateLine(startX: 0, startY: (pixelHeight - 1 - y), xDir: 1, yDir: 1, spliner: self.uprightSpliners[y])
        }

        // Very top row
        let topYIndex = pixelHeight - 1
        self.cubicSplineInterpolateLine(startX: 0, startY: topYIndex, xDir: 1, yDir: 0, spliner: self.horizontalSpliners[topYIndex])
        self.cubicSplineInterpolateLine(startX: 0, startY: (pixelHeight - 1 - topYIndex), xDir: 1, yDir: 1, spliner: self.uprightSpliners[topYIndex])
        
        // Loop up to right side but don't include it beacuse upright diagonals would go out of bounds
        DispatchQueue.concurrentPerform(iterations: pixelWidth - 1) {x in
            // Vertical
            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: 0, yDir: 1, spliner: self.verticalSpliners[x])
            
            // Up left spliners, starting from bottom left and going to bottom right
            self.cubicSplineInterpolateLine(startX: x, startY: 0, xDir: -1, yDir: 1, spliner: self.upleftSpliners[x])
            
            // Up right
            self.cubicSplineInterpolateLine(startX: x + 1, startY: 0, xDir: 1, yDir: 1, spliner: self.uprightSpliners[pixelHeight + x])
        }
        // Very right side
        let rightXIndex = pixelWidth - 1
        self.cubicSplineInterpolateLine(startX: rightXIndex, startY: 0, xDir: -1, yDir: 1, spliner: self.upleftSpliners[rightXIndex])
        self.cubicSplineInterpolateLine(startX: rightXIndex, startY: 0, xDir: 0, yDir: 1, spliner: self.verticalSpliners[rightXIndex])
    }
    
    // startX and startY should be index values
    public func cubicSplineInterpolateLine(startX: Int, startY: Int, xDir: Int, yDir: Int, spliner: HeatMapSpline) {
        //print("START x: \(startX), y: \(startY), xDir: \(xDir), yDir: \(yDir)")
        if !spliner.shouldUpdate {
            //print("not told to update, returning")
            return
        }
        var tPoints : [Double] = []
        var zValues : [Double] = []
        // TODO: Clean this up, can do something like spliner.maxIndex once those are computed
        for t in 0..<100000 {
            let xCoord = startX + t * xDir
            let yCoord = startY + t * yDir
            if xCoord >= realDataValues[0].count || yCoord >= realDataValues.count || xCoord < 0 || yCoord < 0 {
                break
            }
            let val = self.realDataValues[yCoord][xCoord]
            if val.samplesTaken > 0 {
                tPoints.append(Double(t))
                zValues.append(val.value)
            }
        }
        //print("tPoints.count=", tPoints.count)
        //print(tPoints)
        if tPoints.count >= 2 {
            spliner.setPoints(newTs: tPoints, newZs: zValues)
        }
        
        spliner.shouldUpdate = false
        
        //print("END x: \(startX), y: \(startY), xDir: \(xDir), yDir: \(yDir)")
    }
    
    public func performWeightedAverage() {
        let imageWidth = self.realDataValues[0].count
        let imageHeight = self.realDataValues.count
        
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

        let upleftSpliner = getSplinerForPixel(xIndex: x, yIndex: y, direction: "upleft")
        if x + y < imageWidth {
            // Upleft spliners that start at bottom
            if let diag1Val = upleftSpliner.zCalcs[y] {
                valuesUsed += 1
                let cubed = pow(diag1Val.distance * 1.41, 3) // 1.41 = sqrt(2) approx
                numerator += diag1Val.value / cubed
                denominator += 1.0 / cubed
            }
        } else {
            // Upleft spliners that start on the right
            if let diag1Val = upleftSpliner.zCalcs[imageWidth - x - 1] {
                valuesUsed += 1
                let cubed = pow(diag1Val.distance * 1.41, 3) // 1.41 = sqrt(2) approx
                numerator += diag1Val.value / cubed
                denominator += 1.0 / cubed
            }
        }

        // Upright spliners that start at left
        let uprightSpliner = getSplinerForPixel(xIndex: x, yIndex: y, direction: "upright")
        if y >= x {
            if let diag2Val = uprightSpliner.zCalcs[x] {
                valuesUsed += 1
                let cubed = pow(diag2Val.distance * 1.41, 3)
                numerator += diag2Val.value / cubed
                denominator += 1.0 / cubed
            }
        } else {
            // Upright spliners that start on the bottom
            if let diag2Val = uprightSpliner.zCalcs[y] {
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
            squareAverages[y][x] = WeightedDataPoint(value: average, samplesTaken: pointsTallied)
        } else {
            squareAverages[y][x] = WeightedDataPoint(value: self.minZ, samplesTaken: 0)
        }
    }
    
    // TODO: Some sort of recursive function that fills in empty squares based on neighbor values
    private func fillInSquareAverages(squareSize: Int) {
        var daArray = squareAverages
        for x in 0..<daArray[0].count {
            for y in 0..<daArray.count {
                if daArray[y][x].samplesTaken == 0 {

                }
            }
        }
    }
    

    
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
        let xCount = squareAverages[0].count - 1
        let yCount = squareAverages.count - 1

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
        let mapValues = squareAverages
        
        if mapValues[yStartIndex][xStartIndex].samplesTaken <= 0 {
//            for i in 0..<squareSizePx {
//                let xIndex = xStartIndex * squareSizePx + squareSizePx / 2 + i
//                if xIndex >= realDataValues[0].count {
//                    break
//                }
//                for j in 0..<squareSizePx {
//                    let yIndex = yStartIndex * squareSizePx + squareSizePx / 2 + j
//                    if yIndex >= realDataValues.count {
//                        break
//                    }
//                    theOneBicubArray[yIndex][xIndex] = WeightedDataPoint(value: self.minZ, samplesTaken: 1)
//                }
//            }
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
        
        
        // Loop x and y from "0 to 1" by steps based on square size
        for i in 0..<squareSizePx {
            let xIndex = xStartIndex * squareSizePx + squareSizePx / 2 + i
//            if xIndex >= realDataValues[0].count {
//                break
//            }
            
            let x1: Double = Double(i) / Double(interpSquareSize * resolution)
            let x2 = precalcStepSquared[i]
            let x3 = precalcStepCubed[i]

            
            for j in 0..<squareSizePx {
                let yIndex = yStartIndex * squareSizePx + squareSizePx / 2 + j
//                if yIndex >= realDataValues.count {
//                    break
//                }
                
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
    
    public func getSplinerForPixel(xIndex: Int, yIndex: Int, direction: String) -> HeatMapSpline {
        if direction == "horizontal" {
            return horizontalSpliners[yIndex]
        } else if direction == "vertical" {
            return verticalSpliners[xIndex]
        } else if direction == "upleft" {
            return upleftSpliners[xIndex + yIndex]
        } else if direction == "upright" {
            return uprightSpliners[realDataValues.count - 1 + xIndex - yIndex]
        }
        print("Hmmm, probably shouldn't be here. Did you typo the direction string?")
        return horizontalSpliners[0]
    }
    
    // Faster function that is more restrained
    public func createLiveHeatImage(addGrid: Bool = true, addPointer: Bool = true) -> UIImage {
        let xCount = theOneBicubArray[0].count
        let yCount = theOneBicubArray.count
        let zDiff = abs(abs(self.maxZ) - abs(self.minZ))
        let whitePixel = PixelData(a: 255, r: 255, g: 255, b: 255)
        
        let heatStart = Date()
        // Fill in heat map colors
        DispatchQueue.concurrentPerform(iterations: yCount) {i in
            fillInHeatRow(y: i, zDiff: zDiff)
        }
        
        // Add white dots every 10 mm
        if addGrid {
            let markerXCount = xCount / self.resolution / 10
            let markerYCount = yCount / self.resolution / 10
            DispatchQueue.concurrentPerform(iterations: markerXCount * markerYCount) {i in
                fillInPixel(x: 10 * self.resolution * (i % markerXCount), y: 10 * self.resolution * (i / markerXCount), pixel: whitePixel)
            }
        }

        // Add teal, circular pointer
        if addPointer {
            fillInPointerPixels()
        }
        let heatEnd = Date()
        //print("heat image:", Int(heatEnd.timeIntervalSince(heatStart) * 1000), "ms")
        
        return generateImageFromPixels(pixelData: self.pixelsArray, width: xCount, height: yCount)
    }
    
    public func createPointsPlottedOverlay() -> UIImage {
        return generateImageFromPixels(
            pixelData: self.pointsPlottedPixelsArray,
            width: realDataValues[0].count,
            height: realDataValues.count)
    }
    
    private func fillInPixel(x: Int, y: Int, pixel: PixelData) {
        let oneDIndex = x + (self.theOneBicubArray.count - 1 - y) * self.theOneBicubArray[0].count
        self.pixelsArray[oneDIndex] = pixel
    }
    
    private func getOneDPixelIndex(x: Int, y: Int) -> Int {
        return x + (self.theOneBicubArray.count - 1 - y) * self.theOneBicubArray[0].count
    }
    
    private func fillInHeatRow(y: Int, zDiff: Double) {
        let daRow = self.theOneBicubArray[y]
        for x in 0..<daRow.count{
            let mahPoint = daRow[x]
            let oneDIndex = getOneDPixelIndex(x: x, y: y)
            if mahPoint.samplesTaken > 0 {
                let z = mahPoint.value
                var ratio = Int(round(255 * (abs(z - self.minZ) / zDiff)))
                if ratio < 0 {
                    ratio = 0
                }
                if ratio > 255 {
                    ratio = 255
                }
                let daColor = mPlasmaColormap[ratio]
                self.pixelsArray[oneDIndex] = PixelData(a: 255, r: daColor.r, g: daColor.g, b: daColor.b)
            }
        }
    }
    
    private func fillInPointerPixels() {
        let tealPixel = PixelData(a: 255, r: 20, g: 255, b: 247)
        
        // Center
        if isInBounds(x: lastXIndex, y: lastYIndex) {
            fillInPixel(x: lastXIndex, y: lastYIndex, pixel: tealPixel)
        }
        
        // Left + Right Edges
        for y in lastYIndex-1...lastYIndex+1 {
            if isInBounds(x: lastXIndex-2, y: y) {
                fillInPixel(x: lastXIndex-2, y: y, pixel: tealPixel)
            }
            if isInBounds(x: lastXIndex+2, y: y) {
                fillInPixel(x: lastXIndex+2, y: y, pixel: tealPixel)
            }
        }
        
        // Top + Bottom edges
        for x in self.lastXIndex-1...self.lastXIndex+1 {
            if isInBounds(x: x, y: lastYIndex-2) {
                fillInPixel(x: x, y: lastYIndex - 2, pixel: tealPixel)
            }
            if isInBounds(x: x, y: lastYIndex+2) {
                fillInPixel(x: x, y: lastYIndex + 2, pixel: tealPixel)
            }
        }
    }

    // Run through the data and set color values based on the z value of each square compared to the min/max
    // Note: Converts data array to 1D for the sake of creating the image
    public func createHeatMapImageFromDataArray(dataArray : [[DataPoint?]], showSquares: Bool = true, magFactor: Int = 1, alphaFactor: UInt8 = 255) -> UIImage {
        let xCount = dataArray[0].count
        let yCount = dataArray.count
        //print("xCount=", xCount, "yCount=", yCount)
        
        var pixels: [PixelData] = Array(repeating: PixelData(a: alphaFactor, r: 0, g: 0, b: 0), count: xCount * yCount * magFactor * magFactor)
                    // TODO: Unnecessary abs?
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
                            var ratio = Int(round(255 * (abs(abs(z) - abs(self.minZ))) / zDiff))
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

        splinerWeightedAvg = [[]]
        squareAverages = [[]]
        theOneBicubArray = [[]]
    }

    
    public func isOutOfBounds(x: Int, y: Int) -> Bool {
        return x < 0 || y < 0 || x >= realDataValues[0].count || y >= realDataValues.count
    }
    
    public func isInBounds(x: Int, y: Int) -> Bool {
        return x >= 0 && y >= 0 && x < realDataValues[0].count && y < realDataValues.count
    }
    
}




public protocol DataPoint {
    var value: Double { get set }
}

public struct WeightedDataPoint : DataPoint {
    public var value: Double
    public var samplesTaken: Int
}

public struct MultiSensorData {
    var x: Double
    var y: Double
    var values: [String: Double]
}

public struct MultiWeightedDataPoint {
    public var values: [String : WeightedDataPoint]
}

public struct InterpolatedDataPoint : DataPoint {
    public var value: Double
    public var distance: Double // Distance = space between 2 interpolated points, probably in pixels
}

public struct zBound {
    var min: Double?
    var max: Double?
}

public struct PixelData {
    var a: UInt8
    var r: UInt8
    var g: UInt8
    var b: UInt8
}
