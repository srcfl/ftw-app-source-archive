import Foundation
import FTWShared

/// One stretch in the box's control journal, from GET /api/control/journal:
/// the time one subject held one verdict. Core owns every field; the phone
/// only puts words to it. Missing numbers stay nil, never zero.
public struct JournalSpan: Equatable, Sendable, Identifiable {
    /// Power over the stretch, as Core summed it.
    public struct Power: Equatable, Sendable {
        public var min: Double
        public var max: Double
        public var mean: Double
        public var n: Double

        public init(min: Double, max: Double, mean: Double, n: Double) {
            self.min = min
            self.max = max
            self.mean = mean
            self.n = n
        }

        init?(_ j: JSON?) {
            guard let j, let mean = j["mean"]?.number, mean.isFinite else { return nil }
            self.init(min: j["min"]?.number ?? mean, max: j["max"]?.number ?? mean, mean: mean, n: j["n"]?.number ?? 1)
        }
    }

    public var id: Int
    /// "battery:sungrow", "source:easee", "site:dispatch", "slot:battery".
    public var subject: String
    public var driver: String
    /// battery, ev, pv, v2x_charger, device, source, dispatch, mode or slot.
    public var kind: String
    public var status: String
    public var reason: String
    public var severity: String
    public var mode: String
    public var startMs: Double
    /// Nil while the verdict still holds.
    public var endMs: Double?
    public var updatedMs: Double
    public var samples: Double
    public var requested: Power?
    public var actual: Power?
    /// The verdict as Core served it when the stretch began and last: for
    /// a device, the control_feedback row of GET /api/status.
    public var first: JSON?
    public var last: JSON?

    public init(id: Int, subject: String, driver: String = "", kind: String, status: String, reason: String = "", severity: String = "warning",
                mode: String = "", startMs: Double, endMs: Double?, updatedMs: Double? = nil, samples: Double = 1,
                requested: Power? = nil, actual: Power? = nil, first: JSON? = nil, last: JSON? = nil) {
        self.id = id
        self.subject = subject
        self.driver = driver
        self.kind = kind
        self.status = status
        self.reason = reason
        self.severity = severity
        self.mode = mode
        self.startMs = startMs
        self.endMs = endMs
        self.updatedMs = updatedMs ?? endMs ?? startMs
        self.samples = samples
        self.requested = requested
        self.actual = actual
        self.first = first
        self.last = last
    }

    /// A span as the box sent it; nil without an id, a kind and a start.
    public init?(_ j: JSON) {
        guard let id = j["id"]?.number, let kind = j["kind"]?.string, let start = j["start_ms"]?.number else { return nil }
        self.init(id: Int(id), subject: j["subject"]?.string ?? kind, driver: j["driver"]?.string ?? "", kind: kind,
                  status: j["status"]?.string ?? "", reason: j["reason"]?.string ?? "", severity: j["severity"]?.string ?? "info",
                  mode: j["mode"]?.string ?? "", startMs: start, endMs: j["end_ms"]?.number, updatedMs: j["updated_ms"]?.number,
                  samples: j["samples"]?.number ?? 0, requested: Power(j["requested_w"]), actual: Power(j["actual_w"]),
                  first: j["first"].flatMap { $0.object != nil ? $0 : nil }, last: j["last"].flatMap { $0.object != nil ? $0 : nil })
    }

    public var needsLook: Bool { severity == "warning" || severity == "alarm" }

    /// Whether two stretches share any time; an open one runs to `nowMs`.
    /// Whether this stretch held for all of `other`, give or take the time
    /// between two of the journal's samples.
    func covers(_ other: JournalSpan, nowMs: Double) -> Bool {
        let margin = ControlFeedback.joinMs * 2
        return startMs <= other.startMs + margin && (endMs ?? nowMs) >= (other.endMs ?? nowMs) - margin
    }
}

/// A notice the box sent, or tried to send, in the journal's window.
public struct JournalNotice: Equatable, Sendable, Identifiable {
    public var id: Int
    public var tsMs: Double
    public var eventType: String
    public var driver: String
    public var title: String
    public var body: String
    /// sent, failed or queued.
    public var status: String
    public var error: String

    public init(id: Int, tsMs: Double, eventType: String, driver: String = "", title: String, body: String = "", status: String, error: String = "") {
        self.id = id
        self.tsMs = tsMs
        self.eventType = eventType
        self.driver = driver
        self.title = title
        self.body = body
        self.status = status
        self.error = error
    }

    public init?(_ j: JSON) {
        guard let id = j["id"]?.number, let ts = j["ts_ms"]?.number else { return nil }
        self.init(id: Int(id), tsMs: ts, eventType: j["event_type"]?.string ?? "", driver: j["driver"]?.string ?? "",
                  title: j["title"]?.string ?? "", body: j["body"]?.string ?? "", status: j["status"]?.string ?? "", error: j["error"]?.string ?? "")
    }
}

/// The box's answer to "what happened": its spans newest first, and the
/// notices it sent.
public struct JournalAnswer: Equatable, Sendable {
    public var sinceMs: Double?
    public var untilMs: Double?
    public var spans: [JournalSpan]
    public var more: Bool
    public var notices: [JournalNotice]
    public var noticesMore: Bool

    public init(sinceMs: Double? = nil, untilMs: Double? = nil, spans: [JournalSpan], more: Bool = false, notices: [JournalNotice] = [], noticesMore: Bool = false) {
        self.sinceMs = sinceMs
        self.untilMs = untilMs
        self.spans = spans
        self.more = more
        self.notices = notices
        self.noticesMore = noticesMore
    }

    public init(_ j: JSON?) {
        self.init(sinceMs: j?["since_ms"]?.number, untilMs: j?["until_ms"]?.number,
                  spans: j?["spans"]?.array?.compactMap(JournalSpan.init) ?? [], more: j?["more"]?.bool ?? false,
                  notices: j?["notifications"]?.array?.compactMap(JournalNotice.init) ?? [], noticesMore: j?["notifications_more"]?.bool ?? false)
    }
}

/// One line of "What happened" in the control sheet.
public struct JournalEntry: Equatable, Sendable, Identifiable {
    public enum Mark: Equatable, Sendable {
        case tone(ControlFeedback.Tone)
        case noticeSent
        case noticeFailed
    }

    public let id: String
    public let mark: Mark
    public let title: String
    /// What it was about, as the sheet names it elsewhere: "sungrow ·
    /// battery". Nil for the home as a whole.
    public let name: String?
    public let text: String
    /// "06:14–06:29", "Since 06:14", "05:52 · 3 s".
    public let when: String
    /// Newest first by this.
    public let atMs: Double
    /// Still holds: only this takes the alarm's colour; what has passed
    /// is ink.
    public let ongoing: Bool

    public init(id: String, mark: Mark, title: String, name: String?, text: String, when: String, atMs: Double, ongoing: Bool = false) {
        self.id = id
        self.mark = mark
        self.title = title
        self.name = name
        self.text = text
        self.when = when
        self.atMs = atMs
        self.ongoing = ongoing
    }
}

extension ControlFeedback {
    /// Reasons a device row shares with the site's dispatch block: the
    /// dispatch line says them once.
    static let dispatchReasons: Set<String> = ["site_meter_stale", "site_phase_currents_stale"]
    /// How close two stretches of one verdict must lie to read as one.
    static let joinMs: Double = 5_000

    /// The journal's warnings and alarms in words, with the notices the box
    /// sent or failed to send, newest first. A device's line takes the live
    /// row's words; a dispatch block says FTW was not in control and why; a
    /// source says the device was not reporting; a plan slot behind the plan
    /// gets a line of its own. A device line that only repeats a dispatch
    /// block or a quiet source for all of its time is left out, and back-to-back
    /// stretches of one verdict read as one. Nothing here is the phone's own
    /// verdict.
    public static func happened(_ answer: JournalAnswer, sources: [String: Source] = [:], zone: TimeZone = .current, nowMs: Double) -> [JournalEntry] {
        let looked = answer.spans.filter { span in
            guard span.needsLook else { return false }
            switch span.kind {
            case "mode": return false
            case "slot": return span.status == "under_delivered" || span.status == "sign_mismatch"
            default: return true
            }
        }
        let blocks = looked.filter { $0.kind == "dispatch" }
        let quiet = looked.filter { $0.kind == "source" }
        let kept = looked.filter { span in
            if ["dispatch", "source", "slot"].contains(span.kind) { return true }
            if dispatchReasons.contains(span.reason), blocks.contains(where: { $0.reason == span.reason && $0.covers(span, nowMs: nowMs) }) { return false }
            if span.reason == "telemetry_stale", quiet.contains(where: { $0.driver == span.driver && $0.covers(span, nowMs: nowMs) }) { return false }
            return true
        }
        var entries = joined(kept).map { entry($0, sources: sources, zone: zone, nowMs: nowMs) }
        for notice in answer.notices where notice.status == "sent" || notice.status == "failed" {
            entries.append(entry(notice, zone: zone, nowMs: nowMs))
        }
        return entries.sorted { ($0.atMs, $0.id) > ($1.atMs, $1.id) }
    }

    /// Back-to-back stretches of one subject, status and reason as one: an
    /// escalation from warning to alarm is still the same thing happening.
    static func joined(_ spans: [JournalSpan]) -> [JournalSpan] {
        var out = [JournalSpan]()
        for span in spans.sorted(by: { ($0.subject, $0.startMs, $0.id) < ($1.subject, $1.startMs, $1.id) }) {
            guard let i = out.indices.last, out[i].subject == span.subject, out[i].kind != "slot", out[i].status == span.status, out[i].reason == span.reason,
                  let end = out[i].endMs, span.startMs - end <= joinMs, span.startMs >= out[i].startMs else {
                out.append(span)
                continue
            }
            var a = out[i]
            a.endMs = span.endMs
            a.updatedMs = max(a.updatedMs, span.updatedMs)
            a.samples += span.samples
            if span.severity == "alarm" { a.severity = "alarm" }
            a.requested = merge(a.requested, span.requested)
            a.actual = merge(a.actual, span.actual)
            a.last = span.last ?? a.last
            out[i] = a
        }
        return out
    }

    static func merge(_ a: JournalSpan.Power?, _ b: JournalSpan.Power?) -> JournalSpan.Power? {
        guard let a else { return b }
        guard let b else { return a }
        let n = a.n + b.n
        guard n > 0 else { return a }
        return JournalSpan.Power(min: Swift.min(a.min, b.min), max: Swift.max(a.max, b.max), mean: (a.mean * a.n + b.mean * b.n) / n, n: n)
    }

    /// "06:14–06:29"; "Since 06:14" while it holds; "05:52 · 3 s" when it
    /// lasted under a minute; "Yesterday 22:10–22:30" before the
    /// household's midnight.
    public static func when(startMs: Double, endMs: Double?, nowMs: Double, zone: TimeZone) -> String {
        let clock = ZoneClock.of(zone)
        let start = stamp(startMs, nowMs: nowMs, zone: zone)
        guard let endMs else { return capital(ControlWords.format("since %@", start)) }
        let lasted = endMs - startMs
        if lasted < 60_000 { return capital("\(start) · \(Int(max(1, (lasted / 1000).rounded()))) s") }
        return capital("\(start)–\(clock.label(endMs))")
    }

    /// "06:14", or "yesterday 22:10" before the household's midnight.
    static func stamp(_ ms: Double, nowMs: Double, zone: TimeZone) -> String {
        let clock = ZoneClock.of(zone)
        return ms < clock.alignDown(nowMs, stepMs: 86_400_000) ? ControlWords.format("yesterday %@", clock.label(ms)) : clock.label(ms)
    }

    static func entry(_ span: JournalSpan, sources: [String: Source], zone: TimeZone, nowMs: Double) -> JournalEntry {
        let w = ControlWords.self
        let tone: Tone = span.severity == "alarm" ? .alarm : .warning
        let when = when(startMs: span.startMs, endMs: span.endMs, nowMs: nowMs, zone: zone)
        let ongoing = span.endMs == nil
        let id = "span:\(span.id)"
        switch span.kind {
        case "dispatch":
            let row = ControlRow(driver: "", kind: "dispatch", status: span.status, reason: span.reason, severity: span.severity)
            return JournalEntry(id: id, mark: .tone(tone), title: w.text(ongoing ? "FTW is not in control" : "FTW was not in control"), name: nil,
                                text: sentence(row, zone), when: when, atMs: span.startMs, ongoing: ongoing)
        case "source":
            let source = sources[span.driver]
            let noun = sourceNoun(source?.kind)
            let name = span.driver.isEmpty ? nil : source.map { "\(span.driver) · \(w.text(sourceKind($0.kind)))" } ?? span.driver
            if span.status == "fault" || span.reason == "device_fault" {
                let why = (span.last?["device_fault_reason"] ?? span.first?["device_fault_reason"])?.string.flatMap { $0.isEmpty ? nil : $0 }
                let text = why.map { w.format("%@ reported a fault: %@.", capital(noun), $0) } ?? w.format("%@ reported a fault.", capital(noun))
                return JournalEntry(id: id, mark: .tone(tone), title: w.text("Device fault"), name: name, text: text, when: when, atMs: span.startMs, ongoing: ongoing)
            }
            return JournalEntry(id: id, mark: .tone(tone), title: w.text("No fresh readings"), name: name,
                                text: w.format(ongoing ? "%@ is not reporting." : "%@ was not reporting.", capital(noun)), when: when, atMs: span.startMs, ongoing: ongoing)
        case "slot":
            let planned = span.first?["planned_wh"]?.number
            let delivered = span.first?["actual_wh"]?.number
            let title = w.text(span.status == "sign_mismatch" ? "Battery went the other way" : "Battery behind the plan")
            let text: String
            if let planned, planned.isFinite, let delivered, delivered.isFinite {
                text = w.format("Planned %@, delivered %@.", energyFlow(planned), sameWay(planned, delivered) ? NodeLive.energy(abs(delivered)) : energyFlow(delivered))
            } else if let asked = span.requested?.mean, let got = span.actual?.mean {
                let battery = ControlRow(driver: "", kind: "battery", status: span.status, reason: span.reason)
                text = askedDelivered(battery, asked, got)
            } else {
                text = w.text("The plan’s quarter delivered less than planned.")
            }
            return JournalEntry(id: id, mark: .tone(tone), title: title, name: nil, text: text, when: when, atMs: span.startMs, ongoing: ongoing)
        default:
            var row = span.last.flatMap(ControlRow.init) ?? span.first.flatMap(ControlRow.init)
                ?? ControlRow(driver: span.driver, kind: span.kind, mode: span.mode, status: span.status, reason: span.reason, severity: span.severity)
            // The stretch's own verdict, whatever its latest row carried.
            row.driver = span.driver.isEmpty ? row.driver : span.driver
            row.kind = span.kind
            row.status = span.status
            row.reason = span.reason
            row.severity = span.severity
            let words = status(row, live: true, zone: zone)
            let text: String
            if let asked = span.requested?.mean, let got = span.actual?.mean {
                text = askedDelivered(row, asked, got)
            } else {
                text = words.text
            }
            return JournalEntry(id: id, mark: .tone(tone), title: words.title, name: "\(row.driver) · \(kind(row))", text: text, when: when, atMs: span.startMs, ongoing: ongoing)
        }
    }

    static func entry(_ notice: JournalNotice, zone: TimeZone, nowMs: Double) -> JournalEntry {
        let w = ControlWords.self
        let failed = notice.status == "failed"
        let state = failed ? (notice.error.isEmpty ? w.text("Notice not sent") : w.format("Notice not sent: %@", notice.error)) : w.text("Notice sent")
        let title = notice.title.isEmpty ? notice.eventType : notice.title
        return JournalEntry(id: "notice:\(notice.id)", mark: failed ? .noticeFailed : .noticeSent, title: title, name: state, text: notice.body,
                            when: capital(stamp(notice.tsMs, nowMs: nowMs, zone: zone)), atMs: notice.tsMs)
    }

    /// "Asked for 4.2 kW charge, delivered 1.2 kW on average.": the means
    /// over the stretch, with the direction named whenever it differs.
    static func askedDelivered(_ row: ControlRow, _ asked: Double, _ got: Double) -> String {
        let w = ControlWords.self
        if row.kind == "pv" { return w.format("Asked for %@, produced %@ on average.", w.format("a %@ cap", power(asked)), power(got)) }
        if abs(asked) < 100 { return w.format("Asked to stay idle, delivered %@ on average.", flow(row, got)) }
        return w.format("Asked for %@, delivered %@ on average.", flow(row, asked), sameWay(asked, got) ? power(got) : flow(row, got))
    }

    /// Whether `got` went the way `asked` did, or too little to say.
    static func sameWay(_ asked: Double, _ got: Double) -> Bool {
        abs(got) < 100 || (asked >= 0) == (got >= 0)
    }

    /// "1.1 kWh charge", "300 Wh discharge": the battery's energy by its sign.
    static func energyFlow(_ wh: Double) -> String {
        ControlWords.format(wh >= 0 ? "%@ charge" : "%@ discharge", NodeLive.energy(abs(wh)))
    }

    /// The device a source reads, as a noun with its article.
    static func sourceNoun(_ kind: String?) -> String {
        switch kind {
        case "meter": return ControlWords.text("the meter")
        case "inverter": return ControlWords.text("the inverter")
        case "battery": return ControlWords.text("the battery")
        case "charger", "ev": return ControlWords.text("the charger")
        case "vehicle": return ControlWords.text("the car")
        default: return ControlWords.text("the device")
        }
    }

    /// What a source is in a list: "meter", "inverter".
    static func sourceKind(_ kind: String) -> String {
        switch kind {
        case "meter": return "meter"
        case "inverter": return "inverter"
        case "battery": return "battery"
        case "charger", "ev": return "charger"
        case "vehicle": return "car"
        default: return "device"
        }
    }
}
