import SwiftUI

struct ContentView: View {
  @EnvironmentObject var link: PhoneLink

  private func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }

  var body: some View {
    VStack(spacing: 6) {
      // The alert of the phone stays until it is tapped; the watch only shows it, it never acts on it.
      if !link.alertText.isEmpty {
        Text(link.alertText)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .padding(4)
          .frame(maxWidth: .infinity)
          .background(link.alertSeverity == "CRITICAL" ? Color.red : (link.alertSeverity == "WARNING" ? Color.orange : Color.gray))
          .cornerRadius(6)
          .onTapGesture { link.dismissAlert() }
      }
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
