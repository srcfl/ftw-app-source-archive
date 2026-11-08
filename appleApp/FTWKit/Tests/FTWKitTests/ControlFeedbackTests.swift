import Foundation
import Testing
@testable import FTWDemo
@testable import FTWKit
import FTWShared

/// The control sheet says what the box's own page says. These follow the
/// box's web/control-feedback.test.mjs, case for case where they overlap.
@Suite struct ControlFeedbackTests {
    static let utc = TimeZone(identifier: "UTC")!

    /// The box's test row: a battery discharging 2.25 kW on the plan.
    func row(_ change: (inout ControlRow) -> Void = { _ in }) -> ControlRow {
        var r = ControlRow(driver: "bat", kind: "battery", mode: "planner_arbitrage", status: "following", reason: "power_observed", severity: "info", evidence: "measured")
        r.readingsFresh = true
        r.sentW = -2250
        r.requestedW = -2250
        r.actualW = -2249
        r.readbackW = -2250
        r.commandAtMs = 1
        r.observedAtMs = 2
        r.siteConfirmation = "device_response_unconfirmed"
        change(&r)
        return r
    }

    /// Every reason the box's page has words for, so none shows as a code.
    static let reasons = [
        "power_observed", "plan", "manual_hold", "pv_surplus", "idle", "solar_below_ceiling", "vehicle_complete",
        "vehicle_limit_completion", "vehicle_not_requesting", "waiting_response", "no_command", "not_connected",
        "no_plan_budget", "pv_surplus_pause", "wake_kick", "battery_full", "battery_nearly_full", "battery_nearly_empty",
        "core_limit", "fuse_limit", "fuse_cooldown", "charger_limit", "device_limit", "offered_current_lower",
        "power_below_target", "power_above_target", "power_wrong_direction", "no_power_response", "power_while_idle",
        "setpoint_changed", "device_fault", "telemetry_stale", "readings_lost", "command_failed", "command_unconfirmed",
        "default_failed", "response_unknown", "observe_only", "disabled", "device_control", "site_meter_stale",
        "site_phase_currents_stale", "import_limit", "load_balancer_limit", "charger_pilot_limit", "one_phase", "vehicle_declined",
    ]

    /// Why the site may not dispatch: the journal's dispatch line says it.
    static let dispatchReasons = [
        "site_meter_stale", "site_phase_currents_stale", "setup_measurement_only", "setup_restart_required",
        "setup_meter_identity_unconfirmed", "setup_meter_identity_changed",
    ]

    @Test func everyReasonHasATitleAndASentence() {
        for language in [AppWords.Language.en, .sv] {
            AppWords.$language.withValue(language) {
                for reason in Self.reasons {
                    let words = ControlFeedback.status(row { $0.reason = reason; $0.status = "waiting" }, zone: Self.utc)
                    #expect(!words.text.contains("cannot describe") && !words.text.contains("inte kan beskriva"), "\(reason)")
                    #expect(!words.title.isEmpty && words.title != ControlWords.text("Checking"), "\(reason)")
                    let shown = [words.title, words.text, words.proof, words.next].joined(separator: " ")
                    #expect(shown.range(of: #"_|undefined|NaN|null|%@"#, options: .regularExpression) == nil, "\(reason): \(shown)")
                }
                for reason in Self.dispatchReasons {
                    let text = ControlFeedback.sentence(ControlRow(driver: "", kind: "dispatch", status: "blocked", reason: reason, severity: "warning"), Self.utc)
                    #expect(!text.contains("cannot describe") && !text.contains("inte kan beskriva") && !text.contains("_"), "\(reason)")
                }
            }
        }
    }

    /// Reasons Core added since: the charger's load balancing and pilot
    /// (srcfl/ftw#1537, #1905), the hourly import limit, one phase, and a
    /// car that declined the offer (srcfl/ftw#1980). Each says what the
    /// box reported and no cause it did not.
    @Test func newerReasonsSayWhatCoreReported() {
        AppWords.$language.withValue(.en) {
            let balanced = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "load_balancer_limit"; $0.make = "Easee"
                $0.limitA = 10; $0.limitedBy = "load_balancer"; $0.requestedA = 16; $0.actualW = 6900 })
            #expect(balanced.title == "Limited by the charger’s load balancing")
            #expect(balanced.text == "Easee limits the charger to 10 A with its load balancing. FTW asked for 16 A; the car takes 6.9 kW.")
            #expect(balanced.next.contains("main fuse"))
            #expect(balanced.tone == .neutral)
            let unnamed = ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "load_balancer_limit"; $0.limitA = 10; $0.requestedA = 16; $0.actualW = 6900 })
            #expect(unnamed.text.hasPrefix("The charger’s load balancing limits it to 10 A."))

            let pilot = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "charger_pilot_limit"; $0.pilotA = 10; $0.requestedA = 16; $0.actualW = 6900 })
            #expect(pilot.title == "Limited by the charger")
            #expect(pilot.text == "The charger signals 10 A to the car, below the 16 A FTW asked for, and the car takes 6.9 kW. The charger does not say why.")

            let lets = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "offered_current_lower"; $0.severity = "warning"
                $0.limitA = 10; $0.offeredA = 16; $0.requestedA = 16 })
            #expect(lets.text == "The charger lets the car take 10 A, below the 16 A FTW asked for.")
            let offers = ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "offered_current_lower"; $0.limitA = 10; $0.offeredA = 8; $0.requestedA = 16 })
            #expect(offers.text == "The charger offers 8 A, below the 16 A FTW asked for.")

            let hour = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "import_limit"; $0.sentW = 3700 })
            #expect(hour.title == "Limited by the hourly import limit")
            #expect(hour.text == "FTW lowered the rate to 3.7 kW charge to keep this hour’s grid import within its limit.")
            #expect(!hour.text.contains("fuse"))
            let fuse = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "fuse_limit"; $0.sentW = 3700 })
            #expect(fuse.text == "FTW lowered the rate to 3.7 kW charge to protect the main fuse.")

            let phase = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "one_phase"; $0.chargingPhase = "L2"; $0.chargingPhaseMaxW = 3680 })
            #expect(phase.text == "The car charges on L2 only, at most 3.7 kW. FTW plans with what it takes.")
            #expect(ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "one_phase" }).text == "The car charges on one phase only. FTW plans with what it takes.")

            let declined = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "waiting"; $0.reason = "vehicle_declined"; $0.actualW = 0; $0.requestedW = 10350 })
            #expect(declined.title == "Car stopped charging")
            #expect(declined.text.contains("finished or paused"))
            #expect(!declined.text.contains("is full") && !declined.text.contains("reached its own"))
            #expect(declined.next == "Check the car’s charge limit and schedule.")
            #expect(declined.tone == .neutral)
            // Core's own stop for a car that stopped asking keeps its words.
            let stopped = ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "vehicle_not_requesting"; $0.actualW = 0; $0.sentW = 0 })
            #expect(stopped.title == "Car not taking power")
            #expect(stopped.next == "")

            let numbers = Dictionary(uniqueKeysWithValues: ControlFeedback.numbers(row { $0.kind = "ev"; $0.pilotA = 10; $0.dynamicLimitA = 16; $0.offeredA = 16
                $0.limitA = 10; $0.limitedBy = "load_balancer" }))
            #expect(numbers["Actual pilot current"] == "10 A")
            #expect(numbers["Dynamic current setting"] == "16 A")
            #expect(numbers["Reported current setting"] == nil)
            #expect(numbers["Load balancing allows"] == "10 A")
        }
        AppWords.$language.withValue(.sv) {
            #expect(ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "vehicle_declined" }).title == "Bilen slutade ladda")
            #expect(ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "one_phase" }).text == "Bilen laddar bara på en fas. FTW planerar med det den tar.")
        }
    }

    /// The box's row carries the charger's newer fields.
    @Test func readsTheChargersNewerFields() throws {
        let json = try JSON(parsing: Array(#"{"driver": "easee", "kind": "ev", "status": "limited", "reason": "load_balancer_limit", "pilot_a": 10, "dynamic_limit_a": 16, "limit_a": 10, "limited_by": "load_balancer", "make": "Easee", "charging_phase": "L1", "charging_phase_max_w": 3680}"#.utf8))
        let r = try #require(ControlRow(json))
        #expect(r.pilotA == 10 && r.dynamicLimitA == 16 && r.limitA == 10)
        #expect(r.limitedBy == "load_balancer" && r.make == "Easee")
        #expect(r.chargingPhase == "L1" && r.chargingPhaseMaxW == 3680)
    }

    @Test func theAnswerFollowsCore() {
        AppWords.$language.withValue(.en) {
            let following = ControlFeedback.status(row { $0.onPlan = true }, zone: Self.utc)
            #expect(following.title == "Following FTW")
            #expect(following.text == "Discharging 2.2 kW as planned.")
            #expect(following.proof == "Based on the battery’s own readings.")
            #expect(following.tone == .ok)

            let ignored = ControlFeedback.status(row { $0.status = "not_following"; $0.reason = "no_power_response"; $0.severity = "warning"; $0.sentW = 3000; $0.actualW = 0 }, zone: Self.utc)
            #expect(ignored.title == "Not following")
            #expect(ignored.text == "Asked for 3.0 kW charge, but it delivers no power.")
            #expect(ignored.next.contains("has not said why"))
            #expect(ignored.tone == .warning)

            let lost = ControlFeedback.status(row { $0.status = "no_contact"; $0.reason = "readings_lost"; $0.severity = "alarm"; $0.evidence = "accepted" }, zone: Self.utc)
            #expect(lost.title == "Lost control")
            #expect(lost.tone == .alarm)
            #expect(ControlFeedback.status(row(), live: false).tone == .stale)
        }
    }

    @Test func expectedLimitsStayCalmAndExplainThemselves() {
        AppWords.$language.withValue(.en) {
            let taper = ControlFeedback.status(row { $0.status = "limited"; $0.reason = "battery_nearly_full"; $0.sentW = 3000; $0.actualW = 900; $0.batterySoc = 0.98 })
            #expect(taper.title == "Battery nearly full")
            #expect(taper.text == "Taking 900 W of 3.0 kW at 98\u{00A0}%. A battery charges slower when it is nearly full.")
            #expect(taper.tone == .neutral)
            let full = ControlFeedback.status(row { $0.status = "limited"; $0.reason = "battery_full"; $0.sentW = 0; $0.actualW = 0; $0.batterySoc = 1; $0.chargeResumeSoc = 0.99 })
            #expect(full.text.contains("paused charging at 100\u{00A0}%. Charging resumes at 99\u{00A0}% or lower"))
            #expect(ControlFeedback.status(row { $0.kind = "ev"; $0.reason = "vehicle_complete"; $0.mode = "plan" }).title == "Car is full")
            let limit = ControlFeedback.status(row { $0.kind = "ev"; $0.status = "limited"; $0.reason = "device_limit"; $0.severity = "warning"; $0.deviceLimitA = 8; $0.requestedA = 16 })
            #expect(limit.text == "The charger’s own limit is 8 A, below the 16 A FTW asked for.")
        }
    }

    /// How FTW knows: sent, accepted, measured, confirmed, each with its
    /// value and state, and a confirmed change says what the meter saw.
    @Test func theReceiptWalksSentAcceptedMeasuredConfirmed() {
        AppWords.$language.withValue(.en) {
            let measured = ControlFeedback.receipt(row(), zone: Self.utc)
            #expect(measured.map(\.step) == ["Sent", "Accepted", "Measured", "Confirmed"])
            #expect(measured.map(\.state) == [.done, .done, .done, .wait])
            #expect(measured[1].value == "The battery reports target 2.3 kW discharge")
            #expect(measured[3].value == "Waits for the device’s measured response")

            var comparison = ControlRow.Comparison()
            comparison.deviceChangeW = -1800
            let confirmed = ControlFeedback.receipt(row { $0.evidence = "confirmed"; $0.confirmedAtMs = CarTextTests.t; $0.siteEvidence = comparison }, zone: Self.utc)
            #expect(confirmed.last?.state == .done)
            #expect(confirmed.last?.value == "The grid meter matched a 1.8 kW change · 10:00")

            let failed = ControlFeedback.receipt(row { $0.reason = "command_failed"; $0.evidence = "" })
            #expect(failed[1].state == .fail)
            #expect(failed[1].value == "Commands failing")

            // Asked differs from sent: the plan's wish shows first.
            let asked = ControlFeedback.receipt(row { $0.requestedW = -4000 })
            #expect(asked.first?.step == "Asked")
            #expect(asked.first?.value == "4.0 kW discharge · plan")

            let old = ControlFeedback.receipt(row(), live: false)
            #expect(old[2].value == "Not current")
            #expect(old[2].state == StepState.none)
        }
    }

    typealias StepState = ControlFeedback.StepState

    @Test func theSummaryCountsWhatNeedsAttention() {
        AppWords.$language.withValue(.en) {
            #expect(ControlFeedback.summary([row()]).title == "Yes, FTW is in control")
            #expect(ControlFeedback.summary([row { $0.severity = "warning" }, row()]).title == "1 device needs a look")
            #expect(ControlFeedback.summary([row { $0.severity = "alarm" }, row { $0.severity = "alarm" }]).tone == .alarm)
            #expect(ControlFeedback.summary([row { $0.status = "not_controlled" }]).title == "FTW controls no device right now")
            #expect(ControlFeedback.summary([row()], live: false).tone == .stale)
        }
    }

    /// Numbers say direction in words, never with a bare sign.
    @Test func theNumbersHaveNoMinusSign() {
        AppWords.$language.withValue(.en) {
            var e = ControlRow.Comparison()
            e.gridBeforeW = -1200
            e.gridAfterW = 600
            e.deviceChangeW = -1800
            e.gridChangeW = 1800
            e.samples = 8
            e.windowS = 12
            let numbers = ControlFeedback.numbers(row { $0.batterySoc = 0.62; $0.toleranceW = 150; $0.siteEvidence = e })
            let shown = Dictionary(uniqueKeysWithValues: numbers)
            #expect(shown["Battery charge"] == "62\u{00A0}%")
            #expect(shown["Grid before"] == "1.2 kW export")
            #expect(shown["Device change"] == "1.8 kW toward discharge")
            #expect(shown["Compared"] == "8 readings over 12 s")
            #expect(!numbers.contains { $0.1.contains("-") })
        }
    }

    @Test func inSwedish() {
        AppWords.$language.withValue(.sv) {
            let following = ControlFeedback.status(row { $0.onPlan = true })
            #expect(following.title == "Följer FTW")
            #expect(following.text == "Laddar ur 2,2 kW enligt planen.")
            #expect(following.proof == "Bygger på batteriets egna mätvärden.")
            #expect(ControlFeedback.status(row { $0.reason = "telemetry_stale" }).next == "Kontrollera anslutningen till batteriet.")
            #expect(ControlFeedback.receipt(row()).map(\.step) == ["Skickat", "Mottaget", "Mätt", "Bekräftat"])
        }
    }

    /// Every word the sheet hands to `ControlWords` has Swedish. Read from
    /// the source, so a new sentence without Swedish fails here.
    @Test func everyWordHasSwedish() throws {
        let source = try RepoFiles.read("appleApp/FTWKit/Sources/FTWKit/Format/ControlFeedback.swift")
            + RepoFiles.read("appleApp/FTWKit/Sources/FTWKit/Format/ControlJournal.swift")
            + RepoFiles.read("appleApp/FTWKit/Sources/FTWKit/State/ControlJournalModel.swift")
            + RepoFiles.read("appleApp/FTW/UI/ControlSheet.swift")
        let call = #/(?:ControlWords|\bw)\.(?:text|format)\("((?:[^"\\]|\\.)*)"/#
        var english = Set(source.matches(of: call).map { String($0.1) })
        english.formUnion(ControlFeedback.statusTitles.values)
        english.formUnion(ControlFeedback.reasonTitles.values)
        english.formUnion(ControlFeedback.confirmation.values.map(\.0))
        // Words picked by a ternary inside a call: the call only sees the first.
        english.formUnion(["%@ discharge", "%@ less solar", "%@ more charging", "%@ toward charge", "%@ import", "%@ toward import", "%@ more drawn",
                           "%@ device needs attention now", "%@ devices need attention now", "%@ device needs a look", "%@ devices need a look",
                           "producing", "idle", "charging", "discharging", "two minutes", "15 seconds", "no charging", "%@ export",
                           "%@ more solar", "%@ less charging", "%@ toward discharge", "%@ toward export", "%@ less drawn", "%@ charge",
                           "car charger", "meter", "battery", "solar", "charger", "device",
                           "Load balancing allows", "Charger lets the car take",
                           // The journal's lines.
                           "FTW is not in control", "FTW was not in control", "%@ is not reporting.", "%@ was not reporting.",
                           "Battery behind the plan", "Battery went the other way", "inverter", "car"])
        #expect(english.count > 120)
        for en in english.sorted() where !en.isEmpty {
            #expect(ControlWords.sv[en] != nil || NodeWords.sv[en] != nil || AppWords.sv[en] != nil, "no Swedish for \"\(en)\"")
        }
        for (en, sv) in ControlWords.sv {
            #expect(!sv.isEmpty)
            #expect(en.components(separatedBy: "%@").count == sv.components(separatedBy: "%@").count, "\(en)")
        }
    }

    /// The demo box answers with rows of the same shape as a real box.
    @MainActor
    @Test func theDemoBoxAnswersWithControlRows() async throws {
        let rig = DemoRig()
        rig.app.startDemo()
        let home = try #require(rig.app.home)
        await rig.run(3_000)
        let check = ControlCheck(site: home.site)
        #expect(check.canRead)
        let read = Task { await check.read() }
        await rig.run(1_000)
        await read.value
        #expect(check.rows.map(\.id) == ["sungrow:battery", "easee:ev"])
        #expect(check.live)
        AppWords.$language.withValue(.en) {
            #expect(ControlFeedback.summary(check.rows).title == "Yes, FTW is in control")
            #expect(!ControlFeedback.status(check.rows[0]).text.isEmpty)
        }
        // A new key only when something about control changed.
        let key = check.key
        await rig.run(5_000)
        #expect(check.key == key)
    }
}
