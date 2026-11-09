//
//  TutorialTrialPlayerTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class TutorialTrialPlayerTests: XCTestCase {
    /// 音を出さない AudioManager で鳴らし、その AudioManager も返す
    private func makePlayer(duration: TimeInterval = 60) -> (TutorialTrialPlayer, () -> AudioManager?) {
        var created: AudioManager?
        let player = TutorialTrialPlayer(duration: duration) {
            let manager = AudioManager(startsEngine: false)
            created = manager
            return manager
        }
        return (player, { created })
    }

    private let a440 = TutorialTrialPlayer.Sound(frequency: 440, waveform: .sine)
    private let square = TutorialTrialPlayer.Sound(frequency: 440, waveform: .square)

    func testTrialIsQuietAndShort() {
        XCTAssertGreaterThan(TutorialTrialPlayer.volume, 0)
        XCTAssertLessThan(TutorialTrialPlayer.volume, 0.5, "メイン画面の既定（50%）より低くする")
        XCTAssertGreaterThanOrEqual(TutorialTrialPlayer.duration, 1)
        XCTAssertLessThanOrEqual(TutorialTrialPlayer.duration, 5, "数秒で止める")
    }

    func testDoesNotCreateAudioUntilPlayed() {
        let (player, audio) = makePlayer()
        XCTAssertNil(player.playing)
        player.stop()
        XCTAssertNil(audio(), "試聴を押すまで AudioManager を作らない")
    }

    func testPlaysAtTrialVolumeWithSelectedWaveform() throws {
        let (player, audio) = makePlayer()
        player.play(square)

        let manager = try XCTUnwrap(audio())
        XCTAssertEqual(player.playing, square)
        XCTAssertTrue(player.isAudioPlaying)
        XCTAssertEqual(manager.currentFrequency, 440)
        XCTAssertEqual(manager.currentWaveform, .square)
        XCTAssertEqual(manager.currentVolume, TutorialTrialPlayer.volume)
    }

    func testToggleSameSoundStops() throws {
        let (player, audio) = makePlayer()
        player.toggle(a440)
        player.toggle(a440)
        XCTAssertNil(player.playing)
        XCTAssertFalse(try XCTUnwrap(audio()).isPlaying)
    }

    func testPlayingAnotherSoundReplacesPrevious() throws {
        let (player, audio) = makePlayer()
        player.toggle(a440)
        player.toggle(square)
        XCTAssertEqual(player.playing, square)
        XCTAssertEqual(try XCTUnwrap(audio()).currentWaveform, .square)
    }

    func testStopsAutomaticallyAfterDuration() throws {
        let (player, audio) = makePlayer(duration: 0.05)
        player.play(a440)

        let stopped = expectation(description: "自動で止まる")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 2)
        XCTAssertNil(player.playing)
        XCTAssertFalse(try XCTUnwrap(audio()).isPlaying)
    }

    func testEarlierAutoStopDoesNotCutOffNextSound() {
        // 前の音の自動停止が、あとから鳴らした音を途中で止めないこと
        let (player, _) = makePlayer(duration: 0.2)
        player.play(a440)

        let replaced = expectation(description: "途中で別の音に替える")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            player.play(self.square)
            replaced.fulfill()
        }
        wait(for: [replaced], timeout: 2)

        let checked = expectation(description: "前の音の停止予定を過ぎる")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            checked.fulfill()
        }
        wait(for: [checked], timeout: 2)
        XCTAssertEqual(player.playing, square)
    }

    func testDoesNotTouchMainScreenAudio() {
        // メイン画面の AudioManager とは別のインスタンスで鳴らすので、ユーザーの設定と再生状態はそのまま
        let main = AudioManager(startsEngine: false)
        main.updateVolume(0.9)
        main.updateWaveform(.sawtooth)
        main.updateFrequency(1000)

        let (player, _) = makePlayer()
        player.play(square)
        player.stop()

        XCTAssertFalse(main.isPlaying)
        XCTAssertEqual(main.currentVolume, 0.9)
        XCTAssertEqual(main.currentWaveform, .sawtooth)
        XCTAssertEqual(main.currentFrequency, 1000)
    }

    func testTrialSoundsPerPage() {
        XCTAssertEqual(TutorialTrial.tone(frequency: 440).sounds, [a440])
        let waveformSounds = TutorialTrial.waveforms(frequency: 440).sounds
        XCTAssertEqual(waveformSounds.map(\.waveform), Waveform.allCases)
        XCTAssertTrue(waveformSounds.allSatisfy { $0.frequency == 440 })
    }
}
