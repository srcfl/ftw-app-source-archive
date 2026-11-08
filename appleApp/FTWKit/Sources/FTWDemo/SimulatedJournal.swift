import Foundation
import FTWKit

/// The demo box's control journal, GET /api/control/journal: one morning as
/// the owner's box kept it on 8 Nov 2026. The box restarts at 05:52 and
/// holds dispatch for 3 s until its meter reads again; from 06:14 to 06:29
/// FTW asks the battery for 4.2 kW of charge and it takes 1.2 kW, so the
/// quarter from 06:15 falls behind the plan and the box sends a notice;
/// at 08:02 the charger goes quiet for seven minutes. The morning is today's
/// once it has passed, else yesterday's.
extension SimulatedBox {
    func journalJSON(nowMs: Double, query: [String: String]) -> JSON {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = house.timeZone
        let now = Date(timeIntervalSince1970: nowMs / 1000)
        var day = calendar.startOfDay(for: now)
        func at(_ h: Int, _ m: Int, _ s: Double = 0) -> Double {
            (calendar.date(bySettingHour: h, minute: m, second: 0, of: day)?.timeIntervalSince1970 ?? 0) * 1000 + s * 1000
        }
        if nowMs < at(8, 30) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        let mode = house.modeKey

        func battery(_ actual: Double, atMs: Double) -> JSON {
            [
                "driver": "sungrow", "kind": "battery", "mode": .string(mode), "status": "not_following", "reason": "power_below_target",
                "severity": "warning", "evidence": "measured", "readings_fresh": true, "requested_w": 4200, "sent_w": 4200,
                "readback_w": 4200, "actual_w": .number(actual), "battery_soc": 0.41, "tolerance_w": 150,
                "command_at_ms": .number(atMs - 4_000), "observed_at_ms": .number(atMs - 1_000), "site_confirmation": "no_clear_change",
            ]
        }
        func power(_ min: Double, _ max: Double, _ mean: Double, _ n: Double) -> JSON {
            ["min": .number(min), "max": .number(max), "mean": .number(mean), "n": .number(n)]
        }
        func span(_ id: Int, _ subject: String, driver: String = "", kind: String, status: String, reason: String = "", severity: String,
                  from: Double, to: Double?, requested: JSON = .null, actual: JSON = .null, first: JSON? = nil, last: JSON? = nil) -> JSON {
            // A span that still holds has no end; its numbers run to now.
            let end = to ?? nowMs
            var j: JSON = [
                "id": .number(Double(id)), "subject": .string(subject), "kind": .string(kind), "status": .string(status),
                "severity": .string(severity), "mode": .string(mode), "start_ms": .number(from), "end_ms": to.map(JSON.number) ?? .null,
                "updated_ms": .number(end), "duration_s": .number((end - from) / 1000), "samples": .number(max(1, ((end - from) / 5_000).rounded())),
                "requested_w": requested, "actual_w": actual,
            ]
            if !driver.isEmpty { j = j.setting("driver", .string(driver)) }
            if !reason.isEmpty { j = j.setting("reason", .string(reason)) }
            if let first { j = j.setting("first", first) }
            if let last { j = j.setting("last", last) }
            return j
        }

        let restart = at(5, 52, 10), lowStart = at(6, 14, 5), lowEnd = at(6, 29, 40)
        let quiet = at(8, 2, 30), back = at(8, 9, 10)
        let charger: JSON = ["status": "offline", "consecutive_errors": 40, "last_success_ms": .number(quiet - 30_000), "last_error": "no answer from the charger"]
        var spans: [JSON] = [
            span(10, "battery:sungrow", driver: "sungrow", kind: "battery", status: "following", reason: "plan", severity: "info",
                 from: lowEnd, to: nil, requested: power(-1800, 2400, 300, 400), actual: power(-1790, 2390, 296, 400)),
            span(9, "source:easee", driver: "easee", kind: "source", status: "offline", reason: "telemetry_stale", severity: "warning",
                 from: quiet, to: back, first: charger, last: charger),
            // The charger's control row says the same in the same minutes.
            span(8, "ev:easee", driver: "easee", kind: "ev", status: "no_contact", reason: "telemetry_stale", severity: "warning", from: quiet, to: back),
            span(7, "slot:battery", kind: "slot", status: "under_delivered", severity: "warning", from: at(6, 15), to: at(6, 30),
                 requested: power(4200, 4200, 4200, 1), actual: power(1260, 1260, 1260, 1),
                 first: ["planned_wh": 1050, "actual_wh": 315, "ratio": 0.3, "replans": 0]),
            span(6, "battery:sungrow", driver: "sungrow", kind: "battery", status: "not_following", reason: "power_below_target", severity: "warning",
                 from: lowStart, to: lowEnd, requested: power(4200, 4200, 4200, 187), actual: power(1090, 1350, 1200, 187),
                 first: battery(1240, atMs: lowStart), last: battery(1160, atMs: lowEnd)),
            span(5, "slot:battery", kind: "slot", status: "on_target", severity: "info", from: at(6, 0), to: at(6, 15),
                 first: ["planned_wh": 1050, "actual_wh": 1000, "ratio": 0.95, "replans": 0]),
            span(4, "battery:sungrow", driver: "sungrow", kind: "battery", status: "following", reason: "plan", severity: "info",
                 from: restart + 15_000, to: lowStart, requested: power(0, 4200, 3100, 240), actual: power(0, 4190, 3080, 240)),
            span(3, "site:dispatch", kind: "dispatch", status: "free", severity: "info", from: restart + 3_000, to: nil),
            span(2, "battery:sungrow", driver: "sungrow", kind: "battery", status: "not_controlled", reason: "site_meter_stale", severity: "warning",
                 from: restart, to: restart + 3_000),
            span(1, "site:dispatch", kind: "dispatch", status: "blocked", reason: "site_meter_stale", severity: "warning", from: restart, to: restart + 3_000),
        ]
        let since = Double(query["since"] ?? "") ?? nowMs - 86_400_000
        let until = Double(query["until"] ?? "") ?? nowMs
        let wanted: Set<String>? = query["severity"] == "warning" ? ["warning", "alarm"] : nil
        spans = spans.filter { s in
            let start = s["start_ms"]?.number ?? 0, end = s["end_ms"]?.number ?? nowMs
            return start <= until && end >= since && wanted.map { $0.contains(s["severity"]?.string ?? "") } ?? true
        }
        let notices: [JSON] = [
            [
                "id": 31, "ts_ms": .number(lowStart + 600_000), "event_type": "control.not_following", "driver": "sungrow",
                "title": "sungrow is not following FTW", "body": "Asked for 4.2 kW charge for 10 minutes; it delivers 1.2 kW.",
                "priority": 4, "status": "sent",
            ],
        ].filter { ($0["ts_ms"]?.number ?? 0) >= since && ($0["ts_ms"]?.number ?? 0) <= until }
        return [
            "since_ms": .number(since), "until_ms": .number(until), "spans": .array(spans), "more": false,
            "notifications": .array(notices), "notifications_more": false,
        ]
    }
}
