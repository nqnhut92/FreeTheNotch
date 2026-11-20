import Foundation
import Testing

struct MusicSkipScriptsTests {
    @Test(arguments: [
        (0.0, MusicSkipScripts.PreviousAction.previousSong), (3.0, .previousSong), (3.1, .restart), (120, .restart),
    ])
    func previousRestartsOnlyAfterTheFirstThreeSeconds(elapsed: Double, expected: MusicSkipScripts.PreviousAction) {
        #expect(MusicSkipScripts.previousAction(elapsed: elapsed) == expected)
    }

    @Test func skippingForwardChoosesTheSongByItsPlace() {
        let script = MusicSkipScripts.skip(by: 1)
        #expect(script.contains("(index of current track) + (1)"))
        #expect(script.contains("next track"))
        #expect(!script.contains("set player position to 0"))
    }

    @Test func skippingBackAtTheStartRestartsTheSong() {
        let script = MusicSkipScripts.skip(by: -1)
        #expect(script.contains("(index of current track) + (-1)"))
        #expect(script.contains("previous track"))
        #expect(script.contains("set player position to 0"))
    }
}
