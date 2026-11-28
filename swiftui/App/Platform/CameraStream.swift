// HYDRA-UMC-IOS-CONTROL - the camera stream of the phone, with the same certificate rules as the requests and no redirect followed.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation
import HydraCore

@MainActor
struct PhoneCameraStreams: CameraStreamTransport {
    let trust: TrustDelegate

    func open(url: String, headers: [String: String], onEvent: @escaping @MainActor (CameraEvent) -> Void) -> LiveConnection {
        PhoneCameraStream(url: url, headers: headers, trust: trust, onEvent: onEvent)
    }
}

@MainActor
private final class PhoneCameraStream: LiveConnection {
    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let trust: TrustDelegate
        let events: AsyncStream<CameraEvent>.Continuation

        init(trust: TrustDelegate, events: AsyncStream<CameraEvent>.Continuation) {
            self.trust = trust
            self.events = events
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            trust.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            events.yield(.response((response as? HTTPURLResponse)?.statusCode ?? 0))
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            events.yield(.data(data))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            events.yield(.ended)
            events.finish()
        }
    }

    private var session: URLSession?
    private var reader: Task<Void, Never>?

    init(url: String, headers: [String: String], trust: TrustDelegate, onEvent: @escaping @MainActor (CameraEvent) -> Void) {
        var continuation: AsyncStream<CameraEvent>.Continuation!
        let stream = AsyncStream<CameraEvent> { continuation = $0 }
        reader = Task { @MainActor in
            for await event in stream {
                if Task.isCancelled { break }
                onEvent(event)
            }
        }
        guard let address = URL(string: url) else {
            continuation.yield(.ended)
            continuation.finish()
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 40
        let session = URLSession(configuration: configuration, delegate: Delegate(trust: trust, events: continuation), delegateQueue: nil)
        var request = URLRequest(url: address)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        session.dataTask(with: request).resume()
        self.session = session
    }

    func close() {
        reader?.cancel()
        reader = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
