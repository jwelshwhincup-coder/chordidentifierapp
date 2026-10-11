import Foundation
import Testing
@testable import chordid

struct DemoTests {
    private func freshDefaults() -> UserDefaults {
        let name = "DemoTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func wordingMatchesTheBrief() {
        let steps = DemoController.steps
        #expect(steps.count == 4)
        #expect(steps.map(\.title) == [
            "Tap any fret to place a finger.",
            "Tap above a string to switch it.",
            "The chord name appears straight away.",
            "Or tap the mic and play each string.",
        ])
        #expect(steps.map(\.body) == [
            "Tap it again to take it off.",
            "A circle means it rings open. A cross means it's muted or not played.",
            "Strum to hear it. Save to keep it.",
            "Go low to high. Tap Skip string for any you don't play.",
        ])
        #expect(steps.map(\.target) == [.fret(string: 1, fret: 3), .markerRow, .result, .mic])
    }

    @Test func scriptBuildsCMajor() {
        let shape = DemoController.shape(afterStep: 1)
        #expect(shape == ChordShape("x32010"))
        #expect(ChordEngine.identify(shape: shape, tuning: .standard).best?.displayName == "C major")
        // After step 1 only the fingers are down (open strings come in step 2).
        #expect(DemoController.shape(afterStep: 0) == ChordShape(frets: [nil, 3, 2, nil, 1, nil]))
        // The listening step starts from an empty board.
        #expect(DemoController.shape(afterStep: 3).isEmpty)
    }

    @Test func noStepUsesTheMicrophone() {
        // The only listening action is the scripted preview.
        let actions = DemoController.steps.flatMap(\.actions)
        #expect(actions.filter { $0 == .listeningPreview }.count == 1)
    }

    @Test func skippingClearsTheBoardAndRemembersItWasSeen() {
        let defaults = freshDefaults()
        let demo = DemoController(defaults: defaults)
        let model = ChordIDModel(defaults: freshDefaults())
        #expect(!demo.hasSeen)
        demo.start(model: model, listener: ListeningController(), player: GuitarPlayer())
        #expect(demo.isRunning)
        demo.advance()   // finish step 1 instantly → fingers placed
        #expect(model.shape == DemoController.shape(afterStep: 0))
        demo.skip()
        #expect(!demo.isRunning)
        #expect(model.shape.isEmpty)
        #expect(demo.hasSeen)
        #expect(defaults.bool(forKey: DemoController.seenKey))
    }

    @Test func replayRestoresTheUsersTuningCapoAndShape() {
        let demo = DemoController(defaults: freshDefaults())
        let model = ChordIDModel(defaults: freshDefaults())
        model.tuning = .dadgad
        model.setCapo(3)
        model.shape = ChordShape("x02210")!
        let listener = ListeningController()
        demo.start(model: model, listener: listener, player: GuitarPlayer())
        #expect(model.tuning == .standard)
        #expect(model.capo == 0)
        #expect(model.shape.isEmpty)
        // Jump through every step, including the scripted listening screen.
        demo.advance(); demo.advance(); demo.advance()
        #expect(demo.isLastStep)
        // The scripted listening screen never starts the microphone.
        listener.beginPreview(model: model)
        #expect(listener.isPreview && listener.phase == .listening && listener.session?.currentString == 0)
        demo.advance()   // tap on the last step closes the demo
        #expect(!demo.isRunning)
        #expect(!listener.isPreview)
        #expect(listener.phase == .idle)
        #expect(model.tuning == .dadgad)
        #expect(model.capo == 3)
        #expect(model.shape == ChordShape("x02210"))
    }

    @Test func startPlayingHandsOverToTheRealListener() {
        let demo = DemoController(defaults: freshDefaults())
        var handedOver = false
        demo.onStartPlaying = { handedOver = true }
        demo.start(model: ChordIDModel(defaults: freshDefaults()), listener: ListeningController(), player: GuitarPlayer())
        demo.startPlaying()
        #expect(handedOver)
        #expect(!demo.isRunning)
    }
}
