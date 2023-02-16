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
    var constrainedCubic: Bool
    var exponentialWeighted: Bool
    var dangerGap: Double
    
    var resolution : Int = 1 // pixels per millimeter, larger = higher resolution
    var interpSquareSize: Int = 20 // millimeters
    
    // Calculated values based on actual data passed in. x and y in millimeters
    private var actualMinX : Double = Double.greatestFiniteMagnitude
    private var actualMaxX : Double = 1.0 - Double.greatestFiniteMagnitude
    private var actualMinY : Double = Double.greatestFiniteMagnitude
    private var actualMaxY : Double = 1.0 - Double.greatestFiniteMagnitude
    private var minZ : Double = Double.greatestFiniteMagnitude
    private var maxZ : Double = 1.0 - Double.greatestFiniteMagnitude
    
    // Different arrays for holding data
    
    // A storage of all of the data we've seen
    var rawData : [SensorData?] = Array(repeating: nil, count: 160000)
    var pointsAdded = 0
    
    // The data points from above plotted on x, y coordinates. For any collisions, we add them to a running average at the point
    var heatMapDataArray : [[WeightedDataPoint?]] = [[]]
    
    // An array of the data above that uses spline interpolation along rows/columns to fill in the blank spots of the data area
    var splineInterpolatedDataArray : [[InterpolatedDataPoint?]] = [[]]
    
    var horizontalSplineInterpolatedDataArray : [[InterpolatedDataPoint?]] = [[]]
    var verticalSplineInterpolatedDataArray : [[InterpolatedDataPoint?]] = [[]]
    
    // A sparse array that holds the running average for each interpSquareSize x interpSquareSize square from splineInterpolatedDataArray
    var squareAverageDataArray : [[WeightedDataPoint?]] = [[]]
    
    // The bicubic interpolation data from the square average data array
    var bicubicInterpDataArray : [[WeightedDataPoint?]] = [[]]
    
    // Contain pre-calculated square and cubic values for numbers between 0 and 1 based on interpSquareSize.
    // Useful for the bicubic function to make it faster
    var precalcStepSquared : [Double] = []
    var precalcStepCubed : [Double] = []
    
    
    var pointsSet : Int = 0
    
    // x/y values should be in millimeters, resolution is pixels / millimeters, interpSquareSize is millimeters
    init(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int, _ resolution : Int, _ interpSquareSize: Int, _ dangerGap: Double, _ constrainedCubic: Bool, _ exponentialWeighted: Bool) {
        self.graphMinX = minX
        self.graphMinY = minY
        self.graphMaxX = maxX
        self.graphMaxY = maxY
        self.resolution = resolution
        self.interpSquareSize = interpSquareSize
        self.dangerGap = dangerGap
        self.constrainedCubic = constrainedCubic
        self.exponentialWeighted = exponentialWeighted
        
        resetArrays()
    }
    
    // Call this when an input parameter changes
    public func regeneratePlots() {
        resetArrays()

        for dataPoint in rawData {
            if dataPoint != nil {
                addDataPointToHeatMap(dataPoint: dataPoint!)
            }
        }
       
        
        processData()
    }
    private func resetArrays() {
        heatMapDataArray = [[WeightedDataPoint?]](repeating: [WeightedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        splineInterpolatedDataArray = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        squareAverageDataArray = [[WeightedDataPoint?]](repeating: [WeightedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) / interpSquareSize), count: (graphMaxY - graphMinY) / interpSquareSize)
        bicubicInterpDataArray = [[WeightedDataPoint?]](repeating: [WeightedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        horizontalSplineInterpolatedDataArray = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        verticalSplineInterpolatedDataArray = [[InterpolatedDataPoint?]](repeating: [InterpolatedDataPoint?](repeating: nil, count: (graphMaxX - graphMinX) * resolution), count: (graphMaxY - graphMinY) * resolution)
        pointsSet = 0
    }
    
    public func processData () {
        for x in 0..<heatMapDataArray[0].count {
            for y in 0..<heatMapDataArray.count {
                let value = heatMapDataArray[y][x]?.value
                if value != nil {
                    print(getAbsoluteCoordInMmFromI(graphMin: graphMinX, graphMax: graphMinY, i: x), ",", getAbsoluteCoordInMmFromI(graphMin: graphMinY, graphMax: graphMaxY, i: heatMapDataArray.count - 1 - y) , ",", abs(Float(value!)), separator: "")
                }
            }
        }
        precalcCubicValues(step: interpSquareSize)
        performSplineInterpolation()
        createSquareAverages()
        performBicubicInterpolation()
    }
    
    public func processNewDataPoint(dataPoint: SensorData) {
        rawData[pointsAdded] = dataPoint
        pointsAdded += 1
        addDataPointToHeatMap(dataPoint: dataPoint)
    }
    
    private func addDataPointToHeatMap(dataPoint: SensorData) -> Void {
        let xIndex = Int(round((dataPoint.x - Double(graphMinX)) * Double(resolution)))
        let yIndex = (heatMapDataArray.count - 1) - Int(round((dataPoint.y - Double(graphMinY)) * Double(resolution)))
        
        if xIndex < 0 || xIndex >= heatMapDataArray[0].count || yIndex < 0 || yIndex >= heatMapDataArray.count {
//            print("trying to plot point outside chart range at x=", dataPoint.x, "y=", dataPoint.y)
//            print("xIndex=", xIndex, "yIndex=", yIndex)
//            print("heatMapDataArray[0].count=", heatMapDataArray[0].count)
//            print("heatMapDataArray.count=", heatMapDataArray.count)
            return
        }
        
        //print("xPos is", xPos, "yPos is", yPos)
        let weightedPoint = heatMapDataArray[yIndex][xIndex]
        if weightedPoint == nil {
            heatMapDataArray[yIndex][xIndex] = WeightedDataPoint(value: dataPoint.z, samplesTaken: 1)
            pointsSet += 1
        } else {
            let newVal = (weightedPoint!.value * Double(weightedPoint!.samplesTaken) + dataPoint.z) / Double(weightedPoint!.samplesTaken + 1)
            heatMapDataArray[yIndex][xIndex] = WeightedDataPoint(value: newVal, samplesTaken: weightedPoint!.samplesTaken + 1)

        }
        
        self.minZ = Double.minimum(self.minZ, dataPoint.z)
        self.maxZ = Double.maximum(self.maxZ, dataPoint.z)
    }
    
    public func performSplineInterpolation() {
        for y in 0..<heatMapDataArray[0].count {
            cubicSplineInterpolateLine(c: y, horizontal: true)
        }
        for x in 0..<heatMapDataArray.count {
            cubicSplineInterpolateLine(c: x, horizontal: false)
        }
        performSplineWeightedAverage()
    }
    
    public func cubicSplineInterpolateLine(c: Int, horizontal: Bool) {
        var xPoints : [Double] = []
        var zValues : [Double] = []
        var minI = 10000000
        var maxI = 0
        let rowSize = horizontal ? heatMapDataArray.count : heatMapDataArray[0].count
        for i in 0..<rowSize {
            var val : Double? = nil
            if horizontal {
                val = heatMapDataArray[i][c]?.value
            } else {
                val = heatMapDataArray[c][i]?.value
            }
            if val != nil {
                xPoints.append(Double(i))
                zValues.append(val!)
                maxI = i
                if minI == 10000000 {
                    minI = i
                }
            }
        }
        
        if xPoints.count >= 3 {

//            let midValue = xPoints[xPoints.count / 2]
//            let xDiffTotal = abs(xPoints.last! - xPoints.first!)
//            let xDiffFirstHalf = abs(midValue - xPoints.first!)
//            let xDiffSecondHalf = abs(midValue - xPoints.last!)

//            print("xDiffFirstHalf=", xDiffFirstHalf / Double(10), "cm")
//            print("xDiffSecondHalf=", xDiffSecondHalf / Double(10), "cm")
//            print("xDiffTotal=", xDiffTotal / Double(10), "cm")

            // TODO: This will probably need some fine tuning
            // if xDiffTotal >= 30 && (xDiffFirstHalf >= 10 && xDiffSecondHalf >= 10)
            let spliner = ConstrainedCubicSpline(xPoints: xPoints, yPoints: zValues, maxDistance: Double(30 * resolution))
            for i in minI..<maxI {
                //let xCoord = getAbsoluteCoordInMmFromI(graphMin: graphMinX, graphMax: graphMaxX, i: interpI)
                //print("spline interp at x=", i, "y=", y, "is", spliner.interpolate(Double(i)))
                let splineValues = spliner.interpolate(Double(i))
                if splineValues != nil {
                    if horizontal {
                        horizontalSplineInterpolatedDataArray[i][c] = InterpolatedDataPoint(value: splineValues!.value, distance: splineValues!.distance)
                    } else {
                        verticalSplineInterpolatedDataArray[c][i] = InterpolatedDataPoint(value: splineValues!.value, distance: splineValues!.distance)
                    }
                }

            }
        }
    }
    
    public func performSplineWeightedAverage() {
        for x in 0..<heatMapDataArray[0].count {
            for y in 0..<heatMapDataArray.count {
                let verticalVal = verticalSplineInterpolatedDataArray[y][x]
                let horizontalVal = horizontalSplineInterpolatedDataArray[y][x]
                //print("horizontalVal=", horizontalVal)
                if verticalVal != nil && horizontalVal != nil {
                    // Squared formula
                    let totalDistance = pow(horizontalVal!.distance, 2) + pow(verticalVal!.distance, 2)
                    let yWeight = pow(horizontalVal!.distance, 2) / totalDistance
                    let xWeight = pow(verticalVal!.distance, 2) / totalDistance
                    let weightedVal = yWeight * verticalVal!.value + xWeight * horizontalVal!.value
                    // Linear formula
//                    let totalDistance = horizontalVal!.distance + verticalVal!.distance
//                    let yWeight = horizontalVal!.distance / totalDistance
//                    let xWeight = verticalVal!.distance / totalDistance
//                    let weightedVal = yWeight * verticalVal!.value + xWeight * horizontalVal!.value
                    //print("weightedVal=", weightedVal)
                    splineInterpolatedDataArray[y][x] = InterpolatedDataPoint(value: weightedVal, distance: 0.0)
                } else if verticalVal != nil {
                    splineInterpolatedDataArray[y][x] = verticalVal
                } else if horizontalVal != nil {
                    splineInterpolatedDataArray[y][x] = horizontalVal
                }
            }
        }
    }
    
    public func getAbsoluteCoordInMmFromI(graphMin: Int, graphMax: Int, i: Int) -> Double {
        return Double(graphMin) + Double(i) / Double(resolution)
    }
    

    // Loop through data in chunks of size x size and set the bottom left pixel to that data
    public func createSquareAverages() {
        let horizontalIterations = (graphMaxX - graphMinX) / interpSquareSize
        let verticalIterations = (graphMaxY - graphMinY) / interpSquareSize
        for x in 0..<horizontalIterations {
            for y in 0..<verticalIterations {
                var localSum : Double = 0.0
                var pointsTallied = 0
                for i in 0..<interpSquareSize * resolution {
                    for j in 0..<interpSquareSize * resolution {
                        let z = splineInterpolatedDataArray[y * interpSquareSize * resolution + j][x * interpSquareSize * resolution + i]?.value
                        if z != nil {
                            localSum += z!
                            pointsTallied += 1
                        }
                    }
                }
                //print("pointsTallied=", pointsTallied)
                if pointsTallied > 0 {
                    let average = localSum / Double(pointsTallied)
                    let newPoint = WeightedDataPoint(value: average, samplesTaken: 0)
                    squareAverageDataArray[y][x] = newPoint
//                    for i in 0..<interpSquareSize {
//                        for j in 0..<interpSquareSize {
//                            bicubicInterpDataArray[x * interpSquareSize + i][y * interpSquareSize + j] = newPoint
//                        }
//                    }
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
//        print("precalcStepSquared=", precalcStepSquared)
//        print("precalcStepCubed=", precalcStepCubed)
    }
    
    public func performBicubicInterpolation() {
        for x in 0..<squareAverageDataArray[0].count {
            for y in 0..<squareAverageDataArray.count {
                bicubInterpSquare(x: x, y: y)
            }
        }
//        bicubInterpSquare(x: 1, y: 3)
    }
    
    private func bicubInterpSquare(x: Int, y: Int) {
        let mapValues = squareAverageDataArray
        let xMaxIndex = mapValues[0].count - 1
        let yMaxIndex = mapValues.count - 1
        
        var x1Index = x - 1
        let x2Index = x
        var x3Index = x + 1
        var x4Index = x + 2
        
        if x1Index < 0 {
            x1Index = 0
        }
        if x3Index > xMaxIndex {
            x3Index = xMaxIndex
        }
        if x4Index > xMaxIndex {
            x4Index = xMaxIndex
        }
        
        var y1Index = y + 2
        var y2Index = y + 1
        let y3Index = y
        var y4Index = y - 1
        
        if y4Index < 0 {
            y4Index = 0
        }
        if y1Index > yMaxIndex {
            y1Index = yMaxIndex
        }
        if y2Index > yMaxIndex {
            y2Index = yMaxIndex
        }
        
        let currentVal = mapValues[y][x]?.value
        if currentVal == nil {
            //print("no value for x=", x, "y=", y)
            return
        }

//        print("x=", x, "y=", y)
//        print("x1Index=", x1Index, "y1Index=", y1Index)
//        print("mapValues[x1Index][y1Index]=", mapValues[x1Index][y1Index])
        
        // Working before swap
//        let p2 : [[WeightedDataPoint?]] = [
//            [mapValues[x1Index][y1Index], mapValues[x2Index][y1Index], mapValues[x3Index][y1Index], mapValues[x4Index][y1Index]],
//            [mapValues[x1Index][y2Index], mapValues[x2Index][y2Index], mapValues[x3Index][y2Index], mapValues[x4Index][y2Index]],
//            [mapValues[x1Index][y3Index], mapValues[x2Index][y3Index], mapValues[x3Index][y3Index], mapValues[x4Index][y3Index]],
//            [mapValues[x1Index][y4Index], mapValues[x2Index][y4Index], mapValues[x3Index][y4Index], mapValues[x4Index][y4Index]],
//        ]
        
        // Check top row
        let topRow = [mapValues[y4Index][x1Index], mapValues[y4Index][x2Index], mapValues[y4Index][x3Index], mapValues[y4Index][x4Index]]
        if topRow[0] == nil || topRow[1] == nil || topRow[2] == nil || topRow[3] == nil {
            y4Index = y3Index
        }
        
        // Check 3rd row
        let thirdRow = [mapValues[y2Index][x1Index], mapValues[y2Index][x2Index], mapValues[y2Index][x3Index], mapValues[y2Index][x4Index]]
        if thirdRow[0] == nil || thirdRow[1] == nil || thirdRow[2] == nil || thirdRow[3] == nil {
            y2Index = y3Index
        }
        
        // Check bottom row
        let bottomRow = [mapValues[y1Index][x1Index], mapValues[y1Index][x2Index], mapValues[y1Index][x3Index], mapValues[y1Index][x4Index]]
        if bottomRow[0] == nil || bottomRow[1] == nil || bottomRow[2] == nil || bottomRow[3] == nil {
            y1Index = y2Index
        }
        
        // Check left column
        let leftColumn = [mapValues[y1Index][x1Index], mapValues[y2Index][x1Index], mapValues[y3Index][x1Index], mapValues[y4Index][x1Index]]
        if leftColumn[0] == nil || leftColumn[1] == nil || leftColumn[2] == nil || leftColumn[3] == nil {
            x1Index = x2Index
        }
        
        // Check 3rd column
        let thirdColumn = [mapValues[y1Index][x3Index], mapValues[y2Index][x3Index], mapValues[y3Index][x3Index], mapValues[y4Index][x3Index]]
        if thirdColumn[0] == nil || thirdColumn[1] == nil || thirdColumn[2] == nil || thirdColumn[3] == nil {
            x3Index = x2Index
        }
        
        // Check last column
        let lastColumn = [mapValues[y1Index][x4Index], mapValues[y2Index][x4Index], mapValues[y3Index][x4Index], mapValues[y4Index][x4Index]]
        if lastColumn[0] == nil || lastColumn[1] == nil || lastColumn[2] == nil || lastColumn[3] == nil {
            x4Index = x3Index
        }
        
        let p2 : [[DataPoint?]] = [
            [mapValues[y1Index][x1Index], mapValues[y2Index][x1Index], mapValues[y3Index][x1Index], mapValues[y4Index][x1Index]],
            [mapValues[y1Index][x2Index], mapValues[y2Index][x2Index], mapValues[y3Index][x2Index], mapValues[y4Index][x2Index]],
            [mapValues[y1Index][x3Index], mapValues[y2Index][x3Index], mapValues[y3Index][x3Index], mapValues[y4Index][x3Index]],
            [mapValues[y1Index][x4Index], mapValues[y2Index][x4Index], mapValues[y3Index][x4Index], mapValues[y4Index][x4Index]],
        ]
        
        var p : [[Double]] = [
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0]
        ]
        
        for i in 0...3 {
            for j in 0...3 {
                if p2[i][j] == nil {
                    //print("missing neighbor value")
                    return
                } else {
                    p[i][j] = p2[i][j]!.value
                }
            }
        }
       // print("going to interpolate for x=", x, "y=", y)
            
            
        
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
        
        for i in 0..<interpSquareSize * resolution {
            let x1 : Double = Double(i) / Double(interpSquareSize * resolution)
            let x2 = precalcStepSquared[i]
            let x3 = precalcStepCubed[i]
            
            for j in 0..<interpSquareSize * resolution {
                let y1 : Double = Double(interpSquareSize * resolution - j - 1) / Double(interpSquareSize * resolution)
                let y2 = precalcStepSquared[interpSquareSize * resolution - j - 1]
                let y3 = precalcStepCubed[interpSquareSize * resolution - j - 1]
                var interpValue = a[0][0] + a[0][1] * y1 + a[0][2] * y2 + a[0][3] * y3
                interpValue += (a[1][0] + a[1][1] * y1 + a[1][2] * y2 + a[1][3] * y3) * x1
                interpValue += (a[2][0] + a[2][1] * y1 + a[2][2] * y2 + a[2][3] * y3) * x2
                interpValue += (a[3][0] + a[3][1] * y1 + a[3][2] * y2 + a[3][3] * y3) * x3
                //print("interpValue=", interpValue)
//                minZ = Float.minimum(minZ, interpValue)
//                maxZ = Float.maximum(maxZ, interpValue)
                //bicubicInterpDataArray[x + i][y + step - j - 1] = WeightedDataPoint(value: interpValue, samplesTaken: 0)
                // Working before swap
//                bicubicInterpDataArray[x * interpSquareSize + step - 1 - j][y * interpSquareSize + step - i - 1] = WeightedDataPoint(value: interpValue, samplesTaken: 0)
                bicubicInterpDataArray[y * interpSquareSize * resolution + j][x * interpSquareSize * resolution + i] = WeightedDataPoint(value: interpValue, samplesTaken: 0)
            }
        }
//        
//        
    }
    
    

    // Run through the data and set color values based on the z value of each square compared to the min/max
    // Note: Converts data array to 1D for the sake of creating the image
    public func createHeatMapImageFromDataArray(dataArray : [[DataPoint?]], showSquares: Bool = true) -> UIImage {
        let xCount = dataArray[0].count
        let yCount = dataArray.count
        //print("xCount=", xCount, "yCount=", yCount)
        
        var pixels: [PixelData] = Array(repeating: PixelData(a: 255, r: 0, g: 0, b: 0), count: xCount * yCount)
        
        let zDiff = abs(abs(maxZ) - abs(minZ))
        
        //print(zDiff)
        
        for y in 0..<yCount {
                for x in 0..<xCount {
                    //var z = heatMapDataArray[x][y].value
                    let oneDIndex = x + y * xCount
                    
                    // White pixels centimeter locations
                    if showSquares && ((x % (10 * resolution) == 0 && y % (10 * resolution) == 0)) {
                        pixels[oneDIndex] = PixelData(a: 255, r: 255, g: 255, b: 255)
                    } else if let weightedPoint = dataArray[y][x] {
                        let z = weightedPoint.value
                        //print("z is", z)
                        //print("minZ is", minZ)
                        //print("zDiff is", zDiff)
                        var ratio = 255 - Int(round(255 * (abs(abs(z) - abs(minZ))) / zDiff))
                        //print("ratio is", ratio)
                        if ratio < 0 {
                            ratio = 0
                        }
                        if ratio > 255 {
                            ratio = 255
                        }
                        //print("ratio=", ratio)
                        let daColor = mPlasmaColormap[ratio]
                            pixels[oneDIndex] = PixelData(a: 255, r: daColor.r, g: daColor.g, b: daColor.b)
                    }
                    

                }

        }
        
        return generateImageFromPixels(pixelData: pixels, width: xCount, height: yCount)
    }
    

    
    public func generateUiImageMap(measurementData: [Float], width: Int, height: Int) -> UIImage {
        var pixels: [PixelData] = Array(repeating: PixelData(a: 255, r: 255, g: 0, b: 0), count: width * height)
        for y in 0..<height {
                for x in 0..<width {
                    let z = measurementData[x + y * width]
                    let ratio = Int(round(255 * (z - 0.005) / 0.008))
                    //print(ratio)
                    let daColor = mPlasmaColormap[ratio]
                        pixels[x + y * width] = PixelData(a: 255, r: daColor.r, g: daColor.g, b: daColor.b)
                }
        }
        return generateImageFromPixels(pixelData: pixels, width: width, height: height)
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

public protocol DataPoint {
    var value: Double { get set }
}

public struct WeightedDataPoint : DataPoint {
    public var value: Double
    public var samplesTaken: Int
}

public struct InterpolatedDataPoint : DataPoint {
    public var value: Double
    public var distance: Double // Distance = space between 2 interpolated points, probably in pixels
}

public struct PixelData {
    var a: UInt8
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

// Note: This function should only be called for pixels that have a value + an empty pixel on their right
//public func interpolateSquareFromPoint(xCoord: Int, yCoord: Int) {
//    let diagonalNeighbor = findNearestDiagonalNeighbor(xCoord: xCoord, yCoord: yCoord)
//    print("Found it at x=", diagonalNeighbor.x, " y=", diagonalNeighbor.y)
//    let horizontalNeighbor = heatMapDataArray[xCoord][diagonalNeighbor.y]
////        if horizontalNeighbor == nil {
////            print("no horizontal neighbor")
////        } else {
////            print("yes horizontal neighbor")
////        }
////        let verticalNeighbor = heatMapDataArray[diagonalNeighbor.x][yCoord]
////        if verticalNeighbor == nil {
////            print("no vertical neighbor")
////        } else {
////            print("yes vertical neighbor")
////        }
//    // TODO: Interpolate the neighbors if they don't exist
//
//    let x1 = Float(xCoord)
//    let x2 = Float(diagonalNeighbor.x)
//    let y1 = Float(yCoord)
//    let y2 = Float(diagonalNeighbor.y)
//    let q11 = heatMapDataArray[xCoord][yCoord]!.value
//    let q21 = heatMapDataArray[diagonalNeighbor.x][yCoord]!.value
//    let q12 = heatMapDataArray[xCoord][diagonalNeighbor.y]!.value
//    let q22 = heatMapDataArray[diagonalNeighbor.x][diagonalNeighbor.y]!.value
//    let denominator: Float = ((x2-x1)*(y2-y1))
//
//    for intX in xCoord...diagonalNeighbor.x {
//        for intY in yCoord...diagonalNeighbor.y {
//            let somePoint = heatMapDataArray[intX][intY]
//            if somePoint == nil {
//                let x = Float(intX)
//                let y = Float(intY)
//
//                let interpValue = (q11*(x2-x)*(y2-y)+q21*(x-x1)*(y2-y)+q12*(x2-x)*(y-y1)+q22*(x-x1)*(y-y1)) / denominator
//                //print("adding point to x=", x, "y=", y, "z=", interpValue)
//                let interpPoint = WeightedDataPoint(value: interpValue, samplesTaken: 0)
//                heatMapDataArray[intX][intY] = interpPoint
//            }
//        }
//    }
//}

// Look down and to the right of a given pixel to find the closest pixel that has a value
//public func findNearestDiagonalNeighbor(xCoord: Int, yCoord: Int) -> (x: Int, y: Int) {
//    //var range = 3
//    //var nearestNeighbor : SensorData? = nil
//    print("looking at neighbors for x=", xCoord, " y=", yCoord)
//
//    for range in 1...25 {
//        // Check the vertical column
//        for j in 1...range {
//            //print("checking at x=", xCoord + range, "y=", yCoord + j)
//            //print("checking at x=", xCoord + j, "y=", yCoord + range)
//            if heatMapDataArray[xCoord + range][yCoord + j] != nil {
//                print("Found it 1!")
//                return (xCoord + range, yCoord + j)
//            } else if heatMapDataArray[xCoord + j][yCoord + range] != nil {
//                print("Found it 2!")
//                return (xCoord + j, yCoord + range)
//            }
//        }
//    }
//    print("Didn't find it :(")
//    return (-1, -1)
//
//}
//
//public func linearlyInterpolateData(direction: String) {
//    var xIncrement = 0
//    var yIncrement = 0
//    if direction == "horizontal" {
//        xIncrement = 1
//    } else if direction == "vertical" {
//        yIncrement = 1
//    } else if direction == "diagonal" {
//        xIncrement = 1
//        yIncrement = 1
//    } else {
//        print("Please provide a valid direction of: 'horizontal', 'vertical', or 'diagonal'")
//        return
//    }
//
//    for x in 0..<118 {
//        for y in 0..<118 {
//            let currentPoint = heatMapDataArray[x][y]
//            let neighborPoint = heatMapDataArray[x + xIncrement][y + yIncrement]
//            if currentPoint != nil && neighborPoint == nil {
//                //print("found a point at x=", x, "y=", y, "with z=", currentZ)
//                var nextNeighborDistance = -1
//                var maxDistance = 0
//                if direction == "horizontal" {
//                    maxDistance = 119 - x
//                } else if direction == "vertical" {
//                    maxDistance = 119 - y
//                } else if direction == "diagonal" {
//                    let xDistance = 119 - x
//                    let yDistance = 119 - y
//                    maxDistance = min(xDistance, yDistance)
//                }
//
//                // Search for the closest neighbor in the given direction
//                for i in 2...maxDistance {
//                    let potentialNeighbor = heatMapDataArray[x + i * xIncrement][y + i * yIncrement]
//                    if potentialNeighbor != nil {
//                        nextNeighborDistance = i
//                        break
//                    }
//                }
//
//                if nextNeighborDistance > -1 {
//                    let neighborValue = heatMapDataArray[x + nextNeighborDistance * xIncrement][y + nextNeighborDistance * yIncrement]!.value
//                    let zDifference = neighborValue - currentPoint!.value
//                    for i in 1..<nextNeighborDistance {
//                        let interpZ = currentPoint!.value + zDifference * Float(i) / Float(nextNeighborDistance)
//                        heatMapDataArray[x + i * xIncrement][y + i * yIncrement] = WeightedDataPoint(value: interpZ, samplesTaken: 0)
//                    }
//                }
//
//            }
//        }
//    }
//}
//


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
