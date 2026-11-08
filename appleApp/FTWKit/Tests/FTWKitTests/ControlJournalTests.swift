import Foundation
import Testing
@testable import FTWDemo
@testable import FTWKit
import FTWShared

/// "What happened" in the control sheet: the box's control journal, GET
/// /api/control/journal, in the live rows' words. The vector is Core's
/// answer as api_control_journal.go serves it (srcfl/ftw
/// feat/control-journal): one morning, newest first.
@Suite struct ControlJournalTests {
    static let zone = TimeZone(identifier: "Europe/Stockholm")!
    /// 8 Nov 2026 at noon in Stockholm (CET, UTC+1).
    static let noon: Double = 1_794_135_600_000
    static func local(_ h: Int, _ m: Int, _ s: Double = 0) -> Double { noon + (Double(h - 12) * 3600 + Double(m) * 60 + s) * 1000 }

    static let vector = """
    {"since_ms": \(Int(noon - 86_400_000)), "until_ms": \(Int(noon)), "more": false, "notifications_more": false,
     "spans": [
      {"id": 9, "subject": "source:easee", "driver": "easee", "kind": "source", "status": "offline", "reason": "telemetry_stale",
       "severity": "warning", "start_ms": \(Int(local(8, 2, 30))), "end_ms": \(Int(local(8, 9, 10))), "updated_ms": \(Int(local(8, 9, 10))),
       "duration_s": 400, "samples": 80, "requested_w": null, "actual_w": null,
       "first": {"status": "offline", "consecutive_errors": 40, "last_error": "i/o timeout"}},
      {"id": 8, "subject": "ev:easee", "driver": "easee", "kind": "ev", "status": "no_contact", "reason": "telemetry_stale",
       "severity": "warning", "start_ms": \(Int(local(8, 2, 30))), "end_ms": \(Int(local(8, 9, 10))), "updated_ms": 0, "duration_s": 400,
       "samples": 80, "requested_w": null, "actual_w": null},
      {"id": 7, "subject": "slot:battery", "kind": "slot", "status": "under_delivered", "severity": "warning", "mode": "planner_arbitrage",
       "start_ms": \(Int(local(6, 15))), "end_ms": \(Int(local(6, 30))), "updated_ms": \(Int(local(6, 30))), "duration_s": 900, "samples": 1,
       "requested_w": {"min": 4200, "max": 4200, "mean": 4200, "n": 1}, "actual_w": {"min": 1260, "max": 1260, "mean": 1260, "n": 1},
       "first": {"planned_wh": 1050, "actual_wh": 315, "ratio": 0.3, "replans": 0}},
      {"id": 6, "subject": "battery:sungrow", "driver": "sungrow", "kind": "battery", "status": "not_following",
       "reason": "power_below_target", "severity": "warning", "mode": "planner_arbitrage",
       "start_ms": \(Int(local(6, 14, 5))), "end_ms": \(Int(local(6, 29, 40))), "updated_ms": \(Int(local(6, 29, 40))), "duration_s": 935,
       "samples": 187, "requested_w": {"min": 4200, "max": 4200, "mean": 4200, "n": 187},
       "actual_w": {"min": 1090, "max": 1350, "mean": 1200, "n": 187},
       "first": {"driver": "sungrow", "kind": "battery", "status": "not_following", "reason": "power_below_target", "severity": "warning",
                 "sent_w": 4200, "actual_w": 1240, "evidence": "measured"},
       "last": {"driver": "sungrow", "kind": "battery", "status": "not_following", "reason": "power_below_target", "severity": "warning",
                "sent_w": 4200, "actual_w": 1160, "evidence": "measured"}},
      {"id": 2, "subject": "battery:sungrow", "driver": "sungrow", "kind": "battery", "status": "not_controlled",
       "reason": "site_meter_stale", "severity": "warning", "start_ms": \(Int(local(5, 52, 10))), "end_ms": \(Int(local(5, 52, 13))),
       "updated_ms": 0, "duration_s": 3, "samples": 1, "requested_w": null, "actual_w": null},
      {"id": 1, "subject": "site:dispatch", "kind": "dispatch", "status": "blocked", "reason": "site_meter_stale", "severity": "warning",
       "start_ms": \(Int(local(5, 52, 10))), "end_ms": \(Int(local(5, 52, 13))), "updated_ms": 0, "duration_s": 3, "samples": 1,
       "requested_w": null, "actual_w": null}
     ],
     "notifications": [
      {"id": 31, "ts_ms": \(Int(local(6, 24, 5))), "event_type": "control.not_following", "driver": "sungrow",
       "title": "sungrow is not following FTW", "body": "Asked for 4.2 kW charge; it delivers 1.2 kW.", "priority": 4, "status": "sent"},
      {"id": 30, "ts_ms": \(Int(local(6, 24))), "event_type": "control.not_following", "title": "queued", "status": "queued"}
     ]}
    """

    static func answer(_ text: String = vector) throws -> JournalAnswer {
        JournalAnswer(try JSON(parsing: Array(text.utf8)))
    }

    static let sources: [String: Source] = [
        "easee": Source(kind: "charger", name: "easee", lastOkMs: 0, staleAfterMs: 10_000, state: .live),
        "sdm630": Source(kind: "meter", name: "sdm630", lastOkMs: 0, staleAfterMs: 10_000, state: .live),
    ]

    func happened(_ answer: JournalAnswer, nowMs: Double = Self.noon) -> [JournalEntry] {
        AppWords.$language.withValue(.en) {
            ControlFeedback.happened(answer, sources: Self.sources, zone: Self.zone, nowMs: nowMs)
        }
    }

    @Test func readsCoresAnswer() throws {
        let a = try Self.answer()
        #expect(a.spans.count == 6)
        #expect(a.notices.count == 2)
        #expect(a.more == false)
        let battery = try #require(a.spans.first { $0.id == 6 })
        #expect(battery.subject == "battery:sungrow")
        #expect(battery.kind == "battery")
        #expect(battery.requested == JournalSpan.Power(min: 4200, max: 4200, mean: 4200, n: 187))
        #expect(battery.actual?.mean == 1200)
        #expect(battery.endMs == Self.local(6, 29, 40))
        #expect(battery.last?["actual_w"]?.number == 1160)
        let quiet = try #require(a.spans.first { $0.id == 8 })
        #expect(quiet.requested == nil && quiet.actual == nil)
        #expect(a.notices[0].status == "sent")
        #expect(a.notices[0].eventType == "control.not_following")
        // An open span has no end, and an empty answer is still an answer.
        let open = try #require(JournalSpan(try JSON(parsing: Array(#"{"id": 3, "kind": "dispatch", "start_ms": 5, "end_ms": null}"#.utf8))))
        #expect(open.endMs == nil)
        #expect(JournalAnswer(nil).spans.isEmpty)
        #expect(JournalSpan(try JSON(parsing: Array(#"{"kind": "dispatch"}"#.utf8))) == nil)
    }

    /// The morning of 8 Nov 2026: one line each, newest first, and nothing
    /// said twice.
    @Test func theMorningInWords() throws {
        let lines = happened(try Self.answer())
        #expect(lines.map(\.id) == ["span:9", "notice:31", "span:7", "span:6", "span:1"])
        #expect(!lines.contains { $0.ongoing })

        let charger = lines[0]
        #expect(charger.title == "No fresh readings")
        #expect(charger.name == "easee · charger")
        #expect(charger.text == "The charger was not reporting.")
        #expect(charger.when == "08:02–08:09")

        let notice = lines[1]
        #expect(notice.mark == .noticeSent)
        #expect(notice.title == "sungrow is not following FTW")
        #expect(notice.name == "Notice sent")
        #expect(notice.when == "06:24")

        let slot = lines[2]
        #expect(slot.title == "Battery behind the plan")
        #expect(slot.text == "Planned 1.1\u{00A0}kWh charge, delivered 315\u{00A0}Wh.")
        #expect(slot.when == "06:15–06:30")

        let battery = lines[3]
        #expect(battery.mark == .tone(.warning))
        #expect(battery.title == "Not following")
        #expect(battery.name == "sungrow · battery")
        #expect(battery.text == "Asked for 4.2 kW charge, delivered 1.2 kW on average.")
        #expect(battery.when == "06:14–06:29")

        let dispatch = lines[4]
        #expect(dispatch.title == "FTW was not in control")
        #expect(dispatch.name == nil)
        #expect(dispatch.text == "FTW stopped control because the grid meter readings are out of date.")
        #expect(dispatch.when == "05:52 · 3 s")

        // No raw sign, code or placeholder anywhere.
        for line in lines {
            let shown = [line.title, line.name ?? "", line.text, line.when].joined(separator: " ")
            #expect(shown.range(of: #"-\d|_|%@|null"#, options: .regularExpression) == nil, "\(shown)")
        }
    }

    @Test func whatStillHoldsSaysSince() {
        let open = JournalSpan(id: 1, subject: "site:dispatch", kind: "dispatch", status: "blocked", reason: "site_phase_currents_stale",
                               startMs: Self.local(11, 40), endMs: nil)
        let quiet = JournalSpan(id: 2, subject: "source:sdm630", driver: "sdm630", kind: "source", status: "offline", reason: "telemetry_stale",
                                startMs: Self.local(11, 41), endMs: nil)
        let lines = happened(JournalAnswer(spans: [open, quiet]))
        #expect(lines.map(\.title) == ["No fresh readings", "FTW is not in control"])
        #expect(lines[0].text == "The meter is not reporting.")
        #expect(lines[0].when == "Since 11:41")
        #expect(lines.allSatisfy { $0.ongoing })
        #expect(lines[1].when == "Since 11:40")
        #expect(lines[1].text == "FTW stopped control because it lacks fresh phase currents for the main fuse check.")
    }

    @Test func beforeMidnightSaysYesterday() {
        let span = JournalSpan(id: 1, subject: "battery:sungrow", driver: "sungrow", kind: "battery", status: "no_contact",
                               reason: "command_failed", startMs: Self.local(-2, 10), endMs: Self.local(-2, 30))
        let line = happened(JournalAnswer(spans: [span]))[0]
        #expect(line.when == "Yesterday 22:10–22:30")
        #expect(line.title == "Commands failing")
        // No power numbers: the live row's own sentence.
        #expect(line.text == "The last command to the battery failed. FTW keeps trying.")
        AppWords.$language.withValue(.sv) {
            #expect(ControlFeedback.when(startMs: Self.local(-2, 10), endMs: nil, nowMs: Self.noon, zone: Self.zone) == "Sedan i går 22:10")
        }
    }

    /// A warning that turns into an alarm is one stretch: one line, the
    /// worse tone, the means over both.
    @Test func backToBackStretchesReadAsOne() {
        let warn = JournalSpan(id: 1, subject: "ev:easee", driver: "easee", kind: "ev", status: "not_following", reason: "power_above_target",
                               severity: "warning", startMs: Self.local(9, 0), endMs: Self.local(9, 10),
                               requested: .init(min: 7000, max: 7000, mean: 7000, n: 3), actual: .init(min: 9000, max: 9000, mean: 9000, n: 3))
        let alarm = JournalSpan(id: 2, subject: "ev:easee", driver: "easee", kind: "ev", status: "not_following", reason: "power_above_target",
                                severity: "alarm", startMs: Self.local(9, 10), endMs: Self.local(9, 20),
                                requested: .init(min: 7000, max: 7000, mean: 7000, n: 1), actual: .init(min: 11000, max: 11000, mean: 11000, n: 1))
        let lines = happened(JournalAnswer(spans: [alarm, warn]))
        #expect(lines.count == 1)
        #expect(lines[0].mark == .tone(.alarm))
        #expect(lines[0].when == "09:00–09:20")
        #expect(lines[0].text == "Asked for 7.0 kW charge, delivered 9.5 kW on average.")
        // A gap between them means something else held: two lines.
        var later = alarm
        later.startMs = Self.local(9, 15)
        #expect(happened(JournalAnswer(spans: [later, warn])).count == 2)
    }

    @Test func theDirectionIsNamedWhenItDiffers() {
        let span = JournalSpan(id: 1, subject: "battery:sungrow", driver: "sungrow", kind: "battery", status: "not_following",
                               reason: "power_wrong_direction", startMs: Self.local(7, 0), endMs: Self.local(7, 5),
                               requested: .init(min: 812, max: 812, mean: 812, n: 4), actual: .init(min: -1300, max: -1100, mean: -1200, n: 4))
        #expect(happened(JournalAnswer(spans: [span]))[0].text == "Asked for 812 W charge, delivered 1.2 kW discharge on average.")
        var idle = span
        idle.requested = .init(min: 0, max: 0, mean: 0, n: 4)
        idle.reason = "power_while_idle"
        #expect(happened(JournalAnswer(spans: [idle]))[0].text == "Asked to stay idle, delivered 1.2 kW discharge on average.")
    }

    /// Only warnings and alarms, sent and failed notices; the mode and
    /// calm stretches stay out even when the box sends them.
    @Test func onlyWhatNeededALook() {
        let calm = JournalSpan(id: 1, subject: "battery:sungrow", driver: "sungrow", kind: "battery", status: "following", reason: "plan",
                               severity: "info", startMs: Self.local(7, 0), endMs: nil)
        let mode = JournalSpan(id: 2, subject: "site:mode", kind: "mode", status: "planner_arbitrage", severity: "warning", startMs: Self.local(7, 0), endMs: nil)
        let over = JournalSpan(id: 3, subject: "slot:battery", kind: "slot", status: "over_delivered", severity: "warning", startMs: Self.local(7, 0), endMs: Self.local(7, 15))
        let failed = JournalNotice(id: 4, tsMs: Self.local(7, 1), eventType: "driver.offline", title: "easee is offline", status: "failed", error: "timeout")
        let lines = happened(JournalAnswer(spans: [calm, mode, over], notices: [failed]))
        #expect(lines.map(\.id) == ["notice:4"])
        #expect(lines[0].mark == .noticeFailed)
        #expect(lines[0].name == "Notice not sent: timeout")
    }

    @Test func inSwedish() throws {
        let lines = AppWords.$language.withValue(.sv) {
            ControlFeedback.happened(try! Self.answer(), sources: Self.sources, zone: Self.zone, nowMs: Self.noon)
        }
        #expect(lines[0].text == "Laddaren rapporterade inte.")
        #expect(lines[0].name == "easee · laddare")
        #expect(lines[1].name == "Notis skickad")
        #expect(lines[2].text == "Planerat 1,1\u{00A0}kWh laddning, levererat 315\u{00A0}Wh.")
        #expect(lines[3].title == "Följer inte")
        #expect(lines[3].text == "Bad om 4,2 kW laddning, levererade i snitt 1,2 kW.")
        #expect(lines[4].title == "FTW styrde inte")
    }

    /// The demo box keeps the same morning, and an older box answers 404:
    /// the sheet then has nothing new to show.
    @MainActor
    @Test func theDemoBoxKeepsAMorning() async throws {
        let rig = DemoRig(nowMs: Self.noon)
        rig.app.startDemo()
        let home = try #require(rig.app.home)
        await rig.run(3_000)
        let journal = home.journal
        #expect(journal.canRead && journal.shown)
        let read = Task { await journal.read() }
        await rig.run(1_000)
        await read.value
        #expect(journal.phase == .ready)
        #expect(rig.box?.receivedRequests.contains("GET /api/control/journal") == true)
        let lines = AppWords.$language.withValue(.en) { journal.entries() }
        #expect(lines.map(\.title) == ["No fresh readings", "sungrow is not following FTW", "Battery behind the plan", "Not following", "FTW was not in control"])
        #expect(lines.map(\.when) == ["08:02–08:09", "06:24", "06:15–06:30", "06:14–06:29", "05:52 · 3 s"])
        #expect(lines[3].text == "Asked for 4.2 kW charge, delivered 1.2 kW on average.")

        rig.box?.keepsJournal = false
        let again = Task { await journal.read() }
        await rig.run(1_000)
        await again.value
        #expect(journal.phase == .oldBox)
        #expect(!journal.shown)
        #expect(journal.entries().isEmpty)
    }
}
