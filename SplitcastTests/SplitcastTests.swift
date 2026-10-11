import Foundation
import Testing
@testable import Splitcast

/// Builds small, readable data sets: days and workouts counted from a fixed start date.
private struct Fixture {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    static let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC

    var days: [Day] = []
    var workouts: [Workout] = []

    static func date(_ day: Int, hour: Int = 8) -> Date {
        start.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3600)
    }

    mutating func run(day: Int, km: Double = 10, minutes: Double = 50, hr: Double? = 140, power: Double? = nil,
                      elev: Double? = nil, indoor: Bool = false, activity: Activity = .running) {
        workouts.append(Workout(id: UUID(), start: Self.date(day), minutes: minutes, activity: activity, km: km,
                                hrAvg: hr, hrMax: hr.map { $0 + 20 }, powerW: power, elevUpM: elev, indoor: indoor))
    }

    mutating func day(_ day: Int, rhr: Double? = nil, hrv: Double? = nil, vo2: Double? = nil, sleep: Double? = nil) {
        days.append(Day(date: Self.date(day, hour: 0), restingHR: rhr, hrv: hrv, vo2max: vo2, sleepMinutes: sleep))
    }

    func data(nowDay: Int) -> FitnessData {
        FitnessData(days: days, workouts: workouts, hrRest: 45, hrMax: 180, now: Self.date(nowDay, hour: 0), calendar: Self.calendar)
    }
}

private func benchmark(day: Int, km: Double = 10, time: String = "45:00") -> Benchmark {
    Benchmark(id: UUID(), name: "Race", date: Fixture.date(day), km: km, minutes: Format.parseClock(time)!)
}

struct PredictorTests {
    @Test func riegelScalesWithDistance() {
        #expect(abs(Predictor.riegel(minutes: 20, fromKm: 5, toKm: 10) - 41.70) < 0.01)
        #expect(Predictor.riegel(minutes: 45, fromKm: 10, toKm: 10) == 45)
    }

    @Test func fitterEngineScalesTimeBySquareRootOfRatio() throws {
        let b = benchmark(day: 0, time: "50:00")
        let then: [Metric: Double] = [.vo2max: 52, .distancePerBeat: 1.04, .powerPerBeat: 1.56]
        let now: [Metric: Double] = [.vo2max: 50, .distancePerBeat: 1.0, .powerPerBeat: 1.5]
        let p = try #require(Predictor.predict(b, then: then, now: now))
        #expect(abs(p.minutes - 50 * 1.04.squareRoot()) < 0.001)
        #expect(p.markers == 3)
        #expect(abs(p.fastest - p.slowest) < 0.001)
    }

    @Test func rangeUsesMostAndLeastOptimisticMarker() throws {
        let b = benchmark(day: 0, time: "40:00")
        let p = try #require(Predictor.predict(b, then: [.vo2max: 50, .distancePerBeat: 1.0], now: [.vo2max: 55, .distancePerBeat: 1.0]))
        #expect(p.fastest < p.minutes && p.minutes < p.slowest)
        #expect(abs(p.slowest - 40) < 0.001)
    }

    @Test func excludedMarkersAreIgnored() throws {
        let b = benchmark(day: 0, time: "40:00")
        let then: [Metric: Double] = [.vo2max: 60, .distancePerBeat: 1.0]
        let now: [Metric: Double] = [.vo2max: 50, .distancePerBeat: 1.0]
        let p = try #require(Predictor.predict(b, then: then, now: now, using: [.distancePerBeat]))
        #expect(p.minutes == 40)
        #expect(Predictor.predict(b, then: then, now: now, using: []) == nil)
    }

    @Test func noMarkersMeansNoPrediction() {
        #expect(Predictor.predict(benchmark(day: 0), then: [:], now: [.vo2max: 50]) == nil)
    }
}

struct FitnessDataTests {
    @Test func efficiencyNeedsThreeSteadyRuns() {
        var f = Fixture()
        f.run(day: 1)
        f.run(day: 3)
        #expect(f.data(nowDay: 10).value(.distancePerBeat, at: Fixture.date(10, hour: 0)) == nil)
        f.run(day: 5)
        let v = f.data(nowDay: 10).value(.distancePerBeat, at: Fixture.date(10, hour: 0))
        #expect(abs((v ?? 0) - 10_000 / (50 * 140)) < 0.0001)
    }

    @Test func steadyRunsSkipHardIndoorAndShortRuns() {
        var f = Fixture()
        f.run(day: 1)
        f.run(day: 2, hr: 170)
        f.run(day: 3, indoor: true)
        f.run(day: 4, km: 3, minutes: 18)
        f.run(day: 5, hr: nil)
        let steady = f.data(nowDay: 10).steadyRuns(endingAt: Fixture.date(10, hour: 0))
        #expect(steady.count == 1)
    }

    @Test func windowExcludesItsEndDay() {
        var f = Fixture()
        f.run(day: 10, km: 21)
        f.run(day: 9, km: 8)
        let data = f.data(nowDay: 20)
        #expect(data.value(.longestRun, at: Fixture.date(10, hour: 0)) == 8)
        #expect(data.value(.longestRun, at: Fixture.date(11, hour: 0)) == 21)
    }

    @Test func vo2maxAveragesThirtyDaysUpToTheLatestReading() {
        var f = Fixture()
        f.day(0, vo2: 40)
        f.day(40, vo2: 50)
        f.day(50, vo2: 52)
        let data = f.data(nowDay: 200)
        #expect(data.value(.vo2max, at: Fixture.date(60, hour: 0)) == 51)
        #expect(data.value(.vo2max, at: Fixture.date(200, hour: 0)) == nil)
    }

    @Test func missingDataIsNilNotZero() {
        var f = Fixture()
        f.run(day: 1, elev: nil)
        f.day(1, sleep: 420)
        let data = f.data(nowDay: 10)
        #expect(data.value(.climb, at: data.now) == nil)
        #expect(data.value(.sleep, at: data.now) == nil)
        #expect(data.value(.restingHR, at: data.now) == nil)
    }

    @Test func sleepNeedsSevenNightsOfThreeHours() {
        var f = Fixture()
        for d in 1...7 { f.day(d, sleep: d == 1 ? 120 : 420) }
        #expect(f.data(nowDay: 10).value(.sleep, at: Fixture.date(10, hour: 0)) == nil)
        f.day(8, sleep: 480)
        let expected: Double = (6 * 420 + 480) / 7
        #expect(f.data(nowDay: 10).value(.sleep, at: Fixture.date(10, hour: 0)) == expected)
    }

    @Test func trainingLoadBuildsAndFormDropsAfterHardDays() throws {
        var f = Fixture()
        for d in 0..<14 { f.run(day: d, hr: 160) }
        let data = f.data(nowDay: 14)
        let fitness = try #require(data.value(.fitness, at: data.now))
        let form = try #require(data.value(.form, at: data.now))
        #expect(fitness > 0)
        #expect(form < 0)
    }

    @Test func derivedHeartRatesFallBackWithoutData() {
        let data = FitnessData(days: [], workouts: [], calendar: Fixture.calendar)
        #expect(data.hrRest == 60)
        #expect(data.hrMax == 185)
    }

    @Test func backtestPredictsEveryOtherResult() {
        var f = Fixture()
        for d in stride(from: 0, through: 200, by: 2) { f.run(day: d, power: 250) }
        let data = f.data(nowDay: 210)
        let anchor = benchmark(day: 100, km: 5, time: "20:00")
        let rows = data.backtest(from: anchor, against: [anchor, benchmark(day: 150, km: 10), benchmark(day: 160, km: 42.195, time: "3:30:00")])
        #expect(rows.map(\.result.km) == [10, 42.195])
    }

    @Test func typedInResultsMatchTheirRunForTheRoute() {
        var f = Fixture()
        f.run(day: 5, km: 3, minutes: 15)
        f.run(day: 5, km: 10.1, minutes: 47)
        f.run(day: 6, km: 10, minutes: 46)
        let data = f.data(nowDay: 10)
        let match = data.matchingRun(for: benchmark(day: 5, km: 10, time: "47:12"))
        #expect(match?.km == 10.1)
        #expect(data.matchingRun(for: benchmark(day: 7, km: 10)) == nil)
        let linked = data.workouts[0]
        var withID = benchmark(day: 5, km: 10)
        withID.workoutID = linked.id
        #expect(data.matchingRun(for: withID)?.id == linked.id)
    }

    @Test func suggestionsAreTheFastestRunsAtEachDistance() {
        var f = Fixture()
        f.run(day: 1, km: 5, minutes: 25)
        f.run(day: 2, km: 5.1, minutes: 21)
        f.run(day: 3, km: 5, minutes: 30)
        f.run(day: 4, km: 7, minutes: 20)
        let fives = f.data(nowDay: 10).suggestedResults(perDistance: 2).filter { $0.distance == "5k" }
        #expect(fives.map(\.workout.minutes) == [21, 25])
    }
}

struct EnduranceTests {
    @Test func textbookValueWithoutPairs() {
        let data = Fixture().data(nowDay: 400)
        #expect(data.endurance(from: [benchmark(day: 10, km: 5, time: "20:00"), benchmark(day: 20, km: 5, time: "19:50")]) == .standard)
    }

    @Test func fitsExponentFromTwoDistances() {
        let data = Fixture().data(nowDay: 400)
        let tenK = 20 * pow(2, 1.10)
        let e = data.endurance(from: [benchmark(day: 10, km: 5, time: "20:00"),
                                      Benchmark(id: UUID(), name: "10k", date: Fixture.date(40), km: 10, minutes: tenK)])
        #expect(abs(e.exponent - 1.10) < 0.0001)
        #expect(e.pairs == 1)
    }

    @Test func ignoresPairsMoreThanAYearApart() {
        let data = Fixture().data(nowDay: 800)
        let e = data.endurance(from: [benchmark(day: 10, km: 5, time: "20:00"), benchmark(day: 500, km: 10, time: "50:00")])
        #expect(e == .standard)
    }

    @Test func clampsUnlikelyExponents() {
        let data = Fixture().data(nowDay: 400)
        let e = data.endurance(from: [benchmark(day: 10, km: 5, time: "20:00"), benchmark(day: 20, km: 42.195, time: "6:00:00")])
        #expect(e.exponent == 1.20)
    }

    @Test func longStretchesAreFlaggedAndWidened() throws {
        let b = benchmark(day: 0, km: 5, time: "20:00")
        let markers: [Metric: Double] = [.vo2max: 50]
        let up = try #require(Predictor.predict(b, then: markers, now: markers, toKm: 42.195))
        #expect(up.isLongStretch)
        #expect(up.fastest < up.minutes && up.minutes < up.slowest)
        let tenK = try #require(Predictor.predict(b, then: markers, now: markers, toKm: 10))
        #expect(!tenK.isLongStretch)

        let marathon = benchmark(day: 0, km: 42.195, time: "3:30:00")
        let down = try #require(Predictor.predict(marathon, then: markers, now: markers, toKm: 5))
        #expect(down.fastest < down.minutes && down.minutes < down.slowest)
    }

    @Test func personalExponentSlowsLongPredictions() throws {
        let b = benchmark(day: 0, km: 5, time: "20:00")
        let markers: [Metric: Double] = [.vo2max: 50]
        let textbook = try #require(Predictor.predict(b, then: markers, now: markers, toKm: 42.195))
        let personal = try #require(Predictor.predict(b, then: markers, now: markers, toKm: 42.195,
                                                      endurance: Endurance(exponent: 1.14, pairs: 5)))
        #expect(personal.minutes > textbook.minutes)
        #expect(abs(personal.minutes - 20 * pow(42.195 / 5, 1.14)) < 0.001)
    }
}

struct CacheTests {
    @Test func savedDataRoundTrips() throws {
        var f = Fixture()
        f.run(day: 1, power: 250, elev: 40)
        f.day(1, rhr: 45, hrv: 60, vo2: 52, sleep: 420)
        let url = FileManager.default.temporaryDirectory.appending(path: "splitcast-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let saved = FitnessCache(savedAt: Fixture.date(2), days: f.days, workouts: f.workouts)
        try saved.save(to: url)
        let loaded = try #require(FitnessCache.load(from: url))
        #expect(loaded.savedAt == saved.savedAt)
        #expect(loaded.workouts.map(\.id) == saved.workouts.map(\.id))
        #expect(loaded.days.first?.vo2max == 52)
        #expect(FitnessCache.load(from: url.appending(path: "missing")) == nil)
    }

    @Test func quickRefreshReplacesOnlyTheRecentWeeks() {
        var old = Fixture()
        old.run(day: 1, km: 5)
        old.run(day: 20, km: 6)
        old.day(1, rhr: 50)
        old.day(20, rhr: 49)
        let saved = FitnessCache(savedAt: Fixture.date(30), days: old.days, workouts: old.workouts)
        let since = saved.refreshStart(calendar: Fixture.calendar)
        #expect(since == Fixture.date(16, hour: 0))

        var fresh = Fixture()
        fresh.run(day: 20, km: 6.5)
        fresh.run(day: 35, km: 10)
        fresh.day(20, rhr: 48)
        let merged = saved.merged(days: fresh.days, workouts: fresh.workouts, since: since, savedAt: Fixture.date(36))
        #expect(merged.workouts.compactMap(\.km).sorted() == [5, 6.5, 10])
        #expect(merged.days.compactMap(\.restingHR).sorted() == [48, 50])
        #expect(merged.savedAt == Fixture.date(36))
    }

    @Test func dataIsStaleAfterThirtyDays() {
        let saved = Fixture.date(0)
        #expect(!FitnessCache.isStale(savedAt: saved, now: Fixture.date(30, hour: 0)))
        #expect(FitnessCache.isStale(savedAt: saved, now: Fixture.date(31)))
    }

    @Test func routesAreThinnedKeepingTheFinish() {
        let route = (0..<1001).map { Coordinate(latitude: Double($0), longitude: 0) }
        let thin = RouteLoader.thin(route, to: 150)
        #expect(thin.count <= 151)
        #expect(thin.first == route.first)
        #expect(thin.last == route.last)
        #expect(RouteLoader.thin(Array(route.prefix(10)), to: 150).count == 10)
    }
}

struct InsightsTests {
    @Test func fitnessNeededIsTheSquareOfTheTimeGap() {
        #expect(abs(Predictor.fitnessNeeded(predicted: 20.8, goal: 20) - 0.0816) < 0.0001)
        #expect(Predictor.fitnessNeeded(predicted: 19.5, goal: 20) < 0)
    }

    @Test func measuredDistancesSnapToOfficialOnes() {
        #expect(Predictor.officialDistance(near: 21.42)?.name == "Half")
        #expect(Predictor.officialDistance(near: 5.06)?.km == 5)
        #expect(Predictor.officialDistance(near: 7) == nil)
    }

    @Test func accuracyNeedsThreeResults() throws {
        let rows = [BacktestRow(result: benchmark(day: 1, time: "40:00"), predicted: 41),
                    BacktestRow(result: benchmark(day: 2, time: "40:00"), predicted: 39)]
        let two = try #require(Accuracy(rows))
        #expect(abs(two.meanPercent - 2.5) < 0.0001)
        #expect(!two.isReliable)
        #expect(try #require(Accuracy(rows + [rows[0]])).isReliable)
        #expect(Accuracy([]) == nil)
    }

    @Test func trendsCompareTheFirstAndLastThird() {
        let up = (0..<9).map { ChartPoint(x: Double($0), value: 50 + Double($0)) }
        let flat = (0..<9).map { ChartPoint(x: Double($0), value: 50 + ($0 % 2 == 0 ? 0.2 : -0.2)) }
        #expect(Trend.of(up) == .rising)
        #expect(Trend.of(up.map { ChartPoint(x: $0.x, value: 100 - $0.value) }) == .falling)
        #expect(Trend.of(flat) == .flat)
        #expect(Trend.of(Array(up.prefix(3))) == nil)
    }

    @Test func personalBestsCompareAtTheOfficialDistance() {
        let bests = Records.personalBests([benchmark(day: 1, km: 5, time: "20:30"), benchmark(day: 2, km: 5.2, time: "20:50"),
                                           benchmark(day: 3, km: 10, time: "44:00"), benchmark(day: 4, km: 7, time: "28:00")])
        #expect(bests[5]?.km == 5.2)
        #expect(bests[10]?.minutes == 44)
        #expect(bests.count == 2)
    }

    @Test func heartRateShiftIsMeasuredAtTheSamePace() throws {
        var f = Fixture()
        for (i, (pace, hr)) in [(5.0, 140.0), (5.5, 132.0), (6.0, 124.0)].enumerated() {
            f.run(day: 1 + i, km: 10, minutes: pace * 10, hr: hr)
            f.run(day: 50 + i, km: 10, minutes: (pace + 0.25) * 10, hr: hr + 5 - 4)
        }
        let data = f.data(nowDay: 60)
        let shift = try #require(data.heartRateShift(thenEnd: Fixture.date(10, hour: 0), nowEnd: data.now))
        // Now: 0.25 min/km slower at only 1 bpm more; at the same pace that's 5 bpm more.
        #expect(abs(shift - 5) < 0.001)
        #expect(data.heartRateShift(thenEnd: Fixture.date(200, hour: 0), nowEnd: data.now) == nil)
    }

    @Test func spottedRunsSayWhatTheyBeat() {
        var f = Fixture()
        f.run(day: 1, km: 5, minutes: 21)
        f.run(day: 40, km: 5, minutes: 20)
        f.run(day: 80, km: 5, minutes: 20.5)
        let data = f.data(nowDay: 90)
        let five = (km: 5.0, name: "5k")
        #expect(data.spottedReason(for: data.workouts[1], distance: five) == "your fastest 5k")
        #expect(data.spottedReason(for: data.workouts[0], distance: five) == "your fastest 5k at the time")
        #expect(data.spottedReason(for: data.workouts[2], distance: five).hasPrefix("fastest 5k since February"))
        #expect(data.isFastest(data.workouts[1], distance: five))
        #expect(!data.isFastest(data.workouts[0], distance: five))
    }
}

struct CoverageTests {
    @Test func steadyRunsSayWhyOthersDidntCount() {
        var f = Fixture()
        f.run(day: 1)
        f.run(day: 2, km: 3, minutes: 18)
        f.run(day: 3, hr: nil)
        f.run(day: 4, hr: 170)
        f.run(day: 5, indoor: true)
        let c = f.data(nowDay: 10).coverage(.distancePerBeat, endingAt: Fixture.date(10, hour: 0))
        #expect(c.summary == "1 of 3 steady runs")
        #expect(!c.isEnough)
        #expect(c.detail == "5 runs in the 6 weeks before: 1 indoor, 1 under 5 km, 1 without heart rate, 1 too hard or too easy.")
    }

    @Test func powerCoverageCountsSteadyRunsWithoutPower() {
        var f = Fixture()
        for d in 1...3 { f.run(day: d, power: d == 1 ? 250 : nil) }
        let c = f.data(nowDay: 10).coverage(.powerPerBeat, endingAt: Fixture.date(10, hour: 0))
        #expect(c.have == 1)
        #expect(c.detail?.contains("2 steady but without running power") == true)
    }

    @Test func staleVO2maxSaysWhenTheLastReadingWas() {
        var f = Fixture()
        f.day(0, vo2: 50)
        let c = f.data(nowDay: 200).coverage(.vo2max, endingAt: Fixture.date(200, hour: 0))
        #expect(c.have == 0)
        #expect(c.detail == "Last reading 7 months before.")
        #expect(f.data(nowDay: 30).coverage(.vo2max, endingAt: Fixture.date(30, hour: 0)).isEnough)
    }

    @Test func sleepCountsOnlyNightsOfThreeHours() {
        var f = Fixture()
        for d in 1...5 { f.day(d, sleep: d <= 2 ? 120 : 420) }
        let c = f.data(nowDay: 10).coverage(.sleep, endingAt: Fixture.date(10, hour: 0))
        #expect(c.summary == "3 of 7 nights of 3 h+ tracked")
        #expect(c.detail == "2 shorter nights not counted (under 3 hours).")
    }
}

struct GoalAlertTests {
    private func check(_ predicted: String, goal: String = "20:00") -> GoalAlerts.Check {
        GoalAlerts.Check(km: 5, distance: "5k", goal: Format.parseClock(goal)!, predicted: Format.parseClock(predicted)!)
    }

    @Test func levelsFollowTheGapToTheGoal() {
        #expect(GoalLevel.of(predicted: 19.9, goal: 20) == .reached)
        #expect(GoalLevel.of(predicted: 20.3, goal: 20) == .within2)
        #expect(GoalLevel.of(predicted: 20.9, goal: 20) == .within5)
        #expect(GoalLevel.of(predicted: 21.9, goal: 20) == .within10)
        #expect(GoalLevel.of(predicted: 23, goal: 20) == .far)
    }

    @Test func firstSightingAndNewGoalsDontAlert() {
        var state = GoalAlertState()
        #expect(GoalAlerts.evaluate([check("19:50")], state: &state, now: Fixture.date(0)) == nil)
        #expect(GoalAlerts.evaluate([check("19:50", goal: "19:55")], state: &state, now: Fixture.date(2)) == nil)
    }

    @Test func movingCloserAlertsOnceAndRelapsesDont() throws {
        var state = GoalAlertState()
        _ = GoalAlerts.evaluate([check("21:00")], state: &state, now: Fixture.date(0))
        let reached = try #require(GoalAlerts.evaluate([check("19:58")], state: &state, now: Fixture.date(1)))
        #expect(reached.level == .reached)
        #expect(reached.title == "Sub-20 5k is on")
        // Less fit: no alert. Fitter again within 30 days: still no alert.
        #expect(GoalAlerts.evaluate([check("20:40")], state: &state, now: Fixture.date(5)) == nil)
        #expect(GoalAlerts.evaluate([check("19:59")], state: &state, now: Fixture.date(15)) == nil)
        // After 30 days the same news can be sent again.
        _ = GoalAlerts.evaluate([check("20:40")], state: &state, now: Fixture.date(40))
        #expect(GoalAlerts.evaluate([check("19:59")], state: &state, now: Fixture.date(45))?.level == .reached)
    }

    @Test func atMostOneAlertADay() {
        var state = GoalAlertState()
        let ten = GoalAlerts.Check(km: 10, distance: "10k", goal: 42, predicted: 47)
        _ = GoalAlerts.evaluate([check("22:30"), ten], state: &state, now: Fixture.date(0))
        let first = GoalAlerts.evaluate([check("21:30"), ten], state: &state, now: Fixture.date(1))
        #expect(first?.level == .within10)
        let tenCloser = GoalAlerts.Check(km: 10, distance: "10k", goal: 42, predicted: 42.5)
        #expect(GoalAlerts.evaluate([check("21:30"), tenCloser], state: &state, now: Fixture.date(1, hour: 20)) == nil)
        // Held back, not lost: it goes out once a day has passed, then not again.
        #expect(GoalAlerts.evaluate([check("21:30"), tenCloser], state: &state, now: Fixture.date(3))?.km == 10)
        #expect(GoalAlerts.evaluate([check("21:30"), tenCloser], state: &state, now: Fixture.date(5)) == nil)
    }

    @Test func biggestNewsWinsWhenSeveralQualify() {
        var state = GoalAlertState()
        let ten = { (p: Double) in GoalAlerts.Check(km: 10, distance: "10k", goal: 42, predicted: p) }
        _ = GoalAlerts.evaluate([check("22:30"), ten(47)], state: &state, now: Fixture.date(0))
        let alert = GoalAlerts.evaluate([check("21:30"), ten(41.9)], state: &state, now: Fixture.date(1))
        #expect(alert?.km == 10)
        #expect(alert?.level == .reached)
        // The smaller 5k news follows on a later day.
        #expect(GoalAlerts.evaluate([check("21:30"), ten(41.9)], state: &state, now: Fixture.date(3))?.km == 5)
    }

    @Test func oddGoalsReadNaturally() {
        #expect(GoalAlerts.goalTitle(goal: 19.5, distance: "5k") == "your 5k goal")
        #expect(GoalAlerts.goalTitle(goal: 105, distance: "half") == "Sub-1:45 half")
        let alert = GoalAlerts.message(check("19:20", goal: "19:30"), .reached)
        #expect(alert.title == "Your 5k goal is on")
    }
}

struct EffortTests {
    private func t(_ seconds: Double) -> Date { Fixture.start.addingTimeInterval(seconds) }

    @Test func bestAverageNeedsAFullyCoveredStretch() throws {
        // 10 minutes at 250 W with a 3-minute block at 350 W in the middle, one sample every 5 s.
        let samples = stride(from: 0.0, through: 600, by: 5).map { s in (time: t(s), value: (200...379).contains(s) ? 350.0 : 250.0) }
        #expect(abs(try #require(Efforts.bestAverage(samples, over: 180)) - 350) < 3)
        #expect(Efforts.bestAverage(samples, over: 720) == nil)
    }

    @Test func fastestSegmentFindsTheQuickestMile() throws {
        // 3 m/s for 10 minutes, then 4 m/s for 10 minutes; samples every 3 s.
        let samples = stride(from: 3.0, through: 1200, by: 3).map { s in (end: t(s), metres: s <= 600 ? 9.0 : 12.0) }
        let mile = try #require(Efforts.fastest(samples, metres: 1609.344))
        #expect(abs(mile - 1609.344 / 4 / 60) < 0.05)
        #expect(Efforts.fastest(samples, metres: 100_000) == nil)
    }

    @Test func criticalPowerFromBestEfforts() throws {
        var f = Fixture()
        f.run(day: 1)
        f.workouts[0].bestPower3 = 380
        f.workouts[0].bestPower12 = 340
        let data = f.data(nowDay: 10)
        let cp = try #require(data.value(.criticalPower, at: data.now))
        let expected: Double = (12 * 340 - 3 * 380) / 9
        #expect(abs(cp - expected) < 0.001)
        #expect(data.coverage(.criticalPower, endingAt: data.now).isEnough)
    }

    @Test func climbingCountsAsExtraDistance() {
        var f = Fixture()
        f.run(day: 1, km: 10, minutes: 50, hr: 140, elev: 100)
        let data = f.data(nowDay: 10)
        #expect(abs(data.distancePerBeat(data.workouts[0]) - 10_800.0 / (50 * 140)) < 0.0001)
    }

    @Test func bestMileStandsInWithoutResults() throws {
        var f = Fixture()
        f.run(day: 1)
        f.run(day: 20)
        f.workouts[0].bestMileMinutes = 6.5
        f.workouts[1].bestMileMinutes = 6.2
        let data = f.data(nowDay: 30)
        let fallback = try #require(data.bestMileBenchmark())
        #expect(fallback.benchmark.minutes == 6.2)
        #expect(fallback.benchmark.date == Fixture.date(21, hour: 0))
        #expect(f.data(nowDay: 120).bestMileBenchmark() == nil)
    }
}

struct FormatTests {
    @Test(arguments: [("20:00", 20.0), ("1:42:12", 102.2), ("47", 47.0)])
    func parsesClockTimes(text: String, minutes: Double) {
        #expect(abs((Format.parseClock(text) ?? 0) - minutes) < 0.0001)
    }

    @Test(arguments: ["", "5:75", "abc", "1:2:3:4", "-5:00", "0:00"])
    func rejectsBadClockTimes(text: String) {
        #expect(Format.parseClock(text) == nil)
    }

    @Test func formatsClockAndPace() {
        #expect(Format.clock(47.7) == "47:42")
        #expect(Format.clock(113.8) == "1:53:48")
        #expect(Format.pace(4.77, .miles) == "7:41/mi")
        #expect(Format.pace(4.77, .kilometres) == "4:46/km")
    }
}
