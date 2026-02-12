import SwiftUI
import WebKit

/// Full-screen view of a single camera with stream + telemetry.
struct CameraDetailView: View {
    let camera: Camera
    @State private var isFullscreen = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Stream section — MJPEG for ESP32, WebRTC viewer for Pi
                    if camera.isPi {
                        piStreamSection
                    } else {
                        esp32StreamSection
                    }

                    // Telemetry (ESP32 only — Pi uses /status)
                    if !camera.isPi {
                        TelemetryView(camera: camera)
                    }

                    // Info section
                    infoSection
                }
            }
        }
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - ESP32 MJPEG Stream

    @ViewBuilder
    private var esp32StreamSection: some View {
        if let url = camera.streamURL {
            ZStack(alignment: .topLeading) {
                MJPEGStreamView(url: url)
                    .aspectRatio(4/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .onTapGesture { isFullscreen.toggle() }
                    .fullScreenCover(isPresented: $isFullscreen) {
                        FullscreenStreamView(url: url)
                    }
                    .accessibilityLabel("Live stream from \(camera.name)")
                    .accessibilityHint("Double tap to toggle fullscreen")

                liveBadge
            }

            Text("Tap stream for fullscreen")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.5))
                .padding(.top, 4)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Pi WebRTC Stream

    @ViewBuilder
    private var piStreamSection: some View {
        if let url = camera.playerURL {
            ZStack(alignment: .topLeading) {
                WebRTCViewerView(url: url)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .accessibilityLabel("Live WebRTC stream from \(camera.name)")

                liveBadge

                // Pi badge
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 8))
                    Text("WebRTC")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(.top, 10)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Shared Components

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6))
        .clipShape(Capsule())
        .padding(10)
        .accessibilityHidden(true)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAMERA INFO")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(1)

            VStack(spacing: 0) {
                InfoRow(label: "Hostname", value: camera.host)
                Divider().overlay(Color.white.opacity(0.05))
                InfoRow(label: "IP Address", value: camera.ip)
                Divider().overlay(Color.white.opacity(0.05))
                InfoRow(label: "Port", value: "\(camera.port)")
                Divider().overlay(Color.white.opacity(0.05))
                InfoRow(label: "Type", value: camera.cameraType.rawValue.uppercased())
                Divider().overlay(Color.white.opacity(0.05))
                InfoRow(label: "Discovery", value: camera.source.rawValue.uppercased())
            }
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

            // Quick links
            HStack(spacing: 10) {
                if let url = camera.telemetryURL {
                    Link(destination: url) {
                        Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.cyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.2), lineWidth: 0.5))
                    }
                    .accessibilityLabel("Open telemetry dashboard in browser")
                }
                if let url = camera.viewerURL {
                    Link(destination: url) {
                        Label("Viewer", systemImage: "play.rectangle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.cyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.2), lineWidth: 0.5))
                    }
                    .accessibilityLabel("Open WebRTC viewer in browser")
                }
                if let url = camera.statusURL {
                    Link(destination: url) {
                        Label("JSON", systemImage: "curlybraces")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.cyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.2), lineWidth: 0.5))
                    }
                    .accessibilityLabel("Open raw JSON status in browser")
                }
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera details")
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Fullscreen landscape stream view (MJPEG / ESP32).
struct FullscreenStreamView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MJPEGStreamView(url: url)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .accessibilityAction(.escape) { dismiss() }
        .accessibilityLabel("Fullscreen camera stream. Tap to exit.")
    }
}

/// Embedded WKWebView for Pi WebRTC stream via WHEP.
/// Loads the /player endpoint served by the Pi's discovery server.
struct WebRTCViewerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
