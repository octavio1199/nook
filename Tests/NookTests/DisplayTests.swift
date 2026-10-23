import AppKit
import Testing
@testable import Nook

@Suite struct DisplayChoiceTests {
    // Laptop (notch) on the left, external monitor with the menu bar on the right.
    private let laptop = ScreenInfo(id: "LAPTOP", name: "Built-in Retina Display", frame: NSRect(x: -1512, y: 0, width: 1512, height: 982), hasNotch: true, isMain: false)
    private let studio = ScreenInfo(id: "STUDIO", name: "Studio Display", frame: NSRect(x: 0, y: 0, width: 2560, height: 1440), hasNotch: false, isMain: true)
    private let side = ScreenInfo(id: "SIDE", name: "DELL U2720Q", frame: NSRect(x: 2560, y: 0, width: 1920, height: 1080), hasNotch: false, isMain: false)

    private var all: [ScreenInfo] { [studio, laptop, side] }

    @Test func automaticPrefersTheNotchThenTheMainDisplay() {
        #expect(ScreenChooser.choose(.automatic, screens: all, activePoint: nil) == 1)
        // Lid closed: no notch anywhere.
        #expect(ScreenChooser.choose(.automatic, screens: [studio, side], activePoint: nil) == 0)
        #expect(ScreenChooser.choose(.automatic, screens: [side, studio], activePoint: nil) == 1)
    }

    @Test func mainIsTheMenuBarDisplay() {
        #expect(ScreenChooser.choose(.main, screens: all, activePoint: nil) == 0)
        #expect(ScreenChooser.choose(.main, screens: [laptop], activePoint: nil) == 0)
    }

    @Test func aSpecificDisplayFallsBackWhileDisconnected() {
        #expect(ScreenChooser.choose(.display("SIDE"), screens: all, activePoint: nil) == 2)
        // Unplugged: the automatic display, and the saved choice itself is untouched.
        #expect(ScreenChooser.choose(.display("SIDE"), screens: [studio, laptop], activePoint: nil) == 1)
        #expect(ScreenChooser.choose(.display("SIDE"), screens: [studio], activePoint: nil) == 0)
    }

    @Test func activeDisplayUsesWhereTheUserIsWorking() {
        #expect(ScreenChooser.choose(.activeDisplay, screens: all, activePoint: NSPoint(x: 3000, y: 500)) == 2)
        #expect(ScreenChooser.choose(.activeDisplay, screens: all, activePoint: NSPoint(x: -100, y: 500)) == 1)
        // A point on the very top edge (y == maxY) still counts as that display.
        #expect(ScreenChooser.choose(.activeDisplay, screens: all, activePoint: NSPoint(x: 1000, y: 1440)) == 0)
        #expect(ScreenChooser.choose(.activeDisplay, screens: all, activePoint: nil) == 1)
    }

    @Test func noScreensNoChoice() {
        #expect(ScreenChooser.choose(.automatic, screens: [], activePoint: nil) == nil)
    }

    @Test func storageRoundTrips() {
        for choice in [DisplayChoice.automatic, .main, .activeDisplay, .display("37D8832A-2D66-02CA-B9F7-8F30A301B230")] {
            #expect(DisplayChoice(storageValue: choice.storageValue) == choice)
        }
        // The earlier "Follow the mouse" setting carries over as the active display.
        #expect(DisplayChoice(storageValue: "mouse") == .activeDisplay)
        #expect(DisplayChoice(storageValue: nil) == .automatic)
        #expect(DisplayChoice(storageValue: "display:") == .automatic)
        #expect(DisplayChoice(storageValue: "garbage") == .automatic)
    }

    @Test func settingPersists() {
        let defaults = UserDefaults(suiteName: "DisplayChoiceTests-\(UUID().uuidString)")!
        #expect(AppSettings(defaults: defaults).displayChoice == .automatic)
        AppSettings(defaults: defaults).displayChoice = .display("SIDE")
        #expect(AppSettings(defaults: defaults).displayChoice == .display("SIDE"))
    }

    @Test func liveActivityShowsWithoutANotchToo() {
        let focus = FocusTimer()
        let notch = NotchInteraction(
            settings: AppSettings(defaults: UserDefaults(suiteName: "DisplayChoiceTests-\(UUID().uuidString)")!),
            focus: focus, agenda: AgendaModel(), geometry: .placeholder, clock: ManualClock()
        )
        #expect(!notch.geometry.hasNotch)
        #expect(notch.liveActivity == nil)
        focus.startPomodoro(.with(id: "classic"), label: "Write report")
        #expect(notch.liveActivity == .focus)
        focus.stop()
    }

    @Test func clicksAndAppSwitchesMarkTheActiveDisplay() {
        let tracker = ActiveDisplayTracker()
        let t0 = Date()
        #expect(tracker.activePoint == nil)
        tracker.noteClick(at: NSPoint(x: 3000, y: 500), now: t0)
        // The activation that click caused (Finder, window on another screen) doesn't override it.
        tracker.noteActivation(frontWindow: NSRect(x: -1400, y: 100, width: 800, height: 600), now: t0.addingTimeInterval(0.1))
        #expect(tracker.activePoint == NSPoint(x: 3000, y: 500))
        // A later ⌘Tab moves it to the middle of that app's front window.
        tracker.noteActivation(frontWindow: NSRect(x: -1400, y: 100, width: 800, height: 600), now: t0.addingTimeInterval(5))
        #expect(tracker.activePoint == NSPoint(x: -1000, y: 400))
        #expect(ScreenChooser.choose(.activeDisplay, screens: all, activePoint: tracker.activePoint) == 1)
        // An app without windows changes nothing.
        tracker.noteActivation(frontWindow: nil, now: t0.addingTimeInterval(9))
        #expect(tracker.activePoint == NSPoint(x: -1000, y: 400))
    }
}
