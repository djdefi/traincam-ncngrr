import SwiftUI
import Combine

/// Displays an MJPEG stream from a URL by continuously fetching JPEG frames.
struct MJPEGStreamView: View {
    let url: URL
    @StateObject private var loader = MJPEGLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                        .accessibilityLabel("Live camera stream")

                    if loader.isStalled {
                        Color.black.opacity(0.6)
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                            Text("Stream stalled")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Button {
                                loader.start(url: url)
                            } label: {
                                Text("Reconnect")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 6)
                                    .background(Color.cyan.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Stream stalled. Reconnect button available.")
                    }
                }
            } else if loader.errorMessage != nil {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                        Text(loader.errorMessage ?? "Connection error")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        Button {
                            loader.start(url: url)
                        } label: {
                            Text("Retry")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                                .background(Color.cyan.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Stream error: \(loader.errorMessage ?? "Connection error")")
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Connecting...")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                .accessibilityLabel("Connecting to camera stream")
            }
        }
        .animation(.easeIn(duration: 0.2), value: loader.image != nil)
        .onAppear { loader.start(url: url) }
        .onDisappear { loader.stop() }
    }
}

@MainActor
final class MJPEGLoader: NSObject, ObservableObject {
    @Published var image: UIImage?
    @Published var errorMessage: String?
    @Published var isStalled = false

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private let jpegStart = Data([0xFF, 0xD8])
    private let jpegEnd = Data([0xFF, 0xD9])
    private var retryCount = 0
    private var stopped = false
    private var lastFrameTime: Date?
    private var watchdogTask: Task<Void, Never>?
    private var currentURL: URL?
    private static let maxRetries = 3
    private static let maxBufferSize = 2 * 1024 * 1024 // 2 MB
    private static let stallThreshold: TimeInterval = 10
    private static let autoRetryDelay: TimeInterval = 3

    func start(url: URL) {
        stop()
        stopped = false
        retryCount = 0
        errorMessage = nil
        isStalled = false
        lastFrameTime = nil
        currentURL = url
        connect(url: url)
        startWatchdog()
    }

    private func connect(url: URL) {
        guard !stopped else { return }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        stopped = true
        watchdogTask?.cancel()
        watchdogTask = nil
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        buffer = Data()
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, !self.stopped else { return }
                if let lastFrame = self.lastFrameTime,
                   Date().timeIntervalSince(lastFrame) >= Self.stallThreshold,
                   self.image != nil {
                    self.isStalled = true
                    // Auto-retry after showing indicator
                    try? await Task.sleep(for: .seconds(Self.autoRetryDelay))
                    guard !Task.isCancelled, !self.stopped, self.isStalled,
                          let url = self.currentURL else { return }
                    self.reconnect(url: url)
                }
            }
        }
    }

    private func reconnect(url: URL) {
        session?.invalidateAndCancel()
        session = nil
        buffer = Data()
        isStalled = false
        lastFrameTime = nil
        connect(url: url)
    }

    private func extractFrames() {
        while true {
            guard let startRange = buffer.range(of: jpegStart) else {
                buffer.removeAll()
                return
            }
            guard let endRange = buffer.range(of: jpegEnd, in: startRange.lowerBound..<buffer.endIndex) else {
                if startRange.lowerBound > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<startRange.lowerBound)
                }
                return
            }

            let frameEnd = endRange.upperBound
            let frameData = buffer.subdata(in: startRange.lowerBound..<frameEnd)
            buffer.removeSubrange(buffer.startIndex..<frameEnd)

            if let img = UIImage(data: frameData) {
                self.image = img
                self.lastFrameTime = Date()
                self.isStalled = false
            }
        }
    }
}

// MARK: - URLSessionDataDelegate

extension MJPEGLoader: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task { @MainActor [weak self] in
            self?.retryCount = 0
            self?.errorMessage = nil
            self?.lastFrameTime = Date()
        }
        completionHandler(.allow)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.buffer.append(data)
            // Cap buffer to prevent unbounded memory growth
            if self.buffer.count > Self.maxBufferSize {
                self.buffer.removeAll()
            }
            self.extractFrames()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task sessionTask: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            if let error = error as? NSError, error.code == NSURLErrorCancelled { return }

            self.retryCount += 1
            let msg = error?.localizedDescription ?? "Stream ended"
            print("[MJPEG] \(msg) (retry \(self.retryCount)/\(Self.maxRetries))")

            if self.retryCount > Self.maxRetries {
                self.errorMessage = "Camera unavailable"
                return
            }

            // Exponential backoff: 2s, 4s, 8s
            let delay = Double(1 << self.retryCount)
            if let url = sessionTask.originalRequest?.url {
                try? await Task.sleep(for: .seconds(delay))
                guard !self.stopped else { return }
                self.session?.invalidateAndCancel()
                self.session = nil
                self.buffer = Data()
                self.connect(url: url)
            }
        }
    }
}
