import ActivityKit
import SwiftUI
import WidgetKit

// The Live Activity of a running trajectory: the lock screen and the Dynamic Island. It only SHOWS a status that the app
// sends (robot, what it is doing, the step); it has no button and cannot move a robot. This is the source of the widget
// extension target "HydraLiveActivity"; it is not part of the Xcode project yet (the target has to be created in Xcode,
// sharing ios/Runner/HydraJobAttributes.swift and the strings of ios/HydraExtensions).

@main
struct HydraLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    HydraLiveActivityWidget()
  }
}

private func statusText(_ status: String) -> String {
  NSLocalizedString("status.\(status)", comment: "Status of the job")
}

private func stepText(_ state: HydraJobAttributes.ContentState) -> String? {
  guard state.total > 0, state.status == "running" || state.status == "paused" || state.status == "finished" else { return nil }
  return String(format: NSLocalizedString("step.of", comment: "Step 3 of 10"), state.step, state.total)
}

private func symbol(_ status: String) -> String {
  switch status {
  case "running": return "play.fill"
  case "paused": return "pause.fill"
  case "finished": return "checkmark.circle.fill"
  case "offline": return "wifi.slash"
  case "safeMode": return "exclamationmark.shield.fill"
  default: return "stop.fill"
  }
}

private struct ProgressBar: View {
  let state: HydraJobAttributes.ContentState
  var body: some View {
    if state.total > 0 {
      ProgressView(value: Double(min(state.step, state.total)), total: Double(state.total))
    }
  }
}

struct HydraLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: HydraJobAttributes.self) { context in
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Image(systemName: symbol(context.state.status))
          Text(context.state.robotName).font(.headline)
          Spacer()
          Text(statusText(context.state.status)).font(.subheadline)
        }
        if let step = stepText(context.state) { Text(step).font(.caption) }
        ProgressBar(state: context.state)
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: symbol(context.state.status))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(statusText(context.state.status)).font(.caption)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.robotName).font(.headline)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack {
            if let step = stepText(context.state) { Text(step).font(.caption) }
            ProgressBar(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: symbol(context.state.status))
      } compactTrailing: {
        if context.state.total > 0 { Text("\(context.state.step)/\(context.state.total)").font(.caption2) }
      } minimal: {
        Image(systemName: symbol(context.state.status))
      }
    }
  }
}
