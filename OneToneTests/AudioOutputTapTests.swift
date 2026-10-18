//
//  AudioOutputTapTests.swift
//  OneToneTests
//

import AVFoundation
import XCTest
@testable import OneTone

/// レンダーブロックの中身（`AudioManager.render`）が、出力したサンプルをそのまま履歴に写すことを確かめる
final class AudioOutputTapTests: XCTestCase {
    private let sampleRate: Double = 48000
    private let frameCount = 512

    private var synthesizer: UnsafeMutablePointer<ToneSynthesizer>!
    private var outputSamples: SampleRingBuffer!
    private var pcmBuffer: AVAudioPCMBuffer!

    override func setUpWithError() throws {
        synthesizer = .allocate(capacity: 1)
        synthesizer.initialize(to: ToneSynthesizer(sampleRate: sampleRate, frequency: 440, volume: 0.5, waveform: .sine))
        outputSamples = SampleRingBuffer(capacity: 4096)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        pcmBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)))
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
    }

    override func tearDownWithError() throws {
        synthesizer.deinitialize(count: 1)
        synthesizer.deallocate()
        outputSamples.deallocate()
    }

    @discardableResult
    private func render(isPlaying: Bool) -> Bool {
        AudioManager.render(
            frameCount: frameCount,
            into: UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList),
            synthesizer: synthesizer,
            frequency: 440,
            volume: 0.5,
            waveform: .sine,
            isPlaying: isPlaying,
            outputSamples: outputSamples
        )
    }

    private func channel(_ index: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: pcmBuffer.floatChannelData![index], count: frameCount))
    }

    func testRenderCopiesOutputSamplesToHistory() {
        let isSilence = render(isPlaying: true)
        XCTAssertFalse(isSilence)
        XCTAssertEqual(outputSamples.totalWritten, frameCount)
        let history = outputSamples.latest(frameCount)
        // 履歴は出力と同じ値（どのチャンネルにも同じ値を書いている）
        XCTAssertEqual(history, channel(0))
        XCTAssertEqual(history, channel(1))
        XCTAssertGreaterThan(history.map(abs).max() ?? 0, 0.1)
    }

    func testRenderWritesSilenceToHistoryAfterFadeOut() {
        render(isPlaying: true)
        // 停止後、フェードアウトが終わるまで回す
        var isSilence = false
        for _ in 0..<100 where !isSilence {
            isSilence = render(isPlaying: false)
        }
        XCTAssertTrue(isSilence)
        render(isPlaying: false)
        XCTAssertEqual(outputSamples.latest(frameCount), Array(repeating: 0, count: frameCount))
        XCTAssertEqual(channel(0), Array(repeating: 0, count: frameCount))
    }

    func testRenderBeforePlayingIsSilentInHistory() {
        let isSilence = render(isPlaying: false)
        XCTAssertTrue(isSilence)
        XCTAssertEqual(outputSamples.totalWritten, frameCount)
        XCTAssertEqual(outputSamples.latest(frameCount), Array(repeating: 0, count: frameCount))
    }

    func testAudioManagerExposesOutputHistory() {
        // 出力デバイスの有無で実際に描画されるかは環境次第なので、読み出せる範囲だけを確かめる
        let manager = AudioManager()
        XCTAssertLessThanOrEqual(manager.latestOutputSamples(128).count, 128)
        XCTAssertTrue(manager.latestOutputSamples(128).allSatisfy { abs($0) <= 1 })
    }
}
