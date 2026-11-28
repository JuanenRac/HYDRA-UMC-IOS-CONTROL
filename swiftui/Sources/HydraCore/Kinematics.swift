// HYDRA-UMC-IOS-CONTROL - the kinematics of the Parol6 arm, as the studio and the published app solve a Cartesian jog.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum Parol6 {
    public static let modelName = "Parol6 (6-DOF)"

    public static let limits: [String: (low: Double, high: Double)] = [
        "j1": (-97.40, 97.40), "j2": (-56.15, 57.30), "j3": (-114.59, 74.48),
        "j4": (-114.59, 114.59), "j5": (-120.32, 120.32), "j6": (-177.62, 177.62),
    ]

    private static let chain: [(pos: [Double], rpy: [Double], sign: Double)] = [
        ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 1.0),
        ([0.0234207210610375, 0.0, 0.1105], [-1.5707963267949, 0.0, 0.0], 1.0),
        ([0.0, -0.18, 0.0], [3.1416, 0.0, -1.5708], -1.0),
        ([0.0435, 0.0, 0.0], [1.5707963267949, 0.0, 3.14159265358979], -1.0),
        ([0.0, 0.0, -0.17635], [-1.5708, 0.0, 0.0], -1.0),
        ([0.0, 0.0, 0.0], [1.5708, 0.0, 0.0], -1.0),
    ]

    private static let zOffsetMm = 334.0
    private static let reachToleranceM = 0.002

    private typealias Matrix = [[Double]]

    private static func identity() -> Matrix { (0..<4).map { r in (0..<4).map { c in r == c ? 1.0 : 0.0 } } }

    private static func mul(_ a: Matrix, _ b: Matrix) -> Matrix {
        var out = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                var sum = 0.0
                for k in 0..<4 { sum += a[i][k] * b[k][j] }
                out[i][j] = sum
            }
        }
        return out
    }

    private static func translation(_ p: [Double]) -> Matrix {
        var m = identity()
        m[0][3] = p[0]; m[1][3] = p[1]; m[2][3] = p[2]
        return m
    }

    private static func rotX(_ a: Double) -> Matrix {
        var m = identity()
        m[1][1] = cos(a); m[1][2] = -sin(a); m[2][1] = sin(a); m[2][2] = cos(a)
        return m
    }

    private static func rotY(_ a: Double) -> Matrix {
        var m = identity()
        m[0][0] = cos(a); m[0][2] = sin(a); m[2][0] = -sin(a); m[2][2] = cos(a)
        return m
    }

    private static func rotZ(_ a: Double) -> Matrix {
        var m = identity()
        m[0][0] = cos(a); m[0][1] = -sin(a); m[1][0] = sin(a); m[1][1] = cos(a)
        return m
    }

    private static func position(_ joints: [Double]) -> [Double] {
        var m = rotX(-Double.pi / 2)
        for i in 0..<6 {
            let step = chain[i]
            let rotation = mul(mul(rotZ(step.rpy[2]), rotY(step.rpy[1])), rotX(step.rpy[0]))
            m = mul(mul(mul(m, translation(step.pos)), rotation), rotZ(step.sign * joints[i] * Double.pi / 180))
        }
        return [m[0][3], m[1][3], m[2][3]]
    }

    private static func radiusHeight(_ j2: Double, _ j3: Double) -> (Double, Double) {
        let p = position([0, j2, j3, 0, 0, 0])
        return ((p[0] * p[0] + p[2] * p[2]).squareRoot(), p[1])
    }

    private static func clamp(_ v: Double, _ name: String) -> Double {
        let limit = limits[name]!
        return min(limit.high, max(limit.low, v))
    }

    private static func solve(_ radius: Double, _ height: Double) -> (Double, Double) {
        let seeds: [(Double, Double)] = [(-30, 30), (0, 0), (30, -30), (-50, 60), (50, -60)]
        var best = (0.0, 0.0)
        var bestError = Double.infinity
        let h = 0.01
        for seed in seeds {
            var (j2, j3) = seed
            var lastError = Double.infinity
            for iteration in 0..<80 {
                let (r, y) = radiusHeight(j2, j3)
                let fr = r - radius, fy = y - height
                let error = (fr * fr + fy * fy).squareRoot()
                if error < 1e-7 { break }
                if error > lastError * 1.5 && iteration > 5 { break }
                lastError = error
                let (r2, y2) = radiusHeight(j2 + h, j3)
                let (r3, y3) = radiusHeight(j2, j3 + h)
                let a = (r2 - r) / h, b = (y2 - y) / h, c = (r3 - r) / h, d = (y3 - y) / h
                let det = a * d - c * b
                if abs(det) < 1e-9 { break }
                j2 -= min(15, max(-15, (fr * d - fy * c) / det))
                j3 -= min(15, max(-15, (fy * a - fr * b) / det))
            }
            let (r, y) = radiusHeight(j2, j3)
            let error = ((r - radius) * (r - radius) + (y - height) * (y - height)).squareRoot()
            if error < bestError {
                bestError = error
                best = (j2, j3)
            }
            if bestError < 1e-6 { break }
        }
        return (clamp(best.0, "j2"), clamp(best.1, "j3"))
    }

    public static func joints(x: Double, y: Double, z: Double, a: Double, b: Double, c: Double) -> [Double] {
        let j1 = atan2(y, x) * (180 / Double.pi)
        let (j2, j3) = solve((x * x + y * y).squareRoot() / 1000, (z + zOffsetMm) / 1000)
        return [clamp(j1, "j1"), j2, j3, clamp(a, "j4"), clamp(b, "j5"), clamp(c, "j6")]
    }

    /// nil when the pose is out of reach: clamped joints next to a position that does not match them are never sent.
    public static func jointsOrNil(x: Double, y: Double, z: Double, a: Double, b: Double, c: Double) -> [Double]? {
        let j1 = atan2(y, x) * (180 / Double.pi)
        for (name, value) in [("j1", j1), ("j4", a), ("j5", b), ("j6", c)] {
            let limit = limits[name]!
            if !(value >= limit.low && value <= limit.high) { return nil }
        }
        let found = joints(x: x, y: y, z: z, a: a, b: b, c: c)
        let (r, h) = radiusHeight(found[1], found[2])
        let dr = r - (x * x + y * y).squareRoot() / 1000
        let dh = h - (z + zOffsetMm) / 1000
        return (dr * dr + dh * dh).squareRoot() <= reachToleranceM ? found : nil
    }
}
