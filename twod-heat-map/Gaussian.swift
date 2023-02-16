//
//  Gaussian.swift
//  twod-heat-map
//
//  Created by Eric on 2/15/23.
//

import Foundation

public class Gaussian {
    var xCenter: Double
    var yCenter: Double
    var amplitude: Double
    var a: Double
    var b: Double
    var c: Double
    
    init(xCenter: Double, yCenter: Double, amplitude: Double, sigmaX : Double, sigmaY: Double, theta: Double) {
        self.xCenter = xCenter
        self.yCenter = yCenter
        self.amplitude = amplitude
        self.a = pow(cos(theta), 2) / (2.0 * pow(sigmaX, 2)) + pow(sin(theta), 2) / (2.0 * pow(sigmaY, 2))
        self.b = sin(2.0 * theta) / (4.0 * pow(sigmaX, 2)) - sin(2 * theta) / (4.0 * pow(sigmaY, 2))
        self.c = pow(sin(theta), 2) / (2.0 * sigmaX * sigmaX) + pow(cos(theta), 2) / (2.0 * sigmaY*sigmaY)
    }
    
    public func getVal(_ x: Double, _ y: Double) -> Double {
        let xDif = x - xCenter
        let yDif = y - yCenter
        let exponent = 0.0 - (a * xDif * xDif + 2.0 * b * xDif * yDif + c * yDif * yDif)
        return amplitude * exp(exponent)
    }
}
