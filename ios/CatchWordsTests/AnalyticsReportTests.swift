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

    /// 2026-11-13: the points, the funnel's worst step and the rows' 14 days are read when the server sends them, and
    /// an older answer without them still decodes.
    func test_readsTheNewFieldsAndStillReadsAnOlderAnswer() throws {
        let old = try AnalyticsReport.decode(Data(sample.utf8))
        XCTAssertNil(old.highlights)
        XCTAssertNil(old.funnel.worst)
        XCTAssertNil(old.users.first?.recent)

        var json = sample
        json = json.replacingOccurrences(of: #""funnel":{"cohort":0,"#, with: #""funnel":{"worst":2,"cohort":0,"#)
        json = json.replacingOccurrences(of: #""last_active":"2026-11-05","excluded":null}"#,
                                         with: #""last_active":"2026-11-05","excluded":null,"recent":[0,1,0,2,0,0,0,0,0,0,0,0,1,3]}"#)
        json = json.replacingOccurrences(of: #""insights":["#,
                                         with: #""highlights":[{"chart":"users","code":"users_never","tone":"bad","values":{"n":2}}],"insights":["#)
        let r = try AnalyticsReport.decode(Data(json.utf8))
        XCTAssertEqual(r.funnel.worst, 2)
        XCTAssertEqual(r.user("a")?.recent?.count, 14)
        XCTAssertEqual(r.highlights?.first?.code, "users_never")
    }

    func test_languagesShowByNameAndLevelsAsTOCFL() {
        XCTAssertEqual(AnalyticsText.language("es"), "Español")
        XCTAssertEqual(AnalyticsText.language("vi"), "Tiếng Việt")
        XCTAssertNil(AnalyticsText.language(nil))
        XCTAssertEqual(AnalyticsText.levelNumber("TOCFL-5"), "5")
        XCTAssertEqual(AnalyticsText.level(now: "TOCFL-3", goal: nil), "TOCFL 3")
        XCTAssertNil(AnalyticsText.level(now: nil, goal: nil))
        XCTAssertNotNil(AnalyticsText.level(now: "TOCFL-3", goal: "TOCFL-5"))
    }

    /// The person's page (server `getAdminUserDetail`): numbers only — areas, categories, the hours grid, the app's
    /// records — decode, and keys the page does not use are ignored.
    func test_decodesThePersonsPage() throws {
        let json = #"""
        {"profile":{"id":"u1","display_name":"Lucía","avatar_url":null,"created_at":"2026-09-25T02:00:00+00:00",
          "ui_language":"es","target_language":"zh-TW","level_goal":"TOCFL-5","current_level":"TOCFL-3",
          "review_daily_limit":20,"plan":"free","onboarded":true},
         "provider":"google","lastActive":"2026-11-13T05:00:00Z","status":"active","dayNumber":50,
         "daily":[{"day":"2026-11-12","catches":2,"reviews":5,"correct":4,"opens":3,"minutes":7.5,"aiCalls":1,"aiUsd":0.001},
                  {"day":"2026-11-13","catches":0,"reviews":0,"correct":0,"opens":0,"minutes":0,"aiCalls":0,"aiUsd":0}],
         "weekly":[{"from":"2026-11-03","to":"2026-11-09","reviews":10,"correct":8,"accuracy":80,"responseSec":2.1}],
         "memory":{"levels":[1,2,3,4,5,6],"schedule":{"overdue":1,"byDay":[]}},
         "catches":{"total":86,"first":null,"last":null,"last30":21,"byDay":[["2026-11-12",2]],"topPlaces":[["台北市 大安區",34]],
           "captureTypes":{"photo":86},"cutouts":80,"again":4},
         "streak":{"current":6,"best":9},
         "review":{"total180":120,"last30":40,"correctPct":78,"responseMsMedian":2100,"cards":86,"dueNow":3,"matured":20,"activeDays30":12},
         "usage":{"sessions":{"sessions":30,"medianMin":4.5,"totalMin":140},"openDays":31},
         "areas":[{"name":"台北市 大安區","n":34,"morning":10,"day":14,"night":10}],
         "categories":[{"key":"drink","n":12},{"key":"food","n":9}],
         "heat":[[0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0],[0],[0],[0],[0],[0],[0]],
         "app":{"device":{"appVersion":"1.0.7 (44)","device":"iphone","os":"26.1","lang":"es","at":"2026-11-13T05:00:00Z"},
           "tutorial":{"parts":["camera","home"],"lastStep":"home_added","lastAt":"2026-09-25T03:00:00Z","ended":1},
           "screens30":[{"key":"home","n":12}],"features30":[{"key":"lasso","n":2}],"lastScreens":[{"key":"review","n":5}]},
         "trouble":{"aiCalls30":40,"aiFailures30":2,"aiUsd30":0.12,"failures30":0,"reports30":1},
         "compare":[],"compareBase":30}
        """#
        let d = try AdminUserDetail.decode(Data(json.utf8))
        XCTAssertEqual(d.profile?.uiLanguage, "es")
        XCTAssertEqual(d.profile?.reviewDailyLimit, 20)
        XCTAssertEqual(d.daily?.first?.activity, 7)
        XCTAssertEqual(d.areas?.first?.night, 10)
        XCTAssertEqual(d.app?.device?.appVersion, "1.0.7 (44)")
        XCTAssertEqual(d.app?.tutorial?.parts, ["camera", "home"])
        XCTAssertEqual(d.trouble?.reports30, 1)
        XCTAssertEqual(AdminHourGrid.blocks(d.heat ?? [])[0], [0, 0, 3, 0, 0, 0, 0, 2])
        XCTAssertEqual(AdminUserDetailView.categoryRows(d.categories ?? []).first?.1, 12)
    }

    func test_calendarPutsMondayFirst() {
        // 2026-11-13 is a Friday: four empty cells before it in its week.
        let cols = AdminActivityCalendar.columns([AdminDayValue(day: "2026-11-13", value: 3)])
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].count, 7)
        XCTAssertNil(cols[0][3] ?? nil)
        XCTAssertEqual(cols[0][4] ?? nil, 3)
    }

    func test_eventNamesAreSnakeCase() {
        XCTAssertEqual(AppEvents.snake("tapCamera"), "tap_camera")
        XCTAssertEqual(AppEvents.snake("homeAdded"), "home_added")
        XCTAssertEqual(AppEvents.snake("complete"), "complete")
    }
}
