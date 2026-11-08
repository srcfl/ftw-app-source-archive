import Foundation
import FTWShared

/// Whether the batteries do what the plan meant for this quarter, from
/// `plan_now` in GET /api/status. Core decides it and names the cause; this
/// only words it, as the box's web/control-feedback.js does. Watts follow the
/// site convention: charge and load positive, solar negative.
public struct PlanNow: Equatable, Sendable {
    public var status: String
    public var why: String
    public var deviceReason: String
    /// When a change under way takes effect, by the box's clock.
    public var settlesAtMs: Double?
    public var batteryW: Double
    public var plannedBatteryW: Double
    public var pvW: Double?
    public var plannedPVW: Double?
    public var loadW: Double?
    public var plannedLoadW: Double?
    public var evW: Double?
    public var plannedEVW: Double?

    public init(status: String, why: String = "", deviceReason: String = "", settlesAtMs: Double? = nil, batteryW: Double, plannedBatteryW: Double,
                pvW: Double? = nil, plannedPVW: Double? = nil, loadW: Double? = nil, plannedLoadW: Double? = nil, evW: Double? = nil, plannedEVW: Double? = nil) {
        self.status = status
        self.why = why
        self.deviceReason = deviceReason
        self.settlesAtMs = settlesAtMs
        self.batteryW = batteryW
        self.plannedBatteryW = plannedBatteryW
        self.pvW = pvW
        self.plannedPVW = plannedPVW
        self.loadW = loadW
        self.plannedLoadW = plannedLoadW
        self.evW = evW
        self.plannedEVW = plannedEVW
    }

    /// What a status document says; nil on a box that does not compare, or
    /// when no plan steers the batteries.
    public init?(status doc: JSON?) {
        guard let j = doc?["plan_now"], let status = j["status"]?.string,
              let battery = j["battery_w"]?.number, let planned = j["planned_battery_w"]?.number else { return nil }
        self.init(status: status, why: j["why"]?.string ?? "", deviceReason: j["device_reason"]?.string ?? "",
                  settlesAtMs: j["settles_at_ms"]?.number.flatMap { $0 > 0 ? $0 : nil },
                  batteryW: battery, plannedBatteryW: planned,
                  pvW: j["pv_w"]?.number, plannedPVW: j["planned_pv_w"]?.number,
                  loadW: j["load_w"]?.number, plannedLoadW: j["planned_load_w"]?.number,
                  evW: j["ev_w"]?.number, plannedEVW: j["planned_ev_w"]?.number)
    }

    public var isOffPlan: Bool { status == "off_plan" }

    public struct Words: Equatable, Sendable {
        /// "Discharging 1.2 kW"
        public let now: String
        /// "Now: discharging 1.2 kW"
        public let nowLine: String
        /// "The plan said: charge 2.6 kW"
        public let plan: String
        /// "The sun gives 1.4 kW; the forecast said 3.8 kW."
        public let why: String
        /// "The battery covers the home, so you buy less."; empty when
        /// there is nothing to add.
        public let then: String

        /// For the line under the plan's strip.
        public var sentence: String { "\(now). \(plan). \(why)" }
        /// `sentence` one clause shorter each, for a narrow screen.
        public var shorter: [String] {
            ["\(now). \(plan).", ControlWords.format("%@, not as planned.", now)]
        }
    }

    /// Nil while the batteries follow the plan.
    public var words: Words? {
        guard isOffPlan else { return nil }
        let w = ControlWords.self
        func doing(_ watts: Double, _ charge: String, _ discharge: String, _ rest: String) -> String {
            guard abs(watts) >= 100 else { return w.text(rest) }
            return w.format(watts > 0 ? charge : discharge, ControlFeedback.power(watts))
        }
        let now = doing(batteryW, "charging %@", "discharging %@", "idle")
        return Words(
            now: ControlFeedback.capital(now),
            nowLine: w.format("Now: %@", now),
            plan: doing(plannedBatteryW, "The plan said: charge %@", "The plan said: discharge %@", "The plan said: rest"),
            why: whyLine,
            then: thenLine
        )
    }

    private var whyLine: String {
        let w = ControlWords.self
        func pair(_ en: String, _ actual: Double?, _ planned: Double?) -> String {
            guard let actual, let planned else { return w.text("FTW follows what the home and the sun do now, not the forecast.") }
            return w.format(en, ControlFeedback.power(actual), ControlFeedback.power(planned))
        }
        switch why {
        case "less_solar", "more_solar": return pair("The sun gives %@; the forecast said %@.", pvW, plannedPVW)
        case "more_home", "less_home": return pair("The home uses %@; the forecast said %@.", loadW, plannedLoadW)
        case "more_car", "less_car": return pair("The car takes %@; the plan said %@.", evW, plannedEVW)
        case "manual": return w.text("You are holding the battery by hand.")
        case "device":
            guard let title = ControlFeedback.reasonTitles[deviceReason] else { return w.text("The battery cannot follow the plan right now.") }
            return w.text(title) + "."
        default: return w.text("FTW follows what the home and the sun do now, not the forecast.")
        }
    }

    private var thenLine: String {
        let w = ControlWords.self
        guard ["less_solar", "more_solar", "more_home", "less_home", "more_car", "less_car"].contains(why) else { return "" }
        if batteryW <= -100 {
            return w.text(plannedBatteryW > -100 || abs(batteryW) > abs(plannedBatteryW)
                ? "The battery covers the home, so you buy less." : "The battery gives only what the home needs.")
        }
        if batteryW >= 100 { return w.text("The battery charges with what is left over.") }
        return w.text(plannedBatteryW > 0 ? "Nothing is left over to charge with." : "The battery rests.")
    }
}
