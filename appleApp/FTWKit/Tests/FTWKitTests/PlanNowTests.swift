import Foundation
import Testing
import FTWShared
@testable import FTWKit

@Suite(.serialized) struct PlanNowTests {
    static let morning = PlanNow(status: "off_plan", why: "less_solar", batteryW: -1231, plannedBatteryW: 2595,
                                 pvW: -1392, plannedPVW: -3814, loadW: 1230, plannedLoadW: 1219, evW: 0, plannedEVW: 0)

    @Test func saysWhatHappensBesideThePlan() throws {
        try AppWords.$language.withValue(.en) {
            let w = try #require(Self.morning.words)
            #expect(w.now == "Discharging 1.2 kW")
            #expect(w.nowLine == "Now: discharging 1.2 kW")
            #expect(w.plan == "The plan said: charge 2.6 kW")
            #expect(w.why == "The sun gives 1.4 kW; the forecast said 3.8 kW.")
            #expect(w.then == "The battery covers the home, so you buy less.")
            #expect(w.sentence == "Discharging 1.2 kW. The plan said: charge 2.6 kW. The sun gives 1.4 kW; the forecast said 3.8 kW.")
            #expect(w.shorter.last == "Discharging 1.2 kW, not as planned.")
        }
    }

    @Test func saysItInSwedish() throws {
        try AppWords.$language.withValue(.sv) {
            let w = try #require(Self.morning.words)
            #expect(w.nowLine == "Nu: laddar ur 1,2 kW")
            #expect(w.plan == "Planen sa: ladda 2,6 kW")
            #expect(w.why == "Solen ger 1,4 kW, prognosen sa 3,8 kW.")
            #expect(w.then == "Batteriet täcker huset, så du köper mindre.")
        }
    }

    @Test func staysQuietOnPlan() {
        var p = Self.morning
        p.status = "as_planned"
        #expect(p.words == nil)
    }

    @Test func readsTheBoxAndAnOldBox() {
        let doc: JSON = ["plan_now": ["status": "off_plan", "why": "more_home", "battery_w": 500, "planned_battery_w": 2000,
                                      "load_w": 2500, "planned_load_w": 1000, "settles_at_ms": 5000]]
        let p = PlanNow(status: doc)
        #expect(p?.why == "more_home" && p?.settlesAtMs == 5000)
        #expect(PlanNow(status: ["plan_now": .null]) == nil)
        #expect(PlanNow(status: ["grid_w": 1]) == nil)
    }

    @Test func wordsEveryCause() throws {
        try AppWords.$language.withValue(.en) {
            var p = Self.morning
            p.batteryW = 800
            #expect(p.words?.then == "The battery charges with what is left over.")
            p.batteryW = 20
            #expect(p.words?.now == "Idle")
            #expect(p.words?.then == "Nothing is left over to charge with.")
            p = Self.morning
            p.plannedBatteryW = 0
            #expect(p.words?.plan == "The plan said: rest")
            p = Self.morning
            p.why = "manual"
            #expect(p.words?.why == "You are holding the battery by hand.")
            #expect(p.words?.then == "")
            p.why = "device"
            p.deviceReason = "fuse_limit"
            #expect(p.words?.why == "Limited by the main fuse.")
            p.why = "other"
            #expect(p.words?.why == "FTW follows what the home and the sun do now, not the forecast.")
            p = Self.morning
            p.why = "less_home"
            p.plannedBatteryW = -3000
            p.batteryW = -1000
            #expect(p.words?.then == "The battery gives only what the home needs.")
            p = Self.morning
            p.pvW = nil
            #expect(p.words?.why == "FTW follows what the home and the sun do now, not the forecast.")
        }
    }

    @Test func aBatteryIsAsPlannedOnlyWhenTheBoxSaysSo() {
        AppWords.$language.withValue(.en) {
            var row = ControlRow(driver: "bat", kind: "battery", mode: "planner_arbitrage", status: "following", reason: "power_observed")
            row.actualW = -2200
            let zone = TimeZone(identifier: "UTC")!
            #expect(ControlFeedback.sentence(row, zone) == "Discharging 2.2 kW as FTW asked.")
            row.onPlan = true
            #expect(ControlFeedback.sentence(row, zone) == "Discharging 2.2 kW as planned.")
            row.onPlan = false
            #expect(ControlFeedback.sentence(row, zone) == "Discharging 2.2 kW as FTW asked.")
        }
    }

    @Test func asksAgainWhenItSettlesAndWhileOffPlan() {
        var p = Self.morning
        #expect(ControlCheck.planFollowUpMs(p, nowMs: 0) == ControlCheck.planRereadMs)
        p.settlesAtMs = 20_000
        #expect(ControlCheck.planFollowUpMs(p, nowMs: 0) == 21_000)
        p.settlesAtMs = 9_000_000
        #expect(ControlCheck.planFollowUpMs(p, nowMs: 0) == ControlCheck.planRereadMs + 5_000)
        p.status = "as_planned"
        p.settlesAtMs = nil
        #expect(ControlCheck.planFollowUpMs(p, nowMs: 0) == nil)
        #expect(ControlCheck.planFollowUpMs(nil, nowMs: 0) == nil)
    }
}
