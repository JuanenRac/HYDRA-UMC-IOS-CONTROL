import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// What the Live Activity of a running trajectory shows. The Runner target starts and updates it (LiveActivityBridge.swift);
/// the widget extension that draws it on the lock screen and in the Dynamic Island (ios/HydraLiveActivity) shares this file.
/// The words of the status are the ones of lib/util/live_activity_model.dart (SurfaceStatus).
@available(iOS 16.1, *)
struct HydraJobAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var robotName: String
    /// running, paused, finished, stopped, offline, safeMode or idle.
    var status: String
    /// The step being run, counted from 1 (0 when none), and the number of steps of the trajectory.
    var step: Int
    var total: Int
  }

  /// A fixed part is not needed: the robot name can change between jobs, so it lives in the content state.
  var title: String = "HYDRA-UMC"
}
#endif
