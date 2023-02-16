//
//  CubicSpline.swift
//  twod-heat-map
//
//  Created by Eric on 2/13/23.
//

import Foundation

// Read more: https://www.deriscope.com/docs/Kruger_CubicSpline.pdf
open class ConstrainedCubicSpline {
    var x : [Double] = []
    var y : [Double] = []
    var maxDistance: Double?
    
    var a : [Double] = []
    var b : [Double] = []
    var c : [Double] = []
    var d : [Double] = []
    
    var f1 : [Double] = []
    var dX : [Double] = [] // x Distance between current index and next index
    var dY : [Double] = [] // y Distance between current index and next index

    public init(xPoints x: Array<Double>, yPoints y: Array<Double>, maxDistance: Double?) {

        self.x = x
        self.y = y
        self.maxDistance = maxDistance

        let count: Int = x.count

        assert(x.count == y.count, "Number of t points should be the same as y points")

        guard count > 0 else { return }
        
        self.dX = Array<Double>(repeating: 0.0, count: count - 1)
        self.dY = Array<Double>(repeating: 0.0, count: count - 1)
        
        // Derivative function values computed for each interval
        self.f1 = Array<Double>(repeating: 0.0, count: count)
        
        // Second derivative function values, x0 when looking left and x1 when looking right
        var f2x0 = Array<Double>(repeating: 0.0, count: count)
        var f2x1 = Array<Double>(repeating: 0.0, count: count)
        
        
        // Coefficient values computed for each interval
        var a = Array<Double>(repeating: 0.0, count: count)
        var b = Array<Double>(repeating: 0.0, count: count)
        var c = Array<Double>(repeating: 0.0, count: count)
        var d = Array<Double>(repeating: 0.0, count: count)
        
        
        for i in 0..<x.count-1 {
            dX[i] = x[i+1]-x[i]
            //dY[i] = y[y+1]-y[i]
        }
        
        // Calculate first derivative for each point
        // The first derivative for the first point (aka i = 0) depends on the first derivative of the neighbor point (aka i=1), so do that one last
        for i in 1..<x.count {
            f1[i] = getFirstDerivative(i)
        }
        f1[0] = getFirstDerivative(0)

        // Calculate 2nd derivatives and cubic coefficients
        for i in 0..<count-1 {
            
            f2x0[i] = Double(-2) * (f1[i+1] + 2*f1[i]) / (x[i+1] - x[i]) + 6 * (y[i+1] - y[i]) / pow(x[i+1] - x[i], 2)
            f2x1[i] = Double(2) * ((Double(2) * f1[i+1] + f1[i])/(x[i+1] - x[i])) - 6 * (y[i+1] - y[i]) / pow(x[i+1] - x[i], 2)
            
            d[i] = (f2x1[i] - f2x0[i]) / (Double(6) * (x[i + 1] - x[i]))
            c[i] = (x[i+1] * f2x0[i] - x[i] * f2x1[i]) / (Double(2) * (x[i + 1] - x[i]))
            b[i] = (y[i+1] - y[i] - c[i]*(pow(x[i+1], 2) - pow(x[i], 2)) - d[i]*(pow(x[i+1], 3) - pow(x[i], 3))) / ((x[i + 1] - x[i]))
            a[i] = y[i] - b[i]*x[i] - c[i]*x[i]*x[i] - d[i]*x[i]*x[i]*x[i]
            
//            print("for range ", x[i], x[i+1])
//            print(f1[i], f2x0[i], f2x1[i])
//            print(a[i], b[i], c[i], d[i])
//            print("")
        }
        
        self.a = a
        self.b = b
        self.c = c
        self.d = d

    }
    
    public func interpolate(_ input: Double) -> (value: Double, distance: Double)? {

        if input > x.last! || input < x.first! {
            print("Tried to interpolate at ", input, "but our bounds are", x.first!, "to", x.last!)
            return nil
        }

        var i: Int = x.count - 1

        while i > 0 {
            if x[i] <= input {
                break
            }
            i -= 1
        }
        if self.maxDistance != nil && dX[i] > self.maxDistance! {
            return nil
        }
//        print("input=", input, "return=", a[i] + b[i] * input + c[i] * input * input + d[i] * pow(input, 3))
//        print("left bound is", x[i])
//        print("right bound is", x[i+1])
//        print("distance is", deltaX[i])
        return (a[i] + b[i] * input + c[i] * input * input + d[i] * pow(input, 3), dX[i])
    }
    
    private func getFirstDerivative(_ i: Int) -> Double {
        
        let n = self.x.count - 1
        // General case
        if i > 0 && i < n {
            // If slope to the left and right are opposite signed, set this derivative to 0
            /*
                Why this works:
                Slope to the left would look something like (y[i] - y[i-1]) / (x[i] - x[i-1])
                Slope to the right would look something like (y[i+1] - y[i]) / (x[i+1] - x[i])
                For one slope to be negative and one slop to be positive, exactly 1 or 3 of these terms will be negative
                If 0, 2, or 4 terms are negative, they will be the same sign
                So, you can just multiply the terms together. If you have 1 or 3 negative values, the overall value will be < 0
                Small little efficiency helper
             */
            if dY[i] * dX[i] * dY[i-1] * dX[i-1] < 0 {
                //print("caught a live one! i=", i)
                return 0.0
            }
            return Double(2.0) / (dX[i] / dY[i] + dX[i-1] / dY[i-1])
        }
        
        // Left edge case
        if i == 0 {
            return Double(1.5) * (y[1] - y[0]) / (x[1] - x[0]) - f1[1] / Double(2)
        }
        
        // Right edge case
        if i == n {
            return Double(1.5) * (y[n] - y[n-1]) / (x[n] - x[n-1]) - f1[n - 1] / Double(2)
        }
        
        print("Something's wrong with the G-diffuser if you made it here")
        return 0.0
        
    }
}
