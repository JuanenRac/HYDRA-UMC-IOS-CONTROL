import SwiftUI

struct ContentView: View {
  @EnvironmentObject var link: PhoneLink

  private func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }

  var body: some View {
    VStack(spacing: 6) {
      if !link.connected {
        Text(text("watch.waiting")).font(.footnote).multilineTextAlignment(.center)
      } else {
        Text(link.robotName.isEmpty ? text("watch.noJob") : link.robotName).font(.headline).lineLimit(1)
        Text(text("status.\(link.status)")).font(.footnote)
        if link.total > 0 {
          Text(String(format: text("step.of"), link.step, link.total)).font(.caption2)
        }
      }
      // STOP is always offered: a request that cannot go through says so below, it is never silently dropped.
      Button(action: { link.requestStop() }) {
        Text(text("stop.button")).font(.headline).frame(maxWidth: .infinity)
      }
      .tint(.red)
      .buttonStyle(.borderedProminent)
      if !link.stopResult.isEmpty {
        Text(text("watch.stop.\(link.stopResult)")).font(.caption2).multilineTextAlignment(.center)
      }
    }
    .padding(.horizontal, 4)
  }
}
