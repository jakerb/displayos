import Foundation
import Network
import ScreenCaptureKit
import VideoToolbox
import CoreMedia
import VirtualDisplayC

final class StreamingManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isStreaming = false
    @Published var status = "Select a receiver to create and stream a 2560 × 1440 virtual display."
    private var stream: SCStream?
    private var connection: NWConnection?
    private var compressionSession: VTCompressionSession?
    private let outputQueue = DispatchQueue(label: "com.displayos.capture", qos: .userInteractive)
    private let encodingQueue = DispatchQueue(label: "com.displayos.encode", qos: .userInteractive)

    func start(receiver: Receiver) {
        stop()
        status = "Creating virtual display…"
        Task { [weak self] in
            guard let self else { return }
            let displayName = "Display OS (\(receiver.name))"
            let displayID = DisplayOSCreateVirtualDisplay(displayName, 2560, 1440, 60)
            guard displayID != 0 else {
                status = "Virtual display creation failed. This macOS version does not expose the POC API."
                return
            }
            do {
                let endpoint = NWEndpoint.service(name: receiver.name, type: receiver.serviceType, domain: receiver.serviceDomain ?? "local.", interface: nil)
                let connection = NWConnection(to: endpoint, using: .tcp)
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    let message: String?
                    let shouldStop: Bool
                    switch state {
                    case .ready:
                        message = "Connected. Request Screen Recording permission when prompted."
                        shouldStop = false
                    case .failed(let error):
                        message = "Receiver connection failed: \(error.localizedDescription)"
                        shouldStop = true
                    default:
                        message = nil
                        shouldStop = false
                    }
                    Task { @MainActor [weak self] in
                        guard let self, let message else { return }
                        self.status = message
                        if shouldStop { self.stop() }
                    }
                }
                connection.start(queue: outputQueue)
                try self.configureEncoder()
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw StreamError.virtualDisplayNotVisible
                }
                let config = SCStreamConfiguration()
                config.width = 2560; config.height = 1440
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                let capture = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
                try await capture.startCapture()
                self.stream = capture
                self.isStreaming = true
                self.status = "Streaming 2560 × 1440 @ 60 Hz to \(receiver.name)"
            } catch {
                self.status = "Could not start stream: \(error.localizedDescription)"
                self.stop()
            }
        }
    }

    func stop() {
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
        connection?.cancel(); connection = nil
        if let session = compressionSession { VTCompressionSessionInvalidate(session) }
        compressionSession = nil
        DisplayOSDestroyVirtualDisplay()
        isStreaming = false
        if !status.hasPrefix("Could not") && !status.hasPrefix("Virtual") && !status.hasPrefix("Receiver") { status = "Select a receiver to create and stream a 2560 × 1440 virtual display." }
    }

    func removeDisplay() {
        stop()
        status = "Streaming display removed."
    }

    private func configureEncoder() throws {
        var session: VTCompressionSession?
        let result = VTCompressionSessionCreate(allocator: nil, width: 2560, height: 1440, codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: compressionCallback, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        guard result == noErr, let session else { throw StreamError.encoderUnavailable }
        compressionSession = session
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 60 as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 35_000_000 as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFTypeRef)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    nonisolated func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let image = sampleBuffer.imageBuffer, let session = compressionSession else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        VTCompressionSessionEncodeFrame(session, imageBuffer: image, presentationTimeStamp: time, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    }

    nonisolated func sendEncoded(_ sampleBuffer: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer), let connection else { return }
        var length = 0; var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr, let dataPointer else { return }
        let avcc = Data(bytes: dataPointer, count: length)
        var annexB = Self.parameterSets(from: sampleBuffer)
        annexB.append(Self.annexB(avcc))
        guard !annexB.isEmpty, annexB.count < 16_000_000 else { return }
        var size = UInt32(annexB.count).bigEndian
        var packet = Data(bytes: &size, count: 4); packet.append(annexB)
        connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    private static func annexB(_ avcc: Data) -> Data {
        var out = Data(); var index = 0
        while index + 4 <= avcc.count {
            let count = avcc[index..<(index + 4)].reduce(0) { ($0 << 8) | Int($1) }
            index += 4
            guard count > 0, index + count <= avcc.count else { return Data() }
            out.append(contentsOf: [0, 0, 0, 1]); out.append(avcc[index..<(index + count)]); index += count
        }
        return out
    }

    private static func parameterSets(from sampleBuffer: CMSampleBuffer) -> Data {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return Data() }
        var output = Data()
        for index in 0...1 {
            var pointer: UnsafePointer<UInt8>?; var length = 0; var count = 0; var nalLength: Int32 = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &length, parameterSetCountOut: &count, nalUnitHeaderLengthOut: &nalLength) == noErr, let pointer else { continue }
            output.append(contentsOf: [0, 0, 0, 1]); output.append(pointer, count: length)
        }
        return output
    }
}

extension StreamingManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        encode(sampleBuffer)
    }
}

private let compressionCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
    guard status == noErr, let refcon, let sampleBuffer else { return }
    let manager = Unmanaged<StreamingManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.sendEncoded(sampleBuffer)
}

enum StreamError: LocalizedError { case encoderUnavailable, virtualDisplayNotVisible
    var errorDescription: String? { switch self { case .encoderUnavailable: return "H.264 hardware encoder unavailable"; case .virtualDisplayNotVisible: return "macOS did not enumerate the virtual display" } }
}
