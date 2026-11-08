import Foundation
import FTWShared
import Observation

/// What happened, from the box's own control journal: GET
/// /api/control/journal, the last 24 hours of warnings and alarms and the
/// notices the box sent. The control sheet asks when it opens and when the
/// stream's facts change while it is open; nothing else asks, and none of
/// it reaches lane 0 or the widgets. A box from before the journal answers
/// 404, and the sheet then shows nothing new.
@Observable
@MainActor
public final class ControlJournal {
    public enum Phase: Equatable, Sendable {
        /// Not read yet.
        case unknown
        case ready
        /// The box has no journal: older software.
        case oldBox
    }

    public private(set) var answer: JournalAnswer?
    public private(set) var phase = Phase.unknown
    /// The last read failed, with a sentence to show.
    public private(set) var problem: String?
    /// When the box last answered, by the phone clock.
    public private(set) var readAtMs: Double?

    /// Warnings and alarms only; the newest fifty of each.
    public nonisolated static let query = ["severity": "warning", "limit": "50"]

    @ObservationIgnored private unowned let site: SiteModel
    @ObservationIgnored private var generation = 0

    public init(site: SiteModel) {
        self.site = site
    }

    /// The box answers only over its own API, on a session that streams.
    public var canRead: Bool { site.session.phase == .streaming && site.hasPassthrough }

    /// Whether the sheet has a place for it: a box that serves its own API
    /// and has not said it lacks the journal.
    public var shown: Bool { site.hasPassthrough && phase != .oldBox }

    /// The lines to show, in the household's clock.
    public func entries(nowMs: Double? = nil) -> [JournalEntry] {
        guard let answer else { return [] }
        return ControlFeedback.happened(answer, sources: site.session.sources, zone: site.householdZone, nowMs: nowMs ?? site.scheduler.nowMs)
    }

    /// Asked by the control sheet.
    public func read() async {
        guard canRead, phase != .oldBox else { return }
        generation += 1
        let mine = generation
        do {
            let json = try await site.callBox(.get, "/api/control/journal", query: Self.query)
            guard mine == generation else { return }
            answer = JournalAnswer(json)
            phase = .ready
            problem = nil
            readAtMs = site.scheduler.nowMs
        } catch let e as BoxAPIError where e.status == 404 || e.code == "E_UNKNOWN_OP" {
            guard mine == generation else { return }
            phase = .oldBox
            answer = nil
            problem = nil
        } catch {
            guard mine == generation else { return }
            problem = ControlWords.text("Your box didn’t answer. Open this again to ask.")
        }
    }
}
