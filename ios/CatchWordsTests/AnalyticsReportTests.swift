import XCTest
@testable import CatchWords

/// 設定 › 開発者 › 分析 (owner 2026-11-05): the server's answer (`analytics.ts`) decodes, and every reading the server
/// can send under a chart has a sentence (a code without one would show as the bare code). Run on its own by
/// ios-check.yml.
@MainActor
final class AnalyticsReportTests: XCTestCase {
    /// Every `code` in server/src/lib/analytics.ts `insightsFor`.
    private let codes = [
        "learners_up", "learners_down", "learners_flat", "learners_none",
        "no_signups", "first_day_catch", "small_sample",
        "funnel_empty", "funnel_no_drop", "funnel_drop",
        "cohort_wait", "cohort_week1",
        "users_at_risk", "users_never", "users_ok",
        "speed_none", "speed_ok", "speed_slow",
        "ai_backup_refused", "ai_errors", "ai_ok", "first_pick", "places_top",
        "ads_no_data", "ads_watch_rate",
    ]

    private let sample = #"""
    {"generated_at":"2026-11-05T04:00:00.000Z","today":"2026-11-05","range":7,
     "window":{"from":"2026-10-30","to":"2026-11-05","prev_from":"2026-10-23","prev_to":"2026-10-29"},
     "counted":1,"excluded":1,"app_events_since":null,
     "overview":{"learners":{"value":1,"prev":0,"users":["a"]},"new_users":{"value":0,"prev":0,"users":[]},
       "catches":{"value":2,"prev":0},"reviews":{"value":0,"prev":0},
       "first_day_catch":{"value":null,"prev":null,"n":0,"prev_n":0,"users":[]},
       "week_return":{"value":null,"prev":null,"n":0,"prev_n":0,"users":[]}},
     "daily":[{"day":"2026-11-05","learners":["a"],"catches":2,"reviews":0,"signups":[]}],
     "funnel":{"cohort":0,"steps":[{"key":"signup","users":[]}]},
     "cohorts":[{"week":"2026-11-02","size":0,"cells":[null]}],
     "users":[{"id":"a","name":"A","avatar_url":null,"created_at":"2026-09-01T01:00:00+00:00","provider":"google",
       "ui_language":"ja","level_now":null,"level_goal":"TOCFL-2","onboarded":true,"status":"active","stopped_at":null,
       "catches":2,"catches_in_range":2,"reviews":0,"reviews_in_range":0,"accuracy":null,"learning_days":1,
       "last_active":"2026-11-05","excluded":null},
      {"id":"o","name":"Owner","avatar_url":null,"created_at":"2026-06-22T01:00:00+00:00","provider":"google",
       "ui_language":"ja","level_now":null,"level_goal":null,"onboarded":true,"status":"active","stopped_at":null,
       "catches":233,"catches_in_range":3,"reviews":898,"reviews_in_range":12,"accuracy":88,"learning_days":90,
       "last_active":"2026-11-05","excluded":"admin"}],
     "quality":{"suggest_s":{"p50":2.1,"p90":4.8,"n":3,"prev_p50":null},"card_s":{"p50":null,"p90":null,"n":0},
       "first_pick":{"pct":null,"n":0},"ai_errors":{"pct":0,"n":4},"backup_refused":1,
       "ai_cost_usd":{"total":0.012,"per_learner":0.012,"unpriced":2},"failures":0,
       "places":[{"name":"台北市 大安區","n":2}]},
     "ads":{"limit_hit":0,"offered":0,"watched":0,"failed":0},
     "insights":[{"chart":"learners","code":"learners_up","tone":"good","values":{"now":1,"prev":0,"diff":1,"days":7}},
       {"chart":"speed","code":"speed_ok","tone":"good","values":{"p50":2.1,"p90":4.8,"target":2.5,"n":3}}]}
    """#

    func test_decodesTheServersAnswer() throws {
        let r = try AnalyticsReport.decode(Data(sample.utf8))
        XCTAssertEqual(r.range, 7)
        XCTAssertEqual(r.window.prevFrom, "2026-10-23")
        XCTAssertEqual(r.overview.learners.users, ["a"])
        XCTAssertNil(r.overview.weekReturn.value)
        XCTAssertEqual(r.cohorts.first?.cells.count, 1)
        XCTAssertNil(r.cohorts.first?.cells.first ?? nil)
        XCTAssertEqual(r.users.last?.excluded, "admin")
        XCTAssertEqual(r.quality.suggestS.p90, 4.8)
        XCTAssertEqual(r.quality.aiCostUsd.unpriced, 2)
        XCTAssertEqual(r.insights(for: "speed").first?.num("target"), 2.5)
        XCTAssertEqual(r.user("a")?.name, "A")
    }

    func test_everyServerCodeHasASentence() {
        for code in codes {
            for tone in ["good", "warn", "bad", "info"] {
                let i = AnalyticsReport.Insight(chart: "x", code: code, tone: tone,
                                                values: ["n": .number(3), "pct": .number(40), "days": .number(7),
                                                         "from": .string("onboarded"), "to": .string("first_catch"),
                                                         "name": .string("台北市 大安區")])
                let text = AnalyticsText.sentence(i)
                XCTAssertNotEqual(text, code, "no sentence for \(code)")
                XCTAssertFalse(text.contains("{"), "unfilled slot in \(code): \(text)")
            }
        }
    }

    func test_funnelStepNamesAreWords() {
        for key in ["signup", "onboarded", "first_catch", "first_review", "came_back"] {
            XCTAssertNotEqual(AnalyticsText.step(key), key)
        }
    }
}
