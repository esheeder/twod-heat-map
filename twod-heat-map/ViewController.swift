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

// xmin, xmax, ymin, ymax, resolution, square avg size
let generatorDefaults = [-10, 90, -70, 10, 4, 4]

class ViewController: UIViewController {
    
    @IBOutlet weak var daImage: UIImageView!
    @IBOutlet weak var daImage2: UIImageView!
    
    @IBOutlet weak var daImage3: UIImageView!
    @IBOutlet weak var daImage4: UIImageView!
    
    @IBOutlet weak var scaleImage: UIImageView!
    
    var theGenerator = HeatMapGenerator(
        minX: generatorDefaults[0],
        maxX: generatorDefaults[1],
        minY: generatorDefaults[2],
        maxY: generatorDefaults[3],
        resolution: generatorDefaults[4],
        interpSquareSize: generatorDefaults[5],
        dangerGap: 30.0,
        constrainedCubic: true,
        exponentialWeighted: true
    )
    var trueGenerator = HeatMapGenerator(
        minX: generatorDefaults[0],
        maxX: generatorDefaults[1],
        minY: generatorDefaults[2],
        maxY: generatorDefaults[3],
        resolution: generatorDefaults[4],
        interpSquareSize: generatorDefaults[5],
        dangerGap: 30.0,
        constrainedCubic: true,
        exponentialWeighted: true
    )
    
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
        switch sender.accessibilityLabel {
        case "resolution":
            theGenerator.resolution = Int(sender.text ?? "4") ?? 4
        case "interpolation":
            theGenerator.interpSquareSize = Int(sender.text ?? "20") ?? 10
        case "xmin":
            theGenerator.graphMinX = (Int(sender.text ?? "-1")!)
        case "xmax":
            theGenerator.graphMaxX = (Int(sender.text ?? "11")!)
        case "ymin":
            theGenerator.graphMinY = (Int(sender.text ?? "-1")!)
        case "ymax":
            theGenerator.graphMaxY = (Int(sender.text ?? "11")!)
        case .none:
            break
        case .some(_):
            break
        }
        theGenerator.regeneratePlots()
        setImages()
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
    
    func setImages() {
        daImage.image = trueGenerator.createHeatMapImageFromDataArray(dataArray: trueGenerator.heatMapDataArray, showSquares: true)
        //daImage2.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.bicubInterpSizeToArray[4]!, showSquares: true)
//        daImage3.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareAverageDataArray, showSquares: false)
//        daImage4.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.bicubicInterpDataArray, showSquares: true)
    }
    
    
    func saveImages(folder: String) {
        let folderDir = "/Users/eric/Documents/nearwave/twod-heat-map/Images/" + folder + "/"
        
        var images: [String: UIImage] = [
            //"0_trueImage": trueGenerator.createHeatMapImageFromDataArray(dataArray: trueGenerator.heatMapDataArray),
            "0_rawData": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.heatMapDataArray),
            "1a_unconstrainedHorizontalSpline": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.unconstrainedHorizontalSpline),
            "1a_unconstrainedVerticalSpline": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.unconstrainedVerticalSpline),
            "1b_constrainedHorizontalSpline": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.horizontalSplineInterpolatedDataArray),
            "1b_constrainedVerticalSpline": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.verticalSplineInterpolatedDataArray),
            "1b_constrainedDownrightSpline": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.downrightDiagonalSplineInterpolatedDataArray),
            "1b_constrainedDownleftSpline": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.downleftDiagonalSplineInterpolatedDataArray),
            "2a1_linearWeightedSplineAvg": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.linearWeightSplineInterpoaltedDataArray),
            "2b2_squareWeightedSplineAvg": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.splineInterpolatedDataArray),
            "2c3_cubeWeightedSplineAvg": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.cubicWeightSplineInterpolatedDataArray),
            "9a_horizontalLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.horizontalLinearInterpolatedDataArray),
            "9a_verticalLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.verticalLinearInterpolatedDataArray),
            "9a_downLeftLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.downleftDiagonalLinearInterpolatedDataArray),
            "9a_downRightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.downrightDiagonalLinearInterpolatedDataArray),
//            "9b1_linearWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.linearWeightLinearInterpolatedDataArray),
//            "9b2_squareWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareWeightLinearInterpolatedDataArray),
//            "9b3_cubeWeightLinear": theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.cubicWeightLinearInterpolatedDataArray),
        ]
        
        for i in 0..<theGenerator.squareAverageSizes.count {
            // Square avg
            let size = theGenerator.squareAverageSizes[i]
            let squareFileName = "3" + String(Character(UnicodeScalar(i + 97)!)) + "_" + String(size) + "mmSquareAverage"
            //print(squareFileName)
            let squareArray = theGenerator.squareAverageSizeToArray[size]!
            let squareImage = theGenerator.createHeatMapImageFromDataArray(dataArray: squareArray)
            images[squareFileName] = squareImage
            
            // Bicub
            let bicubFileName = "4" + String(Character(UnicodeScalar(i + 97)!)) + "_" + String(size) + "mmBicubicInterpolation"
            let bicubArray = theGenerator.bicubInterpSizeToArray[size]!
            let bicubImage = theGenerator.createHeatMapImageFromDataArray(dataArray: bicubArray)
            images[bicubFileName] = bicubImage
            //let bicubArray =
        }
        
        for key in Array(images.keys) {
            let data = images[key]!.pngData()!
            let filename = URL(fileURLWithPath: folderDir + key + ".png")
            try? data.write(to: filename)
        }
    
    }

    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // DELAUNAY STUFF
        // Read x, y, z values for subsampled swirl at resolution = 1
//        guard let filepath2 = Bundle.main.path(forResource: "eric_gauss_subsample_1x", ofType: "csv") else {
//            return
//        }
//        var csvAsString2 = ""
//        do {
//            csvAsString2 = try String(contentsOfFile: filepath2)
//        } catch {
//            print(error)
//            return
//        }
//        let csvData2 = csvAsString2.components(separatedBy: "\n")
//
//        var swirlPoints: [Point]  = Array(repeating: Point(x: 0, y: 0), count: 792)
//
//        for i in 0..<csvData2.count {
//            let rowData = csvData2[i].components(separatedBy: ",")
//            if rowData.count == 3 {
//                let x = Double(rowData[0])!
//                let y = Double(rowData[1])!
//                //swirlPoints[i] = Point(x: x, y: y)
//                let z = 0 - gauss1.getVal(x, y) - gauss2.getVal(x, y)
//                let sensorDataPoint = SensorData(x: x, y:  y, z: z)
//                theGenerator.processNewDataPoint(dataPoint: sensorDataPoint)
//            }
//        }
        
//        let testPoints = [
//            Point(x: 0.0, y: 0.0),
//            Point(x: 80.0, y: -10.0),
//            Point(x: 30.0, y: -30.0),
//            Point(x: 50.0, y: -45.0),
//            Point(x: 10.0, y: -60.0)
//        ]
//
//        let delaunayGen = DelaunayHeatMapGenerator(points: swirlPoints)
//        delaunayGen.colorAllTriangles()
//        daImage.image = delaunayGen.createImageFromPixelArray(delaunayGen.twodPixels)
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        //        let myX : [Double] = [0.0, 10.0, 30.0, 50.0, 70.0, 90.0, 100.0]
        //        let myY : [Double] = [30.0, 130.0, 150.0, 150.0, 170.0, 220.0, 320.0]
        //        let myConstrainedSpline = ConstrainedCubicSpline(xPoints: myX, yPoints: myY)
        
        xminTextField.text = String(generatorDefaults[0])
        xminTextField.accessibilityLabel = "xmin"
        xmaxTextField.text = String(generatorDefaults[1])
        xmaxTextField.accessibilityLabel = "xmax"
        yminTextField.text = String(generatorDefaults[2])
        yminTextField.accessibilityLabel = "ymin"
        ymaxTextField.text = String(generatorDefaults[3])
        ymaxTextField.accessibilityLabel = "ymax"
        resolutionTextField.text = String(generatorDefaults[4])
        resolutionTextField.accessibilityLabel = "resolution"
        interpolationTextField.text = String(generatorDefaults[5])
        interpolationTextField.accessibilityLabel = "interpolation"
        constrainedCubeToggle.setOn(true, animated: false)
        constrainedCubeToggle.accessibilityLabel = "constrained"
        exponentialWeightedToggle.setOn(true, animated: false)
        exponentialWeightedToggle.accessibilityLabel = "exponential"
        
        
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
        
        let gauss1 = Gaussian(xCenter: 60.0, yCenter: -15.0, amplitude: 80, sigmaX: 10, sigmaY: 10, theta: 0)
        let gauss2 = Gaussian(xCenter: 35.0, yCenter: -30.0, amplitude: 100, sigmaX: 10, sigmaY: 20, theta: Double.pi / 6.0)
        
        let daGaussians = [singleGauss]
        
        // Read the csv file and save each row of data as a triplet
        let filename = "interpolation-swirl-in-100000-01-amplitude-phase"
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
        for i in 0..<csvData.count {
            let rowData = csvData[i].components(separatedBy: ",")
//            print("rowData.count=", rowData.count)
//            print(rowData[72])
//            print(rowData[73])
            
            
            if rowData.count == 75 {
                let xCoord = 10.0 * Double(rowData[72])!
                let yCoord = 10.0 * Double(rowData[73])!
                // For real z values
                //let sensorDataPoint = SensorData(x: xCoord, y: yCoord, z: Double(rowData[3])!)
                // For gauss values
                var gaussZ: Double = 0.0
                for gaussian in daGaussians {
                    gaussZ -= gaussian.getVal(xCoord, yCoord)
                }
                let sensorDataPoint = SensorData(x: xCoord, y: yCoord, z: gaussZ)
                
                //theGenerator.processNewDataPoint(dataPoint: sensorDataPoint)

            }
        }
        

        
        // Subsampled gaussian
        guard let filepath2 = Bundle.main.path(forResource: "eric_gauss_subsample_2x", ofType: "csv") else {
            return
        }
        var csvAsString2 = ""
        do {
            csvAsString2 = try String(contentsOfFile: filepath2)
        } catch {
            print(error)
            return
        }
        let csvData2 = csvAsString2.components(separatedBy: "\n")

        //var swirlPoints: [Point]  = Array(repeating: Point(x: 0, y: 0), count: 792)
        
        for i in 0..<csvData2.count {
            let rowData = csvData2[i].components(separatedBy: ",")
            if rowData.count == 3 {
                let x = Double(rowData[0])!
                let y = Double(rowData[1])!
                //swirlPoints[i] = Point(x: x, y: y)
                //let z = 0 - gauss1.getVal(x, y) - gauss2.getVal(x, y)
                var z: Double = 0.0
                for gaussian in daGaussians {
                    z -= gaussian.getVal(x, y)
                }
                let sensorDataPoint = SensorData(x: x, y:  y, z: z)
                //theGenerator.processNewDataPoint(dataPoint: sensorDataPoint)
            }
        }
        
        // Tic tac toe sampling
        let step: Double = 1.0 / Double(generatorDefaults[4])
        // Vertical lines
        for x in stride(from: Double(generatorDefaults[0] + 2), to: Double(generatorDefaults[1]), by: 5) {
            for y in stride(from: Double(generatorDefaults[2]), to: Double(generatorDefaults[3]), by: step) {
                var z: Double = 0.0
                for gaussian in daGaussians {
                    z -= gaussian.getVal(Double(x), Double(y))
                }
                let point = SensorData(x: Double(x), y: Double(y), z: z)
                theGenerator.processNewDataPoint(dataPoint: point)
            }
        }
        // Horizontal
        for x in stride(from: Double(generatorDefaults[0] + 2), to: Double(generatorDefaults[1]), by: step) {
            for y in stride(from: Double(generatorDefaults[2]), to: Double(generatorDefaults[3]), by: 5) {
                var z: Double = 0.0
                for gaussian in daGaussians {
                    z -= gaussian.getVal(Double(x), Double(y))
                }
                let point = SensorData(x: Double(x), y: Double(y), z: z)
                theGenerator.processNewDataPoint(dataPoint: point)
            }
        }
        
        // Full Gaussian
        for x in stride(from: -10, to: 90, by: step) {
            for y in stride(from: -70, to: 10, by: step) {
                var z: Double = 0.0
                for gaussian in daGaussians {
                    z -= gaussian.getVal(x, y)
                }
                let point = SensorData(x: Double(x), y: Double(y), z: z)
                //trueGenerator.processNewDataPoint(dataPoint: point)
            }
        }
        
        //print("points set # is", theGenerator.pointsSet)
        

        
        theGenerator.processData()
        setImages()
        printLineData()
        //saveImages(folder: "tictactoe/1gauss")
        
        
        //print("estimated row for y=-30")
        
//        print("true row for y=-30")
//        theGenerator.printRowData(dataArray: trueGenerator.heatMapDataArray, yInMm: -30.0)
        
//        theGenerator.printColumnData(dataArray: trueGenerator.heatMapDataArray, xInMm: 50.0)
//        print("estimated colum for x=50")
//        theGenerator.printColumnData(dataArray: theGenerator.cubicWeightSplineInterpolatedDataArray, xInMm: 50.0)
        
        //printError(daGaussians: daGaussians, xMin: 20, xMax: 80, yMin: -60, yMax: 0)
    }
    
    func printLineData() {
        print("raw linear, x=50")
        theGenerator.printColumnData(dataArray: theGenerator.verticalLinearInterpolatedDataArray, xInMm: 50.0)
        print("")
        
        print("raw linear, y=-30")
        theGenerator.printRowData(dataArray: theGenerator.verticalLinearInterpolatedDataArray, yInMm: -30.0)
        print("")
        
        print("raw unconstrained, x=50")
        theGenerator.printColumnData(dataArray: theGenerator.unconstrainedVerticalSpline, xInMm: 50.0)
        print("")
        
        print("raw unconstrained, y=-30")
        theGenerator.printRowData(dataArray: theGenerator.unconstrainedHorizontalSpline, yInMm: -30.0)
        print("")
        
        print("raw constrained, x=50")
        theGenerator.printColumnData(dataArray: theGenerator.verticalSplineInterpolatedDataArray, xInMm: 50.0)
        print("")
        
        print("raw constrained, y=-30")
        theGenerator.printRowData(dataArray: theGenerator.horizontalSplineInterpolatedDataArray, yInMm: -30.0)
        print("")
        
    }
    
    func printError(daGaussians: [Gaussian], xMin: Int, xMax: Int, yMin: Int, yMax: Int) {
        print("Error for unconstrained horizontal cubic spline")
        theGenerator.calculateError(interpArray: theGenerator.unconstrainedHorizontalSpline,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for constrained horizontal cubic spline")
        theGenerator.calculateError(interpArray: theGenerator.horizontalSplineInterpolatedDataArray,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for unconstrained vertical cubic spline")
        theGenerator.calculateError(interpArray: theGenerator.unconstrainedVerticalSpline,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")

        print("Error for constrained vertical cubic spline")
        theGenerator.calculateError(interpArray: theGenerator.verticalSplineInterpolatedDataArray,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")

        print("Error for linear weighted cubic")
        theGenerator.calculateError(interpArray: theGenerator.linearWeightSplineInterpoaltedDataArray,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")

        print("Error for exponential weighted cubic")
        theGenerator.calculateError(interpArray: theGenerator.splineInterpolatedDataArray,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        //print("Error for square average")
        
        print("Error for bicubic interp 1mm")
        theGenerator.calculateError(interpArray: theGenerator.bicubInterpSizeToArray[1]!,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for bicubic interp 2mm")
        theGenerator.calculateError(interpArray: theGenerator.bicubInterpSizeToArray[2]!,
                                    gaussians: daGaussians,
                                    xMin: xMin,
                                    xMax: xMax,
                                    yMin: yMin,
                                    yMax: yMax)
        print("")
        
        print("Error for bicubic interp 4mm")
        theGenerator.calculateError(interpArray: theGenerator.bicubInterpSizeToArray[4]!,
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
