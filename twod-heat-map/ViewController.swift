//
//  ViewController.swift
//  twod-heat-map
//
//  Created by Eric on 2/6/23.
//

import UIKit
import LFHeatMap
import ImageIO
import MobileCoreServices
import Foundation

// R1:      [-10, 130, -170, 10, 4, 4]
// R3:      [-10, 120, -150, 10, 4, 4]
// R5:      [-110, 10, -90, 0, 4, 4]
// R7:      [-90, 10, -100, 10, 4, 4]
// R8:      [-90, 10, -100, 10, 4, 4]
// R9:      [-90, 10, -70, 10, 4, 4]

// L0:      [-80, 60, 140, 10, 4, 4]
// L1:      [-20, 140, -140, 10, 4, 4]
// L3:      [-30, 140, -170, 10, 4, 4]

// Tum5:    [-10, 90, -40, 30, 4, 4]
// Tum5 01: [-30, 80, -35, 45, 4, 4]
// Tum5 02: [-10, 50, -20, 30, 4, 4]

// Spiral: [-10, 90, -70, 10, 4, 4]
// xmin, xmax, ymin, ymax, resolution, square avg size

// Images are saved in this folder + filename + wavelength
// Ex: /Users/eric/Documents/nearwave/twod-heat-map/Images/breast-high-res/tum5-30mm-0-amplitude-phase/<850phase, 850amp, etc>
// Note: Running this program with the same folderName and fileName will overwrite any images currently in there
// Can change folderName to get around this if you want (e.g. /Users/eric/Documents/nearwave/twod-heat-map/Images/breast-high-res-take-2/
let folderName = "/Users/eric/Documents/nearwave/twod-heat-map/Images/"
let fileName = "interpolation-swirl-in-100000-01-amplitude-phase"

// Once linear interpolation is done, do square averages of NxN millimeters and bicubic interpolations of them
let squareSizes = [3]

// Images to save in the summary folder.
// Ex: If this is [2,3] then each wavelength in the summary folder will have 3 images: the raw data plot, the 2x2 interp, and the 3x3 interp
// Note: Make sure each number in this array is also in the squareSizes array above!
let summarySizes = [3]

// Pixels per millimeter. Higher value = smaller interpolation steps = smoother image but longer processing time
// Don't make this too high or you might start getting gaps in the data plotting which makes interpolation worse
// Generally keep it around 2-4 for normal runs, 6-8 for super nice pictures (will take a while at 8)
let interpResolution: Int = 2

// Blow up image by integer factor - 1 pixel becomes NxN pixels in the final image
// For the high res pics I made for Roy, interpResolution was at 4-6 and this was at 4-6
let magnifyingFactor: Int = 2

// If pixels are more than this distance away (in millimeters), don't do linear interpolation between them.
// Mostly just for images. Can set to something like 100 to make it not do anything but probably don't need to change it
let maxInterpGap: Double = 100.0

// Skip over the first N points in the CSV file
// I've generally found that the first 3-5 can have bad data that throw off the heat map so I skip them
let pointsToSkip = 20

// Can set to false to only do data plotting and speed things up. Useful for debugging, but you probably won't need it
let doInterp = true

// Array of 12 different things we wanna plot
// Can be helpful to comment out some of them if you're trying to get high-res photos for just a few
// Can set min/max values to throw away any data points that fall outside of those values, useful for more contrast in phase plots
let xCoordIndex = 72
let yCoordIndex = 73
let wavelengthBounds = [
    "690amp": nil,
    "750amp": nil,
    "808amp": nil,
    "850amp": nil,
    "940amp": nil,
    "980amp": nil,
    "690phase": zBound(min: 3.7, max: 4.3),
    "750phase": zBound(min: 3.8, max: 4.5),
    "808phase": zBound(min: 4.6, max: 5.2),
    "850phase": zBound(min: 4.4, max: 4.9),
    "940phase": zBound(min: 3.7, max: 4.2),
    "980phase": zBound(min: 4.8, max: 5.2)
]

let csvIndices = [
    "690amp": 3,
    "750amp": 3+12,
    "808amp": 3+24,
    "850amp": 3+36,
    "940amp": 3+48,
    "980amp": 3+60,
    "690phase": 8,
    "750phase": 8+12,
    "808phase": 8+24,
    "850phase": 8+36,
    "940phase": 8+48,
    "980phase": 8+60
]

class ViewController: UIViewController {
    
    @IBOutlet weak var frontImage: UIImageView!
    @IBOutlet weak var backImage: UIImageView!
    
    @IBOutlet weak var daImage3: UIImageView!
    @IBOutlet weak var daImage4: UIImageView!
    
    @IBOutlet weak var scaleImage: UIImageView!

    
    @IBOutlet weak var xminTextField: UITextField!
    @IBOutlet weak var xmaxTextField: UITextField!
    @IBOutlet weak var yminTextField: UITextField!
    @IBOutlet weak var ymaxTextField: UITextField!
    @IBOutlet weak var resolutionTextField: UITextField!
    @IBOutlet weak var interpolationTextField: UITextField!
    
    
    @IBAction func toggleToggled(_ sender: Any) {
        print("toggle toggled")
        showRawPoints = !showRawPoints
        setLiveImage(generator: liveGenerator)
    }
    
    var showRawPoints = false
    var clickCount = 0
    let dataPoints: [SensorData] = []
    var graphBounds = [
        "xMin": 0,
        "xMax": 0,
        "yMin": 0,
        "yMax": 0,
    ]
    var daGenerators: [String: HeatMapGenerator] = [:]
    var csvData: [MultiSensorData] = []
    let dataPointsPerChunk = 2000
    var liveGenerator = LiveHeatMapGenerator()
    
    
    @IBAction func saveLinearImages(_ sender: Any) {
        let daGen = daGenerators["690amp"]!
        daGen.createLinearArrays()
        saveImages(folder: folderName + fileName + "/", key: String(dataPointsPerChunk * clickCount), daGen: daGen)
    }
    
    @IBAction func processSomePoints(_ sender: Any) {
//        var tempSingleValues: [SensorData] = []
//        for i in 0..<dataPointsPerChunk {
//            tempSingleValues.append(SensorData(x: csvData[i].x, y: csvData[i].y, z: csvData[i].values["690amp"]!))
//        }
//
//        let oldProcessPointStart = Date()
//        for j in 0..<dataPointsPerChunk {
//            let index = clickCount * dataPointsPerChunk + j
//            if index >= csvData.count {
//                break
//            }
//            daGenerators["690amp"]!.processNewDataPoint(dataPoint: tempSingleValues[index])
//        }
//        let oldProcessPointEnd = Date()
//        print("old point process", Int(oldProcessPointEnd.timeIntervalSince(oldProcessPointStart) * 1000), "ms")
//
       
        let maxIndex = clickCount * (dataPointsPerChunk + 1)
        if maxIndex < csvData.count {
            let processPointStart = Date()
            for j in 0..<dataPointsPerChunk {
                let index = clickCount * dataPointsPerChunk + j
                if index >= csvData.count {
                    break
                }
                liveGenerator.processNewDataPoint(dataPoint: csvData[index])
            }
            let processPointEnd = Date()
            //print("point process", Int(processPointEnd.timeIntervalSince(processPointStart) * 1000), "ms")
            
            liveGenerator.processData(printBenchmarks: true)
            
            let imageStart = Date()
            setLiveImage(generator: liveGenerator)
            let imageEnd = Date()
            print("image time:", Int(imageEnd.timeIntervalSince(imageStart) * 1000), "ms")
            
            print("TOTAL TIME:", Int(imageEnd.timeIntervalSince(processPointEnd) * 1000), "ms")
            
            clickCount += 1
            if clickCount % 4 == 0 {
                //self.showRawPoints = !self.showRawPoints
            }
            
            // Uncomment to have it run in "live" time
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
//                self.processSomePoints(sender)
//            }
        }


    }
    
    func setImages(arr1: [[DataPoint?]], arr2: [[DataPoint?]]) {
//        daImage.image = theGenerator.createHeatMapImageFromDataArray(dataArray: arr1, showSquares: true)
//        daImage2.image = theGenerator.createHeatMapImageFromDataArray(dataArray: arr2, showSquares: true)
//        daImage3.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareAverageDataArray, showSquares: false)
//        daImage4.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.bicubicInterpDataArray, showSquares: true)
    }
    
    func setLiveImage(generator: LiveHeatMapGenerator) {
        if showRawPoints {
            self.frontImage.isHidden = false
            self.frontImage.image = generator.createPointsPlottedOverlay()
        } else {
            self.frontImage.isHidden = true
        }
        self.frontImage.setNeedsDisplay()
        
        self.backImage.image = generator.createLiveHeatImage()
        self.backImage.setNeedsDisplay()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        liveGenerator = LiveHeatMapGenerator(
            minX: -10,
            maxX: 90,
            minY: -70,
            maxY: 10,
            resolution: interpResolution,
            interpSquareSize: 3,
            zValKey: "690amp",
            zBounds: wavelengthBounds)
        
        csvData = getCsvData(filename: fileName, xIndex: xCoordIndex, yIndex: yCoordIndex, zIndices: csvIndices)
        print("csv points read:", csvData.count)
        
        let bounds = getXAndYBoundsFromCsvFile(filename: fileName, xIndex: xCoordIndex, yIndex: yCoordIndex)
        
        if bounds == nil {
            print("Couldn't figure out bounds :(")
            return
        }
        
        // Set the bounds to round up/down to nearest centimeter and multiply by 10 to convert to mm
        graphBounds = [
            "xMin": 10 * Int(round(bounds!.xMin - 1)),
            "xMax": 10 * Int(round(bounds!.xMax + 1)),
            "yMin": 10 * Int(round(bounds!.yMin - 1)),
            "yMax": 10 * Int(round(bounds!.yMax + 1)),
        ]
        
        // Create a HeatMapGenerator for each wavelength we want
        daGenerators["690amp"] = HeatMapGenerator(
                            minX: -10,
                            maxX: 120,
                            minY: -100,
                            maxY: 10,
                            resolution: 2,
                            interpSquareSizes: [3],
                            dangerGap: maxInterpGap,
                            zCsvIndex:3,
                            zFloor: nil,
                            zCeil: nil
                        )
        for key in Array(wavelengthBounds.keys) {
            let params = wavelengthBounds[key]!
//            let myGenerator = HeatMapGenerator(
//                minX: graphBounds["xMin"]!,
//                maxX: graphBounds["xMax"]!,
//                minY: graphBounds["yMin"]!,
//                maxY: graphBounds["yMax"]!,
//                resolution: interpResolution,
//                interpSquareSizes: squareSizes,
//                dangerGap: maxInterpGap,
//                zCsvIndex: params["csvIndex"]! as! Int,
//                zFloor: params["min"] as? Double,
//                zCeil: params["max"] as? Double
//            )
            //daGenerators[key] = myGenerator
        }

//        let allT = [2.0, 6.0, 8.0, 10.0, 13.0, 18.0, 22.0, 30.0, 31, 32, 33, 34]
//        let allZ = [3.0, 8.0, 9.0, 16.0, 12.0, 7.0, 13.0, 20.0, 28, 32, 34, 35]
//
//        let oldSpliner = CubicSpline(xPoints: allT, yPoints: allZ)
//        let newSpliner = HeatMapSpline(tPoints: allT, zPoints: allZ, indexCount: 100)
//
//        let someT = [2.0, 6.0, 8.0, 10.0, 13.0, 18.0, 22.0, 30.0, 31, 32, 33]
//        let someZ = [3.0, 8.0, 9.0, 16.0, 12.0, 7.0, 13.0, 20.0, 28, 32, 34]
//
//        let partialSpliner = HeatMapSpline(tPoints: someT, zPoints: someZ, indexCount: 100, minIndexGap: 0.0)
//        
//        for i in stride(from: someT.first!, through: someT.last!, by: 1.0) {
//            if newSpliner.zCalcs[Int(i)]!.value != partialSpliner.zCalcs[Int(i)]!.value {
//                print(Int(i), oldSpliner.interpolate(i), newSpliner.zCalcs[Int(i)]!.value, partialSpliner.zCalcs[Int(i)]!.value, "diff!")
//            } else {
//                print(Int(i), oldSpliner.interpolate(i), newSpliner.zCalcs[Int(i)]!.value, partialSpliner.zCalcs[Int(i)]!.value)
//            }
//
//        }
//
//        partialSpliner.addPoints(newTs: [34.0], newZs: [35.0])
//
//        for i in stride(from: allT.first!, through: allT.last!, by: 1.0) {
//            if newSpliner.zCalcs[Int(i)]!.value != partialSpliner.zCalcs[Int(i)]!.value {
//                print(Int(i), oldSpliner.interpolate(i), newSpliner.zCalcs[Int(i)]!.value, partialSpliner.zCalcs[Int(i)]!.value, "diff!")
//            } else {
//                print(Int(i), oldSpliner.interpolate(i), newSpliner.zCalcs[Int(i)]!.value, partialSpliner.zCalcs[Int(i)]!.value)
//            }
//
//        }
        
//        for i in stride(from: allT.first!, through: allT.last!, by: 1.0) {
//            print(i, oldSpliner.interpolate(i), newSpliner.zCalcs[Int(i)]!.value)
//        }
        
        //        let myX : [Double] = [0.0, 10.0, 30.0, 50.0, 70.0, 90.0, 100.0]
        //        let myY : [Double] = [30.0, 130.0, 150.0, 150.0, 170.0, 220.0, 320.0]
        //        let myConstrainedSpline = ConstrainedCubicSpline(xPoints: myX, yPoints: myY)
        
//        xminTextField.text = String(generatorDefaults[0])
//        xminTextField.accessibilityLabel = "xmin"
//        xmaxTextField.text = String(generatorDefaults[1])
//        xmaxTextField.accessibilityLabel = "xmax"
//        yminTextField.text = String(generatorDefaults[2])
//        yminTextField.accessibilityLabel = "ymin"
//        ymaxTextField.text = String(generatorDefaults[3])
//        ymaxTextField.accessibilityLabel = "ymax"
//        resolutionTextField.text = String(generatorDefaults[4])
//        resolutionTextField.accessibilityLabel = "resolution"
//        interpolationTextField.text = String(generatorDefaults[5])
//        interpolationTextField.accessibilityLabel = "interpolation"
//        constrainedCubeToggle.setOn(true, animated: false)
//        constrainedCubeToggle.accessibilityLabel = "constrained"
//        exponentialWeightedToggle.setOn(true, animated: false)
//        exponentialWeightedToggle.accessibilityLabel = "exponential"
        
        
        // Tell apple to fuck off with their image interpolation, mine is better
        frontImage.layer.magnificationFilter = CALayerContentsFilter.nearest
        frontImage.layer.shouldRasterize = true // Maybe don't need this?
        frontImage.isOpaque = true
        frontImage.alpha = 0.5
        backImage.layer.magnificationFilter = CALayerContentsFilter.nearest
        backImage.layer.shouldRasterize = true
        daImage3.layer.magnificationFilter = CALayerContentsFilter.nearest
        daImage3.layer.shouldRasterize = true
        daImage4.layer.magnificationFilter = CALayerContentsFilter.nearest
        daImage4.layer.shouldRasterize = true
        
        let singleGauss = Gaussian(xCenter: 50.0, yCenter: -30.0, amplitude: 100, sigmaX: 10, sigmaY: 10, theta: 0)
        
        let gauss1 = Gaussian(xCenter: 60.0, yCenter: -25.0, amplitude: 80, sigmaX: 10, sigmaY: 10, theta: 0)
        let gauss2 = Gaussian(xCenter: 35.0, yCenter: -30.0, amplitude: 100, sigmaX: 10, sigmaY: 20, theta: Double.pi / 6.0)
        let daGausses = [gauss1, gauss2]
        

        //let step: Double = 1.0 / Double(generatorDefaults[4])
        // Full Gaussian
//        for x in stride(from: -10, to: 90, by: step) {
//            for y in stride(from: -70, to: 10, by: step) {
//                var z: Double = 0.0
//                for gaussian in daGaussians {
//                    z -= gaussian.getVal(x, y)
//                }
//                let point = SensorData(x: Double(x), y: Double(y), z: z)
//                trueGenerator.processNewDataPoint(dataPoint: point)
//            }
//        }
        
        //print("points set # is", theGenerator.pointsSet)

        
        //processTicTacToe(gaussians: daGaussians)
        
        //theGenerator.printRawData()
        
        //processTicTacToe(gaussians: daGaussians)
        
        // Read the CSV to get our min and max x and y values
//        let bounds = getXAndYBoundsFromCsvFile(filename: fileName, xIndex: xCoordIndex, yIndex: yCoordIndex)
//
//        if bounds == nil {
//            print("Couldn't figure out bounds :(")
//            return
//        }
//
//        // Set the bounds to round up/down to nearest centimeter and multiply by 10 to convert to mm
//        let graphBounds = [
//            "xMin": 10 * Int(round(bounds!.xMin - 1)),
//            "xMax": 10 * Int(round(bounds!.xMax + 1)),
//            "yMin": 10 * Int(round(bounds!.yMin - 1)),
//            "yMax": 10 * Int(round(bounds!.yMax + 1)),
//        ]

        
        //var daGenerators: [String: HeatMapGenerator] = [:]
//        var trueGenerator = HeatMapGenerator(
//            minX: -10,
//            maxX: 90,
//            minY: -70,
//            maxY: 10,
//            resolution: interpResolution,
//            interpSquareSizes: squareSizes,
//            dangerGap: maxInterpGap,
//            zCsvIndex: 2,
//            zFloor: nil,
//            zCeil: nil
//        )
        
        // Create a HeatMapGenerator for each wavelength we want
        for key in Array(wavelengthBounds.keys) {
            let params = wavelengthBounds[key]!
//            let myGenerator = HeatMapGenerator(
//                minX: graphBounds["xMin"]!,
//                maxX: graphBounds["xMax"]!,
//                minY: graphBounds["yMin"]!,
//                maxY: graphBounds["yMax"]!,
//                resolution: interpResolution,
//                interpSquareSizes: squareSizes,
//                dangerGap: maxInterpGap,
//                zCsvIndex: params["csvIndex"]! as! Int,
//                zFloor: params["min"] as? Double,
//                zCeil: params["max"] as? Double
//            )
            //daGenerators[key] = myGenerator
        }
        
        // Process CSV file and store the proper z values in each HeatMapGenerator
        

        //processCsvFile(filename: fileName, xIndex: xCoordIndex, yIndex: yCoordIndex, daGenerators: daGenerators, gaussians: nil)
        
        //processTicTacToe(generator: daGenerators["gauss"]!, gaussians: daGausses)
        
        //processTrueGauss(generator: trueGenerator, gaussians: daGausses)
        //trueGenerator.printColumnData(dataArray: trueGenerator.heatMapDataArray, xInMm: 50.0)
        
        // For each HeatMapGenerator, process the data, save the images, and clear out our arrays to save memory
        for key in Array(daGenerators.keys) {
            let daGen = daGenerators[key]!
            //print(key)
            //daGen.processData(doInterp: doInterp)
            

            //saveInterpsSummary(folder: "/Users/eric/Documents/nearwave/twod-heat-map/Images/breast-high-res/\(filename)/summary/", daGens: daGenerators)
            //daGen.clearArrays()
            
            //print("")
            //saveImages(folder: folderName + fileName + "/", key: key, daGen: daGen)
//            print("raw data")
//            daGen.printRawData()
//            print("")
//            print("constrained horizontal spline")
//            daGen.printColumnData(dataArray: daGen.constrainedHorizontal, xInMm: 50.0)
//            print("unconstrained horizontal spline")
//            daGen.printColumnData(dataArray: daGen.unconstrainedHorizontal, xInMm: 50.0)
//            print("")
            
            
            //printLineData(gen: daGen, subsample: true, averaged: true)
        }
        
        
        //print("\ndone!")
        
    }
    
    func getXAndYBoundsFromCsvFile(filename: String, xIndex: Int, yIndex: Int) -> (xMin: Double, xMax: Double, yMin: Double, yMax: Double)? {
        var xMin = Double.greatestFiniteMagnitude
        var xMax = 1.0 - Double.greatestFiniteMagnitude
        var yMin = Double.greatestFiniteMagnitude
        var yMax = 1.0 - Double.greatestFiniteMagnitude
        
        guard let filepath = Bundle.main.path(forResource: filename, ofType: "csv") else {
            print("Couldn't find CSV file for x/y bounds")
            return nil
        }
        var csvAsString = ""
        do {
            csvAsString = try String(contentsOfFile: filepath)
        } catch {
            print("Error reading CSV file for x/y bounds")
            print(error)
            return nil
        }
        let csvData = csvAsString.components(separatedBy: "\n")
        
        for i in pointsToSkip+1..<csvData.count-1 {
            let rowData = csvData[i].components(separatedBy: ",")
            let xCoord = Double(rowData[xIndex])!
            let yCoord = Double(rowData[yIndex])!
            xMin = Double.minimum(xCoord, xMin)
            xMax = Double.maximum(xCoord, xMax)
            yMin = Double.minimum(yCoord, yMin)
            yMax = Double.maximum(yCoord, yMax)
        }
        
        return (xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
    }
    
    func processCsvFile(filename: String, xIndex: Int, yIndex: Int, daGenerators: [String : HeatMapGenerator], gaussians: [Gaussian]?) {
        // Read the csv file and save each row of data as a triplet
        guard let filepath = Bundle.main.path(forResource: filename, ofType: "csv") else {
            return
        }
        var csvAsString = ""
        do {
            csvAsString = try String(contentsOfFile: filepath)
        } catch {
            print(error)
            return
        }
        let csvData = csvAsString.components(separatedBy: "\n")
        
        
        // Read real csv data for x/y pairs
        // Skip first few lines cause sometimes the data is mucky.
        // +1 to skip the header line always, -1 to ignore the last empty line
        for i in pointsToSkip+1..<csvData.count-1 {
            let rowData = csvData[i].components(separatedBy: ",")
            // Multiply by 10 to convert cm to mm
            let xCoord = 10.0 * Double(rowData[xIndex])!
            let yCoord = 10.0 * Double(rowData[yIndex])!
            for key in Array(daGenerators.keys) {
                let daGen = daGenerators[key]!
                var z = abs(Double(rowData[daGen.zCsvIndex])!)
                if gaussians != nil {
                    z = 0.0
                    for gauss in gaussians! {
                        z += gauss.getVal(xCoord, yCoord)
                    }
                }
                let sensorDataPoint = SensorData(x: xCoord, y: yCoord, z: z)
                daGen.processNewDataPoint(dataPoint: sensorDataPoint)
            }
        }
    }
    
    func getCsvData(filename: String, xIndex: Int, yIndex: Int, zIndices: [String: Int]) -> [MultiSensorData] {
        var data: [MultiSensorData] = []
        // Read the csv file and save each row of data as a triplet
        guard let filepath = Bundle.main.path(forResource: filename, ofType: "csv") else {
            return []
        }
        var csvAsString = ""
        do {
            csvAsString = try String(contentsOfFile: filepath)
        } catch {
            print(error)
            return []
        }
        let csvData = csvAsString.components(separatedBy: "\n")
        for i in pointsToSkip+1..<csvData.count-1 {
            let rowData = csvData[i].components(separatedBy: ",")
            // Multiply by 10 to convert cm to mm
            let xCoord = 10.0 * Double(rowData[xIndex])!
            let yCoord = 10.0 * Double(rowData[yIndex])!
            var zVals: [String : Double] = [:]
            for (wavelength, csvIndex) in zIndices {
                zVals[wavelength] = abs(Double(rowData[csvIndex])!)
            }
            let sensorDataPoint = MultiSensorData(x: xCoord, y: yCoord, values: zVals)
            data.append(sensorDataPoint)
        }
        return data
    }
    
    func processTicTacToe(generator: HeatMapGenerator, gaussians: [Gaussian]) {
        let step: Double = 1.0 / Double(generator.resolution)
        // Vertical lines
        for x in stride(from: Double(generator.graphMinX + 2), to: Double(generator.graphMaxX), by: 5) {
            for y in stride(from: Double(generator.graphMinY + 2), to: Double(generator.graphMaxY), by: step) {
                var z: Double = 0.0
                for gaussian in gaussians {
                    z += gaussian.getVal(x, y)
                }
                let point = SensorData(x: x, y: y, z: z)
                generator.processNewDataPoint(dataPoint: point)
            }
        }
        // Horizontal
        for x in stride(from: Double(generator.graphMinX + 2), to: Double(generator.graphMaxX), by: step) {
            for y in stride(from: Double(generator.graphMinY + 2), to: Double(generator.graphMaxY), by: 5) {
                var z: Double = 0.0
                for gaussian in gaussians {
                    z += gaussian.getVal(x, y)
                }
                let point = SensorData(x: x, y: y, z: z)
                generator.processNewDataPoint(dataPoint: point)
            }
        }
    }
    
    func processTrueGauss(generator: HeatMapGenerator, gaussians: [Gaussian]) {
        let step: Double = 1.0 / Double(generator.resolution)
        for x in stride(from: Double(generator.graphMinX), to: Double(generator.graphMaxX), by: step) {
            for y in stride(from: Double(generator.graphMinY), to: Double(generator.graphMaxY), by: step) {
                var z: Double = 0.0
                for gaussian in gaussians {
                    z += gaussian.getVal(x, y)
                }
                let point = SensorData(x: x, y: y, z: z)
                generator.processNewDataPoint(dataPoint: point)
            }
        }
    }
    
    func saveImages(folder: String, key: String, daGen: HeatMapGenerator) {
        // Create individual folder if doesn't exist
        let fileManager = FileManager.default
        let folderPath = folder + key + "/"
        let folderURL = URL(fileURLWithPath: folderPath)
        let folderExists = (try? folderURL.checkResourceIsReachable()) ?? false
        do {
            if !folderExists {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        } catch { print(error) }
        
        let rawDataImage = daGen.createHeatMapImageFromDataArray(dataArray: daGen.realDataValues, showSquares: true, magFactor: magnifyingFactor)
        
        var images: [String: UIImage] = [
            //"0_trueImage": trueGenerator.createHeatMapImageFromDataArray(dataArray: trueGenerator.heatMapDataArray),
            "0a_rawData": rawDataImage,
            
            // Unconstrained + constrained splines
            "1a1_unconstrainedHorizontal": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedHorizontal, showSquares: true, magFactor: magnifyingFactor),
            "1a2_unconstrainedVerticalSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedVertical, showSquares: true, magFactor: magnifyingFactor),
            "1a3_unconstrainedDownrightSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedDownright, showSquares: true, magFactor: magnifyingFactor),
            "1a4_unconstrainedDownleftSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedDownleft, showSquares: true, magFactor: magnifyingFactor),
            //"1b1_constrainedHorizontalSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedHorizontal, magFactor: magnifyingFactor),
            //"1b2_constrainedVerticalSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedVertical, magFactor: magnifyingFactor),
            //"1b3_constrainedDownrightSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedDownright, magFactor: magnifyingFactor),
            //"1b4_constrainedDownleftSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedDownleft, magFactor: magnifyingFactor),



            
            // Weighted averages of linear, constrained, unconstrained
            //"2a1_linearWeightedLinearAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.linearWeightLinearInterpolatedDataArray),
            //"2a2_linearWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.firstOrderWeightedUnconstrained),
            
            //"2b1_squareWeightedLinearAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.squareWeightLinearInterpolatedDataArray),
            //"2b2_squareWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.secondOrderWeightedUnconstrained),
            
            //"2c1_cubeWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.cubicWeightSplineInterpolatedDataArray),
            "2c2_cubeWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.splinerWeightedAvg, showSquares: true, magFactor: magnifyingFactor),
            
            "3_squareAverage": daGen.createHeatMapImageFromDataArray(dataArray: daGen.theOneSquareAverageArray, showSquares: false, magFactor: magnifyingFactor * interpResolution * daGen.interpSquareSize),
            "4_bicubAverage": daGen.createHeatMapImageFromDataArray(dataArray: daGen.theOneBicubArray, showSquares: false, magFactor: magnifyingFactor),
            //"5_liveImage": daGen.createLiveHeatImage()
            
            //
            //"9a1_horizontalLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.horizontalLinear, magFactor: magnifyingFactor),
            //"9a2_verticalLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.verticalLinear, magFactor: magnifyingFactor),
            //"9a3_downRightLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.downrightDiagonalLinear, magFactor: magnifyingFactor),
            //"9a4_downLeftLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.downleftDiagonalLinear, magFactor: magnifyingFactor),
            //"9b1_linearWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.linearWeightLinearInterpolatedDataArray),
            //"9b2_squareWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareWeightLinearInterpolatedDataArray),
            //"9b3_cubeWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.cubicWeightLinearInterpolatedDataArray),
        ]
        
        
        // Square averages and bicubic interps of them
        for i in 0..<daGen.squareAverageSizes.count {
            // Square avg
            let size = daGen.squareAverageSizes[i]
            // 97 = a, 98 = b, etc.
            let squareFileName = "3" + String(Character(UnicodeScalar(i + 97)!)) + "_" + String(size) + "mmSquareAverage"
            //print(squareFileName)
            let squareArray = daGen.squareAverageSizeToArray[size]!
            //let squareImage = daGen.createHeatMapImageFromDataArray(dataArray: squareArray, showSquares: false, magFactor: magnifyingFactor * interpResolution * size)
            //images[squareFileName] = squareImage

            // Bicub
            let bicubFileName = "4" + String(Character(UnicodeScalar(i + 97)!)) + "_" + String(size) + "mmBicubicInterpolation"
            let bicubArray = daGen.bicubInterpSizeToArray[size]!
            //let bicubImage = daGen.createHeatMapImageFromDataArray(dataArray: bicubArray, showSquares: true, magFactor: magnifyingFactor)
            //images[bicubFileName] = bicubImage
        }
        
        // Save files in local folder
        for wavelength in Array(images.keys) {
            let data = images[wavelength]!.pngData()!
            let filename = URL(fileURLWithPath: folderPath + wavelength + ".png")
            try? data.write(to: filename)
        }
        
        //saveSummaryImages(folder: folder + "summary/", key: key, daGen: daGen)
    
    }
    
    func saveSummaryImages(folder: String, key: String, daGen: HeatMapGenerator) {
        // Create folder if doesn't exist
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: folder)
        let folderExists = (try? folderURL.checkResourceIsReachable()) ?? false
        do {
            if !folderExists {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        } catch { print(error) }
        
        var images: [String: UIImage] = [:]
        
        // Add raw data image
        let rawImageName = "\(key)_a_raw.png"
        images[rawImageName] = daGen.createHeatMapImageFromDataArray(dataArray: daGen.realDataValues, showSquares: true, magFactor: magnifyingFactor)
        // Add interp images
        for size in summarySizes {
            let interpImageName = "\(key)_b_\(size)x\(size).png"
            images[interpImageName] = daGen.createHeatMapImageFromDataArray(dataArray: daGen.bicubInterpSizeToArray[size]!, showSquares: true, magFactor: magnifyingFactor)
        }
        
        for imageName in Array(images.keys) {
            let data = images[imageName]!.pngData()!
            let filename = URL(fileURLWithPath: folder + imageName)
            try? data.write(to: filename)
        }
    
    }
    
    func saveInterpsSummary(folder: String, daGens: [String : HeatMapGenerator]) {
        // Create folder if doesn't exist
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: folder)
        let folderExists = (try? folderURL.checkResourceIsReachable()) ?? false
        do {
            if !folderExists {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        } catch { print(error) }
        
        var images: [String: UIImage] = [:]
        
        var fileContents = ""
        
        for key in Array(daGens.keys).sorted() {
            let daGen = daGens[key]!
            // Add raw data image
            let rawImageName = "\(key)_a_raw.png"
            images[rawImageName] = daGen.createHeatMapImageFromDataArray(dataArray: daGen.realDataValues)
            // Add interp image
            let interpImageName = "\(key)_b_2x2.png"
            images[interpImageName] = daGen.createHeatMapImageFromDataArray(dataArray: daGen.bicubInterpSizeToArray[2]!)
            
            // Add min/max z values for text file
            fileContents += key + "\n"
            fileContents += "minZ=" + String(daGen.minZ) + "\n"
            fileContents += "maxZ=" + String(daGen.maxZ) + "\n\n"
        }
        
        for imageName in Array(images.keys) {
            let data = images[imageName]!.pngData()!
            let filename = URL(fileURLWithPath: folder + imageName)
            try? data.write(to: filename)
        }
        
        
        let zValuesPath = URL(fileURLWithPath: folder + "/zvalues.txt")
        fileManager.createFile(atPath: folder + "/zvalues.txt", contents: nil)
        
        do {
            try fileContents.write(to: zValuesPath, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
        }
    
    }
    
    func printLineData(gen: HeatMapGenerator, subsample: Bool, averaged: Bool) {
        if subsample {
            print("subsample.csv")
            gen.printRawData()
            print("")
        }
        
        if averaged {
            print("constrained averaged @ x=50")
            gen.printColumnData(dataArray: gen.thirdOrderWeightedConstrained, xInMm: 50.0)
            print("\n\n\n\n")
            
            print("constrained averaged @ y=-30")
            gen.printRowData(dataArray: gen.thirdOrderWeightedConstrained, yInMm: -30.0)
            print("\n\n\n\n")
            
            print("linear averaged @ x=50")
            gen.printColumnData(dataArray: gen.thirdOrderWeightedLinear, xInMm: 50.0)
            print("\n\n\n\n")

            print("linear averaged @ y=-30")
            gen.printRowData(dataArray: gen.thirdOrderWeightedLinear, yInMm: -30.0)
            print("\n\n\n\n")

            print("UNconstrained averaged @ x=50")
            gen.printColumnData(dataArray: gen.thirdOrderWeightedUnconstrained, xInMm: 50.0)
            print("\n\n\n\n")

            print("UNconstrained averaged @ y=-30")
            gen.printRowData(dataArray: gen.thirdOrderWeightedUnconstrained, yInMm: -30.0)
            print("\n\n\n\n")
            
            
        } else {
            print("constrained raw @ x=50")
            gen.printColumnData(dataArray: gen.constrainedVertical, xInMm: 50.0)
            print("\n\n\n\n")
            
            print("constrained raw @ y=-30")
            gen.printRowData(dataArray: gen.constrainedHorizontal, yInMm: -30.0)
            print("\n\n\n\n")
            
            print("linear raw @ x=50")
            gen.printColumnData(dataArray: gen.verticalLinear, xInMm: 50.0)
            print("\n\n\n\n")
            
            print("linear raw @ y=-30")
            gen.printRowData(dataArray: gen.horizontalLinear, yInMm: -30.0)
            print("\n\n\n\n")
            
            print("UNconstrained raw @ x=50")
            gen.printColumnData(dataArray: gen.unconstrainedVertical, xInMm: 50.0)
            print("\n\n\n\n")
            
            print("UNconstrained raw @ y=-30")
            gen.printRowData(dataArray: gen.unconstrainedHorizontal, yInMm: -30.0)
            print("\n\n\n\n")
        }
        
    }
    
    func printError(daGaussians: [Gaussian], xMin: Int, xMax: Int, yMin: Int, yMax: Int, daGen: HeatMapGenerator) {
        print("Error for unconstrained horizontal cubic spline")
        daGen.calculateError(interpArray: daGen.unconstrainedHorizontal,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for constrained horizontal cubic spline")
        daGen.calculateError(interpArray: daGen.constrainedHorizontal,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for unconstrained vertical cubic spline")
        daGen.calculateError(interpArray: daGen.unconstrainedVertical,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")

        print("Error for constrained vertical cubic spline")
        daGen.calculateError(interpArray: daGen.constrainedVertical,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")

        print("Error for linear weighted cubic")
        daGen.calculateError(interpArray: daGen.firstOrderWeightedUnconstrained,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")

        print("Error for exponential weighted cubic")
        daGen.calculateError(interpArray: daGen.secondOrderWeightedUnconstrained,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        //print("Error for square average")
        
        print("Error for bicubic interp 1mm")
        daGen.calculateError(interpArray: daGen.bicubInterpSizeToArray[1]!,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for bicubic interp 2mm")
        daGen.calculateError(interpArray: daGen.bicubInterpSizeToArray[2]!,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for bicubic interp 4mm")
        daGen.calculateError(interpArray: daGen.bicubInterpSizeToArray[4]!,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
    }
    
}

public struct SensorData {
    var x: Double
    var y: Double
    var z: Double
}
