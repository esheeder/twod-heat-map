//
//  ViewController.swift
//  twod-heat-map
//
//  Created by Eric on 2/6/23.
//

import UIKit
import LFHeatMap
import SMHeatMapView
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
let magnifyingFactor: Int = 1

// If pixels are more than this distance away (in millimeters), don't do linear interpolation between them.
// Mostly just for images. Can set to something like 100 to make it not do anything but probably don't need to change it
let maxInterpGap: Double = 30.0

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
let wavelengthParams = [
    //"gauss": ["min": nil, "max": nil, "csvIndex": 2],
    //"trueGauss": ["min": nil, "max": nil, "csvIndex": nil]
    "690amp": ["min": nil, "max": nil, "csvIndex": 3],
//    "750amp": ["min": nil, "max": nil, "csvIndex": 3+12],
//    "808amp": ["min": nil, "max": nil, "csvIndex": 3+24],
//    "850amp": ["min": nil, "max": nil, "csvIndex": 3+36],
//    "940amp": ["min": nil, "max": nil, "csvIndex": 3+48],
//    "980amp": ["min": nil, "max": nil, "csvIndex": 3+60],
//    "690phase": ["min": 3.7, "max": 4.3, "csvIndex": 8],
//    "750phase": ["min": 3.8, "max": 4.5, "csvIndex": 8+12],
//    "808phase": ["min": 4.6, "max": 5.2, "csvIndex": 8+24],
//    "850phase": ["min": 4.4, "max": 4.9, "csvIndex": 8+36],
//    "940phase": ["min": 3.7, "max": 4.2, "csvIndex": 8+48],
//    "980phase": ["min": 4.8, "max": 5.2, "csvIndex": 8+60],
]

class ViewController: UIViewController {
    
    @IBOutlet weak var daImage: UIImageView!
    @IBOutlet weak var daImage2: UIImageView!
    
    @IBOutlet weak var daImage3: UIImageView!
    @IBOutlet weak var daImage4: UIImageView!
    
    @IBOutlet weak var scaleImage: UIImageView!
    
//    var theGenerator = HeatMapGenerator(
//        minX: generatorDefaults[0],
//        maxX: generatorDefaults[1],
//        minY: generatorDefaults[2],
//        maxY: generatorDefaults[3],
//        resolution: generatorDefaults[4],
//        interpSquareSizes: squareSizes,
//        dangerGap: maxInterpGap,
//        zCsvIndex: 3,
//        zFloor: nil,
//        zCeil: nil
//    )

    
    @IBOutlet weak var xminTextField: UITextField!
    @IBOutlet weak var xmaxTextField: UITextField!
    @IBOutlet weak var yminTextField: UITextField!
    @IBOutlet weak var ymaxTextField: UITextField!
    @IBOutlet weak var resolutionTextField: UITextField!
    @IBOutlet weak var interpolationTextField: UITextField!
    
    @IBOutlet weak var constrainedCubeToggle: UISwitch!
    @IBOutlet weak var exponentialWeightedToggle: UISwitch!
    

    @IBAction func textFieldChanged(_ sender: UITextField) {
//        print("sender=", sender.accessibilityLabel)
//        print("sender.text=", sender.text)
//        switch sender.accessibilityLabel {
//        case "resolution":
//            theGenerator.resolution = Int(sender.text ?? "4") ?? 4
//        case "interpolation":
//            theGenerator.interpSquareSize = Int(sender.text ?? "20") ?? 10
//        case "xmin":
//            theGenerator.graphMinX = (Int(sender.text ?? "-1")!)
//        case "xmax":
//            theGenerator.graphMaxX = (Int(sender.text ?? "11")!)
//        case "ymin":
//            theGenerator.graphMinY = (Int(sender.text ?? "-1")!)
//        case "ymax":
//            theGenerator.graphMaxY = (Int(sender.text ?? "11")!)
//        case .none:
//            break
//        case .some(_):
//            break
//        }
//        theGenerator.regeneratePlots()
        //setImages()
    }
    
    @IBAction func toggleToggled(_ sender: Any) {
        
    }
    

    @IBAction func buttonPressed(_ sender: Any) {
//        genIndex += 1
//        if genIndex > theGenerators.count - 1 {
//            genIndex = 0
//        }
//        daImage2.image = theGenerators[genIndex].createHeatMapImageFromDataArray(dataArray: theGenerator.bicubicInterpDataArray)
    }
    
    func setImages(arr1: [[DataPoint?]], arr2: [[DataPoint?]]) {
//        daImage.image = theGenerator.createHeatMapImageFromDataArray(dataArray: arr1, showSquares: true)
//        daImage2.image = theGenerator.createHeatMapImageFromDataArray(dataArray: arr2, showSquares: true)
//        daImage3.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareAverageDataArray, showSquares: false)
//        daImage4.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.bicubicInterpDataArray, showSquares: true)
    }
    
    


    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        daImage.layer.magnificationFilter = CALayerContentsFilter.nearest
        daImage.layer.shouldRasterize = true // Maybe don't need this?
        daImage2.layer.magnificationFilter = CALayerContentsFilter.nearest
        daImage2.layer.shouldRasterize = true
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
        let bounds = getXAndYBoundsFromCsvFile(filename: fileName, xIndex: xCoordIndex, yIndex: yCoordIndex)
        
        if bounds == nil {
            print("Couldn't figure out bounds :(")
            return
        }
        
        // Set the bounds to round up/down to nearest centimeter and multiply by 10 to convert to mm
        let graphBounds = [
            "xMin": 10 * Int(round(bounds!.xMin - 1)),
            "xMax": 10 * Int(round(bounds!.xMax + 1)),
            "yMin": 10 * Int(round(bounds!.yMin - 1)),
            "yMax": 10 * Int(round(bounds!.yMax + 1)),
        ]

        
        var daGenerators: [String: HeatMapGenerator] = [:]
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
        for key in Array(wavelengthParams.keys) {
            let params = wavelengthParams[key]!
            let myGenerator = HeatMapGenerator(
//                minX: -10,
//                maxX: 90,
//                minY: -70,
//                maxY: 10,
                minX: graphBounds["xMin"]!,
                maxX: graphBounds["xMax"]!,
                minY: graphBounds["yMin"]!,
                maxY: graphBounds["yMax"]!,
                resolution: interpResolution,
                interpSquareSizes: squareSizes,
                dangerGap: maxInterpGap,
                zCsvIndex: params["csvIndex"]! as! Int,
                zFloor: params["min"] as? Double,
                zCeil: params["max"] as? Double
            )
            daGenerators[key] = myGenerator
            let daGen = daGenerators[key]!
        }
        
        // Process CSV file and store the proper z values in each HeatMapGenerator
        processCsvFile(filename: fileName, xIndex: xCoordIndex, yIndex: yCoordIndex, daGenerators: daGenerators, gaussians: nil)
        //processTicTacToe(generator: daGenerators["gauss"]!, gaussians: daGausses)
        
        //processTrueGauss(generator: trueGenerator, gaussians: daGausses)
        //trueGenerator.printColumnData(dataArray: trueGenerator.heatMapDataArray, xInMm: 50.0)
        
        // For each HeatMapGenerator, process the data, save the images, and clear out our arrays to save memory
        for key in Array(daGenerators.keys) {
            let daGen = daGenerators[key]!
            //print(key)
            Task {
                await daGen.processData(doInterp: doInterp)
            }
            

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
        
        //theGenerator.processData()
        
        // Post Process options
        //setImages(arr1: theGenerator.unconstrainedVerticalSpline, arr2: theGenerator.verticalSplineInterpolatedDataArray)
        //saveImages(folder: "/Users/eric/Documents/nearwave/twod-heat-map/Images/breast/" + filename + "/850/")
        
        
        
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
        
        let rawDataImage = daGen.createHeatMapImageFromDataArray(dataArray: daGen.heatMapDataArray, showSquares: true, magFactor: magnifyingFactor)
        
        var images: [String: UIImage] = [
            //"0_trueImage": trueGenerator.createHeatMapImageFromDataArray(dataArray: trueGenerator.heatMapDataArray),
            "0a_rawData": rawDataImage,
            
            // Unconstrained + constrained splines
            "1a1_unconstrainedHorizontal": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedHorizontal, showSquares: true, magFactor: magnifyingFactor),
            "1a2_constrainedHorizontalSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedHorizontal, magFactor: magnifyingFactor),
            "1b1_unconstrainedVerticalSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedVertical, showSquares: true, magFactor: magnifyingFactor),
            "1b2_constrainedVerticalSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedVertical, magFactor: magnifyingFactor),
            "1c1_unconstrainedDownrightSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedDownright, showSquares: true, magFactor: magnifyingFactor),
            "1c2_constrainedDownrightSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedDownright, magFactor: magnifyingFactor),
            "1d1_unconstrainedDownleftSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.unconstrainedDownleft, showSquares: true, magFactor: magnifyingFactor),
            "1d2_constrainedDownleftSpline": daGen.createHeatMapImageFromDataArray(dataArray: daGen.constrainedDownleft, magFactor: magnifyingFactor),
            
            // Weighted averages of linear, constrained, unconstrained
            //"2a1_linearWeightedLinearAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.linearWeightLinearInterpolatedDataArray),
            //"2a2_linearWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.linearWeightSplineInterpoaltedDataArray),
            
            //"2b1_squareWeightedLinearAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.squareWeightLinearInterpolatedDataArray),
            //"2b2_squareWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.splineInterpolatedDataArray),
            
            //"2c1_cubeWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.cubicWeightSplineInterpolatedDataArray),
            "2c2_cubeWeightedSplineAvg": daGen.createHeatMapImageFromDataArray(dataArray: daGen.thirdOrderWeightedUnconstrained, showSquares: true, magFactor: magnifyingFactor),
            
            //
            "9a1_horizontalLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.horizontalLinear, magFactor: magnifyingFactor),
            "9a2_verticalLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.verticalLinear, magFactor: magnifyingFactor),
            "9a3_downRightLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.downrightDiagonalLinear, magFactor: magnifyingFactor),
            "9a4_downLeftLinear": daGen.createHeatMapImageFromDataArray(dataArray: daGen.downleftDiagonalLinear, magFactor: magnifyingFactor),
            //"9b1_linearWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.linearWeightLinearInterpolatedDataArray),
            //"9b2_squareWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareWeightLinearInterpolatedDataArray),
            //"9b3_cubeWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.cubicWeightLinearInterpolatedDataArray),
        ]
        
        
        // Square averages and bicubic interps of them
        for i in 0..<daGen.squareAverageSizes.count {
            // Square avg
            let size = daGen.squareAverageSizes[i]
            let squareFileName = "3" + String(Character(UnicodeScalar(i + 97)!)) + "_" + String(size) + "mmSquareAverage"
            //print(squareFileName)
            let squareArray = daGen.squareAverageSizeToArray[size]!
            let squareImage = daGen.createHeatMapImageFromDataArray(dataArray: squareArray, showSquares: true, magFactor: magnifyingFactor)
            images[squareFileName] = squareImage

            // Bicub
            let bicubFileName = "4" + String(Character(UnicodeScalar(i + 97)!)) + "_" + String(size) + "mmBicubicInterpolation"
            let bicubArray = daGen.bicubInterpSizeToArray[size]!
            let bicubImage = daGen.createHeatMapImageFromDataArray(dataArray: bicubArray, showSquares: true, magFactor: magnifyingFactor)
            images[bicubFileName] = bicubImage
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
        images[rawImageName] = daGen.createHeatMapImageFromDataArray(dataArray: daGen.heatMapDataArray, showSquares: true, magFactor: magnifyingFactor)
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
            images[rawImageName] = daGen.createHeatMapImageFromDataArray(dataArray: daGen.heatMapDataArray)
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

let testData : [SensorData] = [
    SensorData(x: -6.0, y: 0.0, z: 250),
    SensorData(x: -6.0, y: 2.0, z: 250),
    SensorData(x: -6.0, y: 4.0, z: 250),
    SensorData(x: -6.0, y: 6.0, z: 250),
    SensorData(x: -6.0, y: 8.0, z: 250),
    SensorData(x: -6.0, y: 10.0, z: 250),
    
    SensorData(x: -4.0, y: 0.0, z: 230),
    SensorData(x: -4.0, y: 2.0, z: 170),
    SensorData(x: -4.0, y: 4.0, z: 30),
    SensorData(x: -4.0, y: 6.0, z: 80),
    SensorData(x: -4.0, y: 8.0, z: 250),
    SensorData(x: -4.0, y: 10.0, z: 250),
    
    SensorData(x: -2.0, y: 0.0, z: 40),
    SensorData(x: -2.0, y: 2.0, z: 80),
    SensorData(x: -2.0, y: 4.0, z: 120),
    SensorData(x: -2.0, y: 6.0, z: 200),
    SensorData(x: -2.0, y: 8.0, z: 250),
    SensorData(x: -2.0, y: 10.0, z: 250),
    
    SensorData(x: 0.0, y: 0.0, z: 50),
    SensorData(x: 0.0, y: 2.0, z: 190),
    SensorData(x: 0.0, y: 4.0, z: 130),
    SensorData(x: 0.0, y: 6.0, z: 60),
    SensorData(x: 0.0, y: 8.0, z: 250),
    SensorData(x: 0.0, y: 10.0, z: 250),
    
    SensorData(x: 2.0, y: 0.0, z: 250),
    SensorData(x: 2.0, y: 2.0, z: 250),
    SensorData(x: 2.0, y: 4.0, z: 250),
    SensorData(x: 2.0, y: 6.0, z: 250),
    SensorData(x: 2.0, y: 8.0, z: 250),
    SensorData(x: 2.0, y: 10.0, z: 250),
    
    SensorData(x: 4.0, y: 0.0, z: 250),
    SensorData(x: 4.0, y: 2.0, z: 250),
    SensorData(x: 4.0, y: 4.0, z: 250),
    SensorData(x: 4.0, y: 6.0, z: 250),
    SensorData(x: 4.0, y: 8.0, z: 250),
    SensorData(x: 4.0, y: 10.0, z: 250)
]

public struct SensorData {
    var x: Double
    var y: Double
    var z: Double
}

// Subsampled gaussian
//guard let filepath2 = Bundle.main.path(forResource: "eric_gauss_subsample_2x", ofType: "csv") else {
//    return
//}
//var csvAsString2 = ""
//do {
//    csvAsString2 = try String(contentsOfFile: filepath2)
//} catch {
//    print(error)
//    return
//}
//let csvData2 = csvAsString2.components(separatedBy: "\n")
//
////var swirlPoints: [Point]  = Array(repeating: Point(x: 0, y: 0), count: 792)
//
//for i in 0..<csvData2.count {
//    let rowData = csvData2[i].components(separatedBy: ",")
//    if rowData.count == 3 {
//        let x = Double(rowData[0])!
//        let y = Double(rowData[1])!
//        //swirlPoints[i] = Point(x: x, y: y)
//        //let z = 0 - gauss1.getVal(x, y) - gauss2.getVal(x, y)
//        var z: Double = 0.0
//        for gaussian in daGaussians {
//            z -= gaussian.getVal(x, y)
//        }
//        let sensorDataPoint = SensorData(x: x, y:  y, z: z)
//        //theGenerator.processNewDataPoint(dataPoint: sensorDataPoint)
//    }
//}
