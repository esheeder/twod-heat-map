//
//  ViewController.swift
//  twod-heat-map
//
//  Created by Eric on 2/6/23.
//

import UIKit
import LFHeatMap
import SMHeatMapView

// xmin, xmax, ymin, ymax, resolution, max gap, interp square size
let generatorDefaults = [-10, 90, -70, 10, 2, 20, 4]

class ViewController: UIViewController {
    
    @IBOutlet weak var daImage: UIImageView!
    @IBOutlet weak var daImage2: UIImageView!
    
    @IBOutlet weak var daImage3: UIImageView!
    @IBOutlet weak var daImage4: UIImageView!
    
    @IBOutlet weak var scaleImage: UIImageView!
    
    var theGenerator = HeatMapGenerator(
        generatorDefaults[0],
        generatorDefaults[1],
        generatorDefaults[2],
        generatorDefaults[3],
        generatorDefaults[4],
        generatorDefaults[5],
        generatorDefaults[6],
        true,
        true
    )
    
    var genIndex = 0
    
    var theGenerators: [HeatMapGenerator] = [
        HeatMapGenerator(-10, 90, -70, 10, 2, 4, 100, true, true)
    ]
    
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
            theGenerator.resolution = Int(sender.text ?? "1") ?? 1
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
        daImage.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.heatMapDataArray, showSquares: true)
        daImage2.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.bicubicInterpDataArray, showSquares: true)
//        daImage3.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.squareAverageDataArray, showSquares: false)
//        daImage4.image = theGenerator.createHeatMapImageFromDataArray(dataArray: theGenerator.bicubicInterpDataArray, showSquares: true)
    }
    
    public func calculateGenError(i: Int) {
        
    }
    
    override func viewDidLoad() {
//        let myX : [Double] = [0.0, 10.0, 30.0, 50.0, 70.0, 90.0, 100.0]
//        let myY : [Double] = [30.0, 130.0, 150.0, 150.0, 170.0, 220.0, 320.0]
//        let myConstrainedSpline = ConstrainedCubicSpline(xPoints: myX, yPoints: myY)
        
        super.viewDidLoad()
        
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
        
        // Read the csv file and save each row of data as a triplet
        guard let filepath = Bundle.main.path(forResource: "interpolation-swirl-in-100000-01-amplitude-phase", ofType: "csv") else {
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
        
        
        // Add real csv data
        for i in 0..<csvData.count {
            let rowData = csvData[i].components(separatedBy: ",")
//            print("rowData.count=", rowData.count)
//            print(rowData[72])
//            print(rowData[73])
            
            
            if rowData.count == 75 {
                let sensorDataPoint = SensorData(x: Double(rowData[72])! * 10.0 ?? 0, y: Double(rowData[73])! * 10.0 ?? 0, z: Double(rowData[3]) ?? 0)
                //theGenerator.processNewDataPoint(dataPoint: sensorDataPoint)

            }
        }
        
        let gauss1 = Gaussian(xCenter: 60.0, yCenter: -15.0, amplitude: 80, sigmaX: 10, sigmaY: 10, theta: 0)
        let gauss2 = Gaussian(xCenter: 35.0, yCenter: -30.0, amplitude: 100, sigmaX: 10, sigmaY: 20, theta: Double.pi / 6.0)
        
        

        // Subsampled gaussian
        guard let filepath2 = Bundle.main.path(forResource: "ericswirldata2x", ofType: "csv") else {
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


        for i in 0..<csvData2.count {
            let rowData = csvData2[i].components(separatedBy: ",")
            if rowData.count == 3 {
                let x = Double(rowData[0])!
                let y = Double(rowData[1])!
                let z = 0 - gauss1.getVal(x, y) - gauss2.getVal(x, y)
                let sensorDataPoint = SensorData(x: x, y:  y, z: z)
                theGenerator.processNewDataPoint(dataPoint: sensorDataPoint)
            }
        }
        
        // Full Gaussian
//        for x in stride(from: -10, to: 90, by: 0.5) {
//            for y in stride(from: -70, to: 10, by: 0.5) {
//                let z = 0 - gauss1.getVal(Double(x), Double(y)) - gauss2.getVal(Double(x), Double(y))
//                let point = SensorData(x: Double(x), y: Double(y), z: z)
//                theGenerator.processNewDataPoint(dataPoint: point)
//            }
//        }

//        for i in 0..<testData.count {
//            theGenerator.processNewDataPoint(dataPoint: testData[i])
//        }
        
        print("points set # is", theGenerator.pointsSet)
        

        
        theGenerator.processData()
        setImages()
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
