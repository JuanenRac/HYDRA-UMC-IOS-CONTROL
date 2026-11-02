import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // The quick action of the app icon (long press on the home screen): the global stop.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let item = connectionOptions.shortcutItem, item.type == GlobalStopRequests.quickActionType {
      GlobalStopRequests.shared.request()
    }
    // A pairing link that launched the app (the camera read the QR code of the admin page of the server).
    for context in connectionOptions.urlContexts {
      PairingChannel.shared.receive(context.url)
    }
  }

  // A pairing link that arrives while the app is open.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      PairingChannel.shared.receive(context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    if shortcutItem.type == GlobalStopRequests.quickActionType {
      GlobalStopRequests.shared.request()
      completionHandler(true)
      return
    }
    super.windowScene(windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
  }
}
