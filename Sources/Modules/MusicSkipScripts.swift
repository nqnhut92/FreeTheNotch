import Foundation

/// AppleScript for the previous and next buttons while Music is the now-playing app.
///
/// Music's own `next track` and `previous track` do nothing for a playlist another app has queued, so the song is
/// chosen by its place in the current playlist instead. Plain strings, so they can be tested without Music running.
enum MusicSkipScripts {
    /// A song that has played for longer than this restarts instead of going back, as in Music.
    static let restartThreshold: TimeInterval = 3

    /// What the previous button does after `elapsed` seconds of the song.
    enum PreviousAction: Equatable {
        case restart
        case previousSong
    }

    static func previousAction(elapsed: TimeInterval) -> PreviousAction {
        elapsed > restartThreshold ? .restart : .previousSong
    }

    /// Back to the start of the current song.
    static let restart = """
        tell application "Music" to set player position to 0
        """

    /// Plays the song `offset` places from the current one in the playlist Music is playing from (1 for the next
    /// song, -1 for the previous one). With shuffle on Music picks the song, so its own commands are used. At the
    /// start of the list, going back restarts the song; at either end the list wraps only while repeat is "all".
    static func skip(by offset: Int) -> String {
        let fallback = offset > 0 ? "next track" : "previous track"
        let beforeStart = offset > 0 ? "" : "set player position to 0\n                        return"
        return """
            tell application "Music"
                if shuffle enabled then
                    \(fallback)
                    return
                end if
                set thePlaylist to current playlist
                set total to count of tracks of thePlaylist
                set target to (index of current track) + (\(offset))
                if target < 1 or target > total then
                    if (song repeat as text) is not "all" or total is 0 then
                        \(beforeStart)
                        return
                    end if
                    if target < 1 then
                        set target to total
                    else
                        set target to 1
                    end if
                end if
                play track target of thePlaylist
            end tell
            """
    }
}
