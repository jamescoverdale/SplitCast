import Foundation

/// Best efforts inside a single workout, from the Watch's samples.
nonisolated enum Efforts {
    /// Best average of `samples` over any `seconds`-long stretch, counting only stretches the
    /// samples fully cover. Samples are (time, value), any spacing.
    static func bestAverage(_ samples: [(time: Date, value: Double)], over seconds: TimeInterval) -> Double? {
        let s = samples.sorted { $0.time < $1.time }
        var best: Double?
        var start = 0
        var sum = 0.0
        for end in s.indices {
            sum += s[end].value
            while s[end].time.timeIntervalSince(s[start].time) > seconds {
                sum -= s[start].value
                start += 1
            }
            // A stretch counts once it spans (almost) the whole duration.
            if s[end].time.timeIntervalSince(s[start].time) >= seconds - 10 {
                let avg = sum / Double(end - start + 1)
                best = max(best ?? avg, avg)
            }
        }
        return best
    }

    /// Fastest time, in minutes, to cover `metres`, from distance samples (end time, metres in
    /// that sample).
    static func fastest(_ samples: [(end: Date, metres: Double)], metres: Double) -> Double? {
        let s = samples.sorted { $0.end < $1.end }
        var cumulative: [Double] = []
        var total = 0.0
        for x in s {
            total += x.metres
            cumulative.append(total)
        }
        var best: TimeInterval?
        var start = 0
        for end in s.indices {
            // Move the start up while the stretch would still be long enough without it.
            while start + 1 < end, cumulative[end] - cumulative[start + 1] >= metres { start += 1 }
            if cumulative[end] - cumulative[start] >= metres {
                let t = s[end].end.timeIntervalSince(s[start].end)
                best = min(best ?? t, t)
            }
        }
        return best.map { $0 / 60 }
    }
}
