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
        #expect(ScreenChooser.choose(.automatic, screens: all, pointer: nil) == 1)
        // Lid closed: no notch anywhere.
        #expect(ScreenChooser.choose(.automatic, screens: [studio, side], pointer: nil) == 0)
        #expect(ScreenChooser.choose(.automatic, screens: [side, studio], pointer: nil) == 1)
    }

    @Test func mainIsTheMenuBarDisplay() {
        #expect(ScreenChooser.choose(.main, screens: all, pointer: nil) == 0)
        #expect(ScreenChooser.choose(.main, screens: [laptop], pointer: nil) == 0)
    }

    @Test func aSpecificDisplayFallsBackWhileDisconnected() {
        #expect(ScreenChooser.choose(.display("SIDE"), screens: all, pointer: nil) == 2)
        // Unplugged: the automatic display, and the saved choice itself is untouched.
        #expect(ScreenChooser.choose(.display("SIDE"), screens: [studio, laptop], pointer: nil) == 1)
        #expect(ScreenChooser.choose(.display("SIDE"), screens: [studio], pointer: nil) == 0)
    }

    @Test func followMouseUsesThePointersDisplay() {
        #expect(ScreenChooser.choose(.followMouse, screens: all, pointer: NSPoint(x: 3000, y: 500)) == 2)
        #expect(ScreenChooser.choose(.followMouse, screens: all, pointer: NSPoint(x: -100, y: 500)) == 1)
        // Hovering the very top edge (y == maxY) still counts as that display.
        #expect(ScreenChooser.choose(.followMouse, screens: all, pointer: NSPoint(x: 1000, y: 1440)) == 0)
        #expect(ScreenChooser.choose(.followMouse, screens: all, pointer: nil) == 1)
    }

    @Test func noScreensNoChoice() {
        #expect(ScreenChooser.choose(.automatic, screens: [], pointer: nil) == nil)
    }

    @Test func storageRoundTrips() {
        for choice in [DisplayChoice.automatic, .main, .followMouse, .display("37D8832A-2D66-02CA-B9F7-8F30A301B230")] {
            #expect(DisplayChoice(storageValue: choice.storageValue) == choice)
        }
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
}
