import Foundation
import Testing
import UserNotifications
@testable import Nook

@Suite struct SystemNotifierTests {
    @Test func policyDecisions() {
        let away = PresenceContext(screenLocked: true)
        let here = PresenceContext()
        #expect(!NotificationPolicyLogic.shouldPost(policy: .off, context: away, kind: .taskDue))
        #expect(NotificationPolicyLogic.shouldPost(policy: .always, context: here, kind: .taskDue))
        #expect(!NotificationPolicyLogic.shouldPost(policy: .always, context: here, kind: .info))
        #expect(!NotificationPolicyLogic.shouldPost(policy: .whenAway, context: here, kind: .taskDue))
        for context in [PresenceContext(screenLocked: true), PresenceContext(displaysAsleep: true),
                        PresenceContext(fullScreenOnNotchDisplay: true), PresenceContext(justWoke: true)] {
            #expect(NotificationPolicyLogic.shouldPost(policy: .whenAway, context: context, kind: .eventSoon))
        }
    }

    @Test func identifiersAreStableAndParse() {
        let id = UUID()
        let a = NotificationID.make(kind: .taskCheckIn, key: id.uuidString)
        #expect(a == NotificationID.make(kind: .taskCheckIn, key: id.uuidString))
        #expect(a != NotificationID.make(kind: .taskDue, key: id.uuidString))
        let parsed = NotificationID.parse(NotificationID.make(kind: .eventSoon, key: "abc.def|123"))
        #expect(parsed?.kind == "eventSoon")
        #expect(parsed?.key == "abc.def|123")
        #expect(NotificationID.parse("other.x.y") == nil)
    }

    @Test func categories() {
        #expect(NotificationID.category(kind: .taskCheckIn, hasTask: true, hasJoinURL: false, headline: "x") == "TASK_CHECKIN")
        #expect(NotificationID.category(kind: .breakFinished, hasTask: true, hasJoinURL: false, headline: "x") == "BREAK_OVER_CONTINUE")
        #expect(NotificationID.category(kind: .breakFinished, hasTask: false, hasJoinURL: false, headline: "x") == "BREAK_OVER")
        #expect(NotificationID.category(kind: .eventSoon, hasTask: false, hasJoinURL: false, headline: "x") == nil)
        #expect(NotificationID.category(kind: .eventSoon, hasTask: false, hasJoinURL: true, headline: "x") == "EVENT_SOON_JOIN")
        #expect(NotificationID.category(kind: .focusFinished, hasTask: false, hasJoinURL: false, headline: "Time's up") == nil)
    }

    @Test func actionsMapToCommands() {
        let id = UUID()
        let info = ["taskID": id.uuidString, "url": "https://meet.google.com/abc"]
        #expect(NotificationCommand.from(actionID: UNNotificationDefaultActionIdentifier, userInfo: [:]) == .open)
        #expect(NotificationCommand.from(actionID: "EXTEND_5", userInfo: [:]) == .extend(minutes: 5))
        #expect(NotificationCommand.from(actionID: "BREAK_THEN_CONTINUE", userInfo: [:]) == .breakThenContinue)
        #expect(NotificationCommand.from(actionID: "FINISH_TASK", userInfo: [:]) == .finishTask)
        #expect(NotificationCommand.from(actionID: "CONTINUE_TASK", userInfo: info) == .startNextFocus)
        #expect(NotificationCommand.from(actionID: "SNOOZE_TASK", userInfo: info) == .snoozeTask(id, minutes: 10))
        #expect(NotificationCommand.from(actionID: "SNOOZE_TASK", userInfo: [:]) == .none)
        #expect(NotificationCommand.from(actionID: "DONE_TASK", userInfo: info) == .toggleTask(id))
        #expect(NotificationCommand.from(actionID: "RESUME", userInfo: [:]) == .resume)
        #expect(NotificationCommand.from(actionID: "JOIN_EVENT", userInfo: info) == .join(URL(string: "https://meet.google.com/abc")!))
        #expect(NotificationCommand.from(actionID: "JOIN_EVENT", userInfo: ["url": "http://zoom.us/j/1"]) == .none)
        #expect(NotificationCommand.from(actionID: "JOIN_EVENT", userInfo: ["url": "file:///etc/passwd"]) == .none)
    }

    @Test func staleNotificationsAreDetected() {
        let id = UUID()
        let checkIn = NotificationID.make(kind: .taskCheckIn, key: id.uuidString)
        let due = NotificationID.make(kind: .taskDue, key: id.uuidString)
        var snapshot = NotificationSnapshot(awaitingCheckIn: true, dueTaskIDs: [id])
        #expect(!NotificationStaleness.isStale(identifier: checkIn, in: snapshot))
        #expect(!NotificationStaleness.isStale(identifier: due, in: snapshot))
        snapshot.awaitingCheckIn = false
        snapshot.dueTaskIDs = []
        #expect(NotificationStaleness.isStale(identifier: checkIn, in: snapshot))
        #expect(NotificationStaleness.isStale(identifier: due, in: snapshot))
        #expect(NotificationStaleness.isStale(identifier: NotificationID.make(kind: .breakFinished, key: nil), in: NotificationSnapshot(focusActive: true)))
        #expect(!NotificationStaleness.isStale(identifier: NotificationID.make(kind: .eventSoon, key: "e"), in: snapshot))
    }
}
