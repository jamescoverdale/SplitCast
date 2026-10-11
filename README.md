# Splitcast: Race Predictor (iOS)

Compares your fitness now with your fitness before a past race, and predicts race times from it.
Everything is read from Apple Health and stays on the phone.

## Layout

- `Splitcast/Engine/`: the maths, no HealthKit or SwiftUI. `FitnessData` holds days and workouts
  and computes each `Metric` for a window (the 42 days before a date, date excluded).
  `Predictor` scales a benchmark time by the square root of the mean ratio of the aerobic markers
  (VO2max, hill-adjusted distance per heartbeat, power per heartbeat, critical power from the
  best 3- and 12-minute power), then Riegel to the target distance. Each marker was backtested
  against real races: hills + critical power took the average error from
  3.8% to 3.2%. With no results at all, the best mile in the last 8 weeks stands in as a rough
  benchmark (about 6% error). Riegel's
  exponent is fitted to the user's own results (`FitnessData.endurance`) when they have two
  distances within a year; the textbook 1.06 made a 5k predict a 3:19 marathon for someone whose
  marathons were 3:56 and 4:14 (fitted: 1.14, giving 3:54).
  `Insights.swift` builds the explanations on top: fitness needed for a goal, backtest accuracy,
  personal bests, "heart works X bpm harder at the same pace", chart trends, and why a spotted
  run stands out. Results from Health workouts are stored at the official race distance (a
  21.42 km Watch reading becomes a half marathon).
- `Splitcast/Health/HealthLoader.swift`: reads 5 years of Health data. Workouts saved by several
  apps are de-duplicated (Watch first); HR and power come from samples inside each workout's
  window, so Strava-saved runs work too.
- `Splitcast/Store/RaceResult.swift`: SwiftData model for results the user adds or confirms.
  Never written back to Health.
- `Splitcast/Views/`: Compare, Goal and Results tabs (Swift Charts).

## Setup

HealthKit capability and the Health usage description are already in the project. No signing
team is checked in: under Signing & Capabilities, pick your own team for the `Splitcast` and
`Splitcast WidgetsExtension` targets, and change the bundle IDs and App Group
(`group.com.jcoverdale.split-cast`, also in `Shared/WidgetSnapshot.swift`) if you don't own them.
Select your iPhone and press Run; the simulator has no Health data. Tests: Cmd+U (engine tests in
`SplitcastTests`).

## Background updates and widgets

- `App/BackgroundUpdate.swift`: HealthKit background delivery wakes the app when a workout is
  saved (immediately) and once a day (resting HR). It re-reads the last two weeks before the
  previous read (`FitnessCache.refreshStart`), merges them into the saved copy, and refreshes the
  widgets. Reads fail while the phone is locked; the next wake-up catches up. The app's Refresh
  does the same quick read; "Re-read all history" does a full one.
- `App/WidgetPublisher.swift` writes a `WidgetSnapshot` for every distance into `WidgetData`
  (`Shared/WidgetSnapshot.swift`, member of both targets) in the App Group
  `group.com.jcoverdale.split-cast`. Only finished figures are shared, no raw health data. Each
  widget picks its distance (Edit Widget), or follows the Goal tab.
- The widget extension (`Splitcast Widgets/`) shows small, medium, large and lock-screen widgets,
  including "goal within reach" and "data N days old" states.

- Goal alerts (`Engine/GoalAlerts.swift`, sent by `App/GoalAlertsRunner.swift`): local
  notifications when a prediction moves into a closer level (within 10%, 5%, 2%, goal reached).
  Each level alerts once per 30 days per distance, at most one alert a day (held-back news waits
  for a later day), never for getting less fit, and setting or changing a goal resets quietly.
  Opt-in under Results › Settings, as is turning background updates off.

## Release notes

- `PRIVACY.md` is the draft privacy policy (TestFlight external testing and the App Store need it
  at a public URL). Keep it in step with what the app reads and stores, and with `site/privacy.html`.
- `site/` is the public info site (home, how it works, help, privacy) for GitHub Pages; see
  `site/README.md`.
- App Store Connect's App Privacy answer is "Data Not Collected": nothing leaves the device apart
  from MapKit's map tile requests to Apple.
- `ITSAppUsesNonExemptEncryption = NO` is set, so uploads skip the export compliance question.

## App icon

Drawn by `tools/make_splitcast_icon.swift` (Core Graphics, no dependencies): two race bibs,
you then (orange, behind) and you now (white, in front, THEN / NOW on its strip), with light,
dark (transparent) and tinted (greyscale) variants. It also writes `AboutIcon.imageset` (app
icons can't be shown inside the app, so the About screen uses this copy). To tweak and regenerate:

```bash
swiftc -O tools/make_splitcast_icon.swift -o "$TMPDIR/make_splitcast_icon" \
  && "$TMPDIR/make_splitcast_icon" Splitcast/Assets.xcassets/AppIcon.appiconset
```

## Not done yet

- Caching daily figures in SwiftData, so launches don't re-read 5 years of Health data.
- HR at a set pace (needs per-sample speed), hill-adjusted efficiency.
- Excluding data by device or date range (only whole markers and single results for now).
