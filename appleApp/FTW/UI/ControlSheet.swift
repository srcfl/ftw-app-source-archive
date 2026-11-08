import FTWKit
import SwiftUI

/// What the status line opens: the box's own answer to "Are we in
/// control?", as plain list rows, with the same words as the box's page.
/// First the home as a whole and how its readings reach this phone, then one
/// section per device function: what it does, how FTW knows, and the
/// numbers behind it. Under what needs a look now, what happened: the
/// box's own record of the last day's warnings, kept after they passed.
/// When the box is out of reach, it opens on what to do.
struct ControlSheet: View {
    let app: AppModel
    let home: HomeModels
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast

    private var check: ControlCheck { home.control }
    private var journal: ControlJournal { home.journal }
    private var site: SiteModel { home.site }
    private func needsLook(_ row: ControlRow) -> Bool { row.severity == "warning" || row.severity == "alarm" }
    private var zone: TimeZone { site.session.box.flatMap { TimeZone(identifier: $0.tz) } ?? .current }

    var body: some View {
        NavigationStack {
            List {
                homeSection
                // What needs a look comes straight under the answer, before
                // the legend, so the sheet opens on why.
                ForEach(check.rows.filter(needsLook)) { row in
                    DeviceSection(row: row, live: check.live, zone: zone)
                }
                if let words = check.planWords {
                    Section {
                        PlanNowBlock(words: words)
                    } header: {
                        Text(ControlWords.text("Plan and now"))
                    }
                    .listRowBackground(Theme.raised)
                }
                // A warning that has passed stays here, as the box kept it.
                if journal.shown {
                    HappenedSection(journal: journal)
                }
                legend
                if let help = app.connectHelp {
                    Section {
                        Text(help)
                        RetryButton(app: app)
                        Button(L("Get this phone back in")) {
                            dismiss()
                            app.recovering = true
                        }
                    }
                    .listRowBackground(Theme.raised)
                }
                ForEach(check.rows.filter { !needsLook($0) }) { row in
                    DeviceSection(row: row, live: check.live, zone: zone)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle(ControlWords.text("Are we in control?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("control.close")
                }
            }
            .animation(Theme.spring, value: check.rows)
            .animation(Theme.spring, value: journal.answer)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Asked when the sheet opens, and again when the stream says
        // something that changes the answer. Never on a timer. The journal
        // is read after the answer, so the answer comes first.
        .task(id: check.key) {
            await check.read()
            await journal.read()
        }
    }

    /// What light, grey and pale mean, said once near the top, with the
    /// status line's own dots: the rule every screen keeps.
    private var legend: some View {
        Section {
            Label { Text(L("Lit and moving means live: your box read it just now.")) } icon: { StatusDot(lit: true) }
            Label { Text(L("Grey is the last reading your box sent. The status line says when.")) } icon: { StatusDot(lit: false) }
            Label { Text(L("Pale colour is the plan: what FTW means to do.")) } icon: {
                Capsule().fill(Theme.stores.opacity(Theme.plan(contrast))).frame(width: 10, height: 4).frame(width: StatusDot.side, height: StatusDot.side)
            }
        } header: {
            Text(L("Light means live"))
        }
        .font(.subheadline)
        .foregroundStyle(Theme.ink2)
        .listRowBackground(Theme.raised)
    }

    // Rows in the palette's raised role on the ground, as every sheet will
    // be.
    @ViewBuilder private var homeSection: some View {
        let answer = summary
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(answer.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    if let detail = answer.detail {
                        Text(detail).font(.subheadline).foregroundStyle(Theme.ink2)
                    }
                }
            } icon: {
                ToneMark(tone: answer.tone)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("control.summary")
            LabeledContent(L("Readings")) {
                Text(reach).foregroundStyle(Theme.ink2)
            }
            if let label = home.nodes.mode.label {
                LabeledContent(L("Mode"), value: label)
            }
            if let outcome = home.nodes.mode.outcome {
                ReceiptView(outcome: outcome)
            } else if let doubt = home.nodes.mode.doubt {
                Text(doubt).foregroundStyle(Theme.ink)
            }
            if site.session.needsUpdate {
                Text(L("This app is older than your box. Some things are hidden until it updates."))
                    .foregroundStyle(Theme.ink2)
            }
        } footer: {
            if let at = check.readAtMs, !check.rows.isEmpty {
                Text(NodeWords.format("Read from your box at %@.", AppWords.clock(at, zone: zone)))
            } else if let problem = check.problem {
                Text(problem)
            } else if !check.canRead, site.session.phase == .streaming {
                Text(L("Your box sends no more detail to this phone."))
            }
        }
        .listRowBackground(Theme.raised)
    }

    /// The whole home in one answer: the box's own summary once it has
    /// answered, else what the stream says.
    private var summary: (title: String, detail: String?, tone: ControlFeedback.Tone) {
        if check.readAtMs != nil, !check.rows.isEmpty {
            let s = ControlFeedback.summary(check.rows, live: check.live)
            return (s.title, nil, s.tone)
        }
        let a = InControl.answer(
            streaming: site.isLive,
            lastKnownMs: site.cachedAtMs ?? site.lastFrameAtMs,
            dispatchBlockedBy: site.session.dispatchBlockedBy,
            sources: site.session.sources,
            zone: zone
        )
        let tone: ControlFeedback.Tone
        switch a.tone {
        case .ok: tone = .ok
        case .warning: tone = .alarm
        case .neutral: tone = .neutral
        case .stale: tone = .stale
        }
        return (a.title, a.detail, tone)
    }

    /// How the readings reach this phone, in the band's words.
    private var reach: String {
        if app.isDemo { return L("Simulated on this phone") }
        let band = site.freshness(noCarrier: app.connectHelp != nil)
        return band.message
    }
}

/// One device function: Core's verdict in words, how FTW knows, and the
/// numbers for experts and support.
private struct DeviceSection: View {
    let row: ControlRow
    let live: Bool
    let zone: TimeZone

    var body: some View {
        let status = ControlFeedback.status(row, live: live, zone: zone)
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(status.text).foregroundStyle(Theme.ink)
                    if !status.proof.isEmpty {
                        Text(status.proof).font(.subheadline).foregroundStyle(Theme.ink2)
                    }
                    if !status.next.isEmpty {
                        Text(status.next).font(.subheadline).foregroundStyle(Theme.ink2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                ToneMark(tone: status.tone)
            }
            .accessibilityElement(children: .combine)
            DisclosureGroup(ControlWords.text("How FTW knows")) {
                ForEach(ControlFeedback.receipt(row, live: live, zone: zone)) { step in
                    StepRow(step: step)
                }
            }
            let numbers = ControlFeedback.numbers(row, live: live)
            if !numbers.isEmpty {
                DisclosureGroup(ControlWords.text("Numbers")) {
                    ForEach(numbers, id: \.0) { label, value in
                        LabeledContent(label, value: value)
                    }
                }
            }
        } header: {
            Text(verbatim: "\(row.driver) · \(ControlFeedback.kind(row))")
                .font(Theme.mono())
        }
        .listRowBackground(Theme.raised)
        .accessibilityIdentifier("control.device.\(row.id)")
    }
}

/// What happened: the journal's warnings and alarms of the last day and
/// the notices the box sent, newest first, in the live rows' words. The
/// newest few show; the rest are a tap away.
private struct HappenedSection: View {
    let journal: ControlJournal
    @State private var all = false

    static let first = 6

    var body: some View {
        let entries = journal.entries()
        Section {
            if journal.answer == nil {
                if journal.canRead, journal.problem == nil {
                    // The shape of the list while the box answers.
                    ForEach(0..<2, id: \.self) { _ in
                        HappenedRow(entry: Self.placeholder).redacted(reason: .placeholder)
                    }
                } else if let problem = journal.problem {
                    Text(problem).foregroundStyle(Theme.ink2)
                }
            } else if entries.isEmpty {
                Text(ControlWords.text("Nothing needed a look in the last 24 hours.")).foregroundStyle(Theme.ink2)
            } else {
                ForEach(all ? entries : Array(entries.prefix(Self.first))) { entry in
                    HappenedRow(entry: entry)
                }
                if !all, entries.count > Self.first {
                    Button(ControlWords.format("Show %@ more", String(entries.count - Self.first))) { all = true }
                        .accessibilityIdentifier("control.journal.more")
                }
            }
        } header: {
            Text(ControlWords.text("What happened"))
        } footer: {
            if journal.answer != nil {
                let more = journal.answer?.more == true || journal.answer?.noticesMore == true
                Text(ControlWords.text("From your box’s record of the last 24 hours.") + (more ? " " + ControlWords.text("Only the newest are shown.") : ""))
            }
        }
        .listRowBackground(Theme.raised)
        .accessibilityIdentifier("control.journal")
    }

    static let placeholder = JournalEntry(id: "placeholder", mark: .tone(.neutral), title: "Not following", name: nil,
                                          text: "Asked for 4.2 kW charge, delivered 1.2 kW on average.", when: "06:14–06:29", atMs: 0)
}

/// One line of what happened: when and what, as a mono kicker, then the
/// title and the sentence.
private struct HappenedRow: View {
    let entry: JournalEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ([entry.when] + (entry.name.map { [$0] } ?? [])).joined(separator: " · "))
                    .font(Theme.mono(.caption))
                    .foregroundStyle(Theme.ink2)
                Text(entry.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if !entry.text.isEmpty {
                    Text(entry.text).font(.subheadline).foregroundStyle(Theme.ink)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            switch entry.mark {
            case .tone(let tone): ToneMark(tone: tone, past: !entry.ongoing)
            case .noticeSent: Image(systemName: "bell").foregroundStyle(Theme.ink3).accessibilityHidden(true)
            case .noticeFailed: Image(systemName: "bell.slash").foregroundStyle(Theme.alarm).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One step of how FTW knows: sent, accepted, measured, confirmed.
private struct StepRow: View {
    let step: ControlFeedback.Step

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(step.step.uppercased())
                .font(Theme.mono(.caption, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .frame(minWidth: 92, alignment: .leading)
            Text(step.value)
                .font(.subheadline)
                .foregroundStyle(step.state == .none ? Theme.ink3 : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch step.state {
        case .done: return "checkmark"
        case .wait: return "circle.dotted"
        case .fail: return "xmark"
        case .none: return "minus"
        }
    }

    private var color: Color {
        switch step.state {
        case .done: return Theme.live
        case .wait, .none: return Theme.ink3
        case .fail: return Theme.alarm
        }
    }
}

/// The box's marks for a verdict, as symbols: a tick when following, a
/// triangle for a warning, a stop for an alarm. What has passed keeps its
/// mark in ink.
private struct ToneMark: View {
    let tone: ControlFeedback.Tone
    var past = false

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch tone {
        case .ok: return "checkmark.circle.fill"
        case .neutral: return "circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .alarm: return "exclamationmark.octagon.fill"
        case .stale: return "ellipsis.circle"
        }
    }

    private var color: Color {
        if past { return Theme.ink2 }
        switch tone {
        case .ok: return Theme.live
        case .warning, .alarm: return Theme.alarm
        case .neutral, .stale: return Theme.ink3
        }
    }
}

/// Builds the connection again, with Face ID if the key needs it. Pairing
/// again is a separate, later choice.
struct RetryButton: View {
    let app: AppModel
    @State private var trying = false

    var body: some View {
        Button {
            trying = true
            Task {
                await app.connect()
                trying = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(L("Try again"))
                if trying { ProgressView().controlSize(.small) }
            }
        }
        .disabled(trying)
        .accessibilityIdentifier("now.connect.retry")
    }
}

/// What the batteries do now beside what the plan said, and why. Not a
/// fault: FTW is in control, and the plan met a different day.
struct PlanNowBlock: View {
    let words: PlanNow.Words

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(words.nowLine).font(.headline).foregroundStyle(Theme.ink)
            Text(words.plan).font(.subheadline).foregroundStyle(Theme.ink2)
            Text(words.why).font(.subheadline).foregroundStyle(Theme.ink).padding(.top, 2)
            if !words.then.isEmpty {
                Text(words.then).font(.subheadline).foregroundStyle(Theme.ink)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.now")
    }
}
