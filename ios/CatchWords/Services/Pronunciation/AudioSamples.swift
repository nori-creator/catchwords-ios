import AVFoundation
import Foundation

/// Sound turned into what the analysis reads: 16 kHz mono floats.
nonisolated enum AudioSamples {
    static var format: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: PitchTracker.sampleRate, channels: 1, interleaved: false)!
    }

    /// An audio file's bytes (the AI voice's MP3, a WAV) → samples. nil when it cannot be read.
    static func decode(_ data: Data) -> [Float]? {
        let isWave = data.prefix(4) == Data("RIFF".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pron-\(UUID().uuidString).\(isWave ? "wav" : "mp3")")
        do {
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try AVAudioFile(forReading: url)
            let length = AVAudioFrameCount(file.length)
            guard length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: length) else {
                return nil
            }
            try file.read(into: buffer)
            return convert(buffer)
        } catch {
            return nil
        }
    }

    /// A whole buffer converted at once.
    static func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        if buffer.format.sampleRate == PitchTracker.sampleRate, buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32, let ch = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let feed = Feed(buffer)
        var out: [Float] = []
        for _ in 0..<10_000 {
            guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return nil }
            var error: NSError?
            let status = converter.convert(to: chunk, error: &error) { _, outStatus in feed.next(outStatus, ending: true) }
            if let ch = chunk.floatChannelData, chunk.frameLength > 0 {
                out.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(chunk.frameLength)))
            }
            if status == .error { return nil }
            if status == .endOfStream || (status == .inputRanDry && chunk.frameLength == 0) { break }
        }
        return out
    }

    /// Hands a converter one buffer, then says the input ended (a file) or that nothing more is there yet (a microphone,
    /// whose converter keeps its state between buffers).
    nonisolated final class Feed: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private var given = false

        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>, ending: Bool) -> AVAudioBuffer? {
            if given {
                status.pointee = ending ? .endOfStream : .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
    }

    /// Samples → a 16-bit WAV file (a native's recording kept on the server, to analyse again when the analysis improves).
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let rate = UInt32(PitchTracker.sampleRate)
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            u16(UInt16(bitPattern: v))
        }
        return data
    }
}
