//
//  HeatMapSpline.swift
//  twod-heat-map
//
//

import Foundation

open class HeatMapSpline {
    var t: [Double] = []
    var z: [Double] = []
    
    fileprivate var b: [Double] = []
    fileprivate var c: [Double] = []
    fileprivate var d: [Double] = []
    
    // Array of the computed values for every index
    var zCalcs: [InterpolatedDataPoint?]
    fileprivate var minIndexGap: Double
    var shouldUpdate: Bool = false
    
    public init(tPoints t: [Double] = [], zPoints z: [Double] = [], indexCount: Int, minIndexGap: Double = 0.0, maxInterpGap: Double = 20) {

        self.zCalcs = [InterpolatedDataPoint?](repeating: nil, count: indexCount)
        self.minIndexGap = minIndexGap

        assert(t.count == z.count, "Number of t points should be the same as z points")

        addPoints(newTs: t, newZs: z)

    }
    
    public func setPoints(newTs: [Double], newZs: [Double]) {
        if newTs.count == 0 {
            return
        }
        var tempTs: [Double] = [newTs[0]]
        var tempZs: [Double] = [newZs[0]]
        // Get rid of any points that are too close together
        for i in 1..<newTs.count {
            if newTs[i] - tempTs.last! > minIndexGap {
                tempTs.append(newTs[i])
                tempZs.append(newZs[i])
            }
        }
        self.t = tempTs
        self.z = tempZs
        self.b = [Double](repeating: 0.0, count: tempTs.count)
        self.c = [Double](repeating: 0.0, count: tempTs.count)
        self.d = [Double](repeating: 0.0, count: tempTs.count)
        computeCoefficientVals(startI: 0, endI: tempTs.count - 1)
        computeInterpVals(tempTs.first!, tempTs.last!)
    }
    
    public func addPoints(newTs: [Double], newZs: [Double]) {
        if newTs.count == 0 {
            //print("no new vals, just returning")
            return
        }
        // Case for first time adding values
        if self.t.count == 0 {
            setPoints(newTs: newTs, newZs: newZs)
            return
        }
        // Add values to t and z in smart way while sorting them and respecting the minIndexGap,
        // then maybe need to set vals to nil? Probably not since we will recalculate them
        // Will also want to figure out what our range of values to recalculate are
        var oldCounter = 0
        var newCounter = 0
        var firstInsertIndex: Int = -1
        var lastInsertIndex: Int = -1
        
        var allTs: [Double] = []
        var allZs: [Double] = []
        //var allBs: [Double] = []
        
        
        for i in 0..<(newTs.count + self.t.count) {
            // Case for only have old values left
            if newCounter == newTs.count {
                print("done with new vals, just appending olds")
                for j in oldCounter..<self.t.count {
                    if self.t[j] - allTs.last! > minIndexGap {
                        allTs.append(self.t[j])
                        allZs.append(self.z[j])
                    }
                }
                break
            }
            // Case for only have new values
            if oldCounter == self.t.count {
                print("done with old vals, just appending news")
                for j in newCounter..<newTs.count {
                    if newTs[j] - allTs.last! > minIndexGap {
                        allTs.append(newTs[j])
                        allZs.append(newZs[j])
                    }
                }
                break
            }
            
            let oldT = self.t[oldCounter]
            let newT = newTs[newCounter]
            // Case for using oldT
            if oldT < newT {
                oldCounter += 1
                if i > 0 && (oldT - allTs[i-1] <= self.minIndexGap) {
                    print("skipping over old", oldT)
                    continue
                }
                // Insert old T
                print("adding", oldT, "from old")
                allTs.append(oldT)
                allZs.append(self.z[oldCounter - 1])
                
                // TODO: Could maybe copy over old b/c/d values here?
//                if allNewInserted && lastInsertIndex + 1 < i {
//
//                }
            } else {
                newCounter += 1
                if i > 0 && (newT - allTs[i-1] <= self.minIndexGap) {
                    print("skipping over new", newT)
                    continue
                }
                // Insert new T
                print("adding", newT, "from NEW")
                allTs.append(newT)
                allZs.append(newZs[newCounter - 1])
                lastInsertIndex = i
                if firstInsertIndex == -1 {
                    firstInsertIndex = i
                }
            }
        }
        print("first inserted index is", firstInsertIndex)
        print("last inserted index is", lastInsertIndex)
        //print(allTs)
        self.t = allTs
        self.z = allZs
        self.b = [Double](repeating: 0.0, count: allTs.count)
        self.c = [Double](repeating: 0.0, count: allTs.count)
        self.d = [Double](repeating: 0.0, count: allTs.count)
        computeCoefficientVals(startI: 0, endI: allTs.count - 1)
        computeInterpVals(0.0, Double(self.zCalcs.count - 1))
    }
    
    public func computeCoefficientVals(startI: Int, endI: Int) {
        if self.t.count < 3 {
            return
        }

        let count = endI - startI + 1
        var dT = Array<Double>(repeating: 0.0, count: count)
        var dZ = Array<Double>(repeating: 0.0, count: count)
        
        var yCo = Array<Double>(repeating: 0.0, count: count)
        var lCo = Array<Double>(repeating: 0.0, count: count)
        var uCo = Array<Double>(repeating: 0.0, count: count)
        var zCo = Array<Double>(repeating: 0.0, count: count)
        var slope = Array<Double>(repeating: 0.0, count: count)

        for i in startI...endI {
            if i < t.count - 1 {
                dT[i] = t[i + 1] - t[i]
                dZ[i] = z[i + 1] - z[i]
                slope[i] = dZ[i] / dT[i]
            }
        }

        for i in startI...endI {
            if i > 0 && i < t.count - 1 {
                yCo[i] = 3 / dT[i] * (z[i + 1] - z[i]) - 3 / dT[i - 1] * (z[i] - z[i - 1])
            }
        }

        lCo[0] = 1
        uCo[0] = 0
        zCo[0] = 0

        for i in startI...endI {
            if i > 0 && i < t.count - 1 {
                let temp: Double = 2 * (t[i + 1] - t[i - 1])
                lCo[i] = temp - dT[i - 1] * uCo[i - 1]
                uCo[i] = dT[i] / lCo[i]
                zCo[i] = (yCo[i] - dT[i - 1] * zCo[i - 1]) / lCo[i]
            }
        }

        lCo[lCo.count - 1] = 1
        zCo[zCo.count - 1] = 0

        var i = endI - 1
        while i >= startI {
            self.c[i] = zCo[i] - uCo[i] * self.c[i + 1]

            let zDiff: Double = z[i + 1] - z[i]
            let temp: Double = self.c[i + 1] + 2.0 * self.c[i]

            self.b[i] = zDiff / dT[i] - dT[i] * temp / 3.0
            self.d[i] = (self.c[i + 1] - self.c[i]) / (3 * dT[i])
            i -= 1
        }
        
//        print(b)
//        print(c)
//        print(d)

        // TODO: Figure out if this is trash
        c[c.count - 1] = 0
    }
    
    public func computeInterpVals(_ startIndex: Double, _ endIndex: Double) {
        for i in stride(from: startIndex, through: endIndex, by: 1.0) {
            zCalcs[Int(i)] = interpolate(i)
            //print(i, zCalcs[Int(i)])
        }
    }
    

    public func interpolate(_ index: Double) -> InterpolatedDataPoint? {
        
        if t.count < 3 || index < t.first! || index >= t.last! {
            return nil
        }

        var i: Int = t.count - 1

        while i > 0 {
            if t[i] <= index {
                break
            }
            i -= 1
        }
        
//        if t[i+1]-t[i] > maxInterpGap {
//            return nil
//        }
        let deltaX: Double = index - t[i]
        let af: Double = b[i]
        let cf: Double = c[i]
        let df: Double = d[i]
        // TODO: Calculate distance correctly, something like t[i+1] - t[i]
        return InterpolatedDataPoint(value: z[i] + af * deltaX + cf * pow(deltaX, 2) + df * pow(deltaX, 3), distance: t[i+1]-t[i])
    }
}
