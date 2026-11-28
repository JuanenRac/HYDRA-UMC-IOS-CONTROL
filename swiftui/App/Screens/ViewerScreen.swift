// HYDRA-UMC-IOS-CONTROL - the 3D viewer of the server (STUDIO's) for one robot. Nothing it keeps survives it, it stays on the address of
// the server, and the round STOP is under it. It is not loaded while the app is in the background.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UIKit
import WebKit
import HydraCore

struct ViewerScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let robotId: Int?

    var body: some View {
        VStack(spacing: 0) {
            // the top right corner belongs to the STOP
            HStack(spacing: 12) {
                Button(model.tr("commonClose")) { dismiss() }.font(.system(size: 15, weight: .semibold)).accessibilityIdentifier("viewer-close")
                Text(model.tr("viewerTitle")).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer(minLength: CGFloat(StopLayout.width))
            }
            .padding(.horizontal, 14)
            .frame(height: CGFloat(StopLayout.headerHeight))
            if let robotId, let text = model.controller.viewerUrl(robotId: robotId), let url = URL(string: text) {
                if scenePhase == .background {
                    Color.black
                } else {
                    ViewerWebView(url: url, trust: model.viewerTrust)
                }
            } else {
                Text(model.tr("viewerNoRobot")).font(.system(size: 14)).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                RoundStopButton(model: model)
                Spacer()
                Text(model.tr("stopPhysical")).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .padding(14)
            .background(Theme.surface)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct ViewerWebView: UIViewRepresentable {
    let url: URL
    let trust: TrustDelegate?

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?
        var home: URL?
        var trust: TrustDelegate?

        // the page keeps the session: it never leaves the server it came from
        @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let to = navigationAction.request.url
            let stays = to?.scheme == "about" || (to?.scheme == home?.scheme && to?.host == home?.host && to?.port == home?.port)
            decisionHandler(stays ? .allow : .cancel)
        }

        @objc(webView:didReceiveAuthenticationChallenge:completionHandler:)
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            var answer: (URLSession.AuthChallengeDisposition, URLCredential?) = (.performDefaultHandling, nil)
            // the same certificate rules as the requests; the answer is given at once
            trust?.urlSession(URLSession.shared, didReceive: challenge) { answer = ($0, $1) }
            completionHandler(answer.0, answer.1)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.trust = trust
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        context.coordinator.home = url
        view.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.load(URLRequest(url: URL(string: "about:blank")!))
    }
}
