import Foundation

/// A photo's depth from `DepthModel`: `width` × `height` values, rows top-down, 1 nearest and 0 farthest.
nonisolated struct DepthMap: Sendable {
    let values: [Float]
    let width: Int
    let height: Int

    /// The map with its depths spread out, `amount` of the way (0–1) to equalized, as Equalize spreads a photo's tones:
    /// each value moves toward its rank among them all, so depths the model bunched together (a distant city, everything
    /// past a near subject) come apart into steps, while their order stays the same.
    func equalized(_ amount: Float) -> DepthMap {
        guard amount > 0, values.count > 1 else { return self }
        let order = values.indices.sorted { values[$0] < values[$1] }
        var spread = values
        let last = Float(values.count - 1)
        for (rank, index) in order.enumerated() { spread[index] += (Float(rank) / last - values[index]) * amount }
        return DepthMap(values: spread, width: width, height: height)
    }
}
