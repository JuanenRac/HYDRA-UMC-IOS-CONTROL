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
