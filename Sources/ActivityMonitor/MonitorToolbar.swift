import AppKit
import SwiftUI

/// Match the native toolbar controls' visual height while leaving even space above and below.
enum MonitorTitlebarGeometry {
  static let slotHeight: CGFloat = 40
  static let surfaceHeight: CGFloat = 32
  static let metricButtonHeight: CGFloat = surfaceHeight - 8
}

/// Keep the familiar tab appearance while fitting the compact native title bar.
struct ToolbarMetricPicker: View {
  @Binding var metric: Metric
  let theme: MonitorTheme
  var compact = false

  var body: some View {
    MetricSwitcher(
      metric: $metric, theme: theme, compact: compact,
      controlHeight: MonitorTitlebarGeometry.metricButtonHeight
    )
    .frame(width: compact ? 210 : nil)
    .fixedSize()
    .frame(height: MonitorTitlebarGeometry.slotHeight, alignment: .center)
    .id(compact)
    .accessibilityIdentifier("monitor-metric-picker")
  }
}

/// A single surface extends behind native toolbar controls and the workspace.
struct MonitorWindowBackground: ViewModifier {
  let theme: MonitorTheme

  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      content
        .containerBackground(theme.window, for: .window)
        .toolbarBackground(.hidden, for: .windowToolbar)
    } else {
      content
        .toolbarBackground(theme.window, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }
  }
}

/// Budget the toolbar from the actual SwiftUI tab size and fixed-size actions.
/// Labels take priority over the optional brand mark and expanded action group.
@MainActor struct MonitorToolbarLayout {
  let width: CGFloat
  private static let labeledTabsWidth: CGFloat = {
    let view = NSHostingView(
      rootView:
        MetricSwitcher(
          metric: .constant(.cpu), theme: .init(dark: false),
          controlHeight: MonitorTitlebarGeometry.metricButtonHeight))
    return ceil(view.fittingSize.width)
  }()
  private let windowChrome: CGFloat = 128
  private let compactActions: CGFloat = 68
  private let expandedActions: CGFloat = 238
  private let brand: CGFloat = 40

  var showsLabels: Bool { width >= Self.labeledTabsWidth + windowChrome + compactActions }
  var showsBrand: Bool { width >= Self.labeledTabsWidth + windowChrome + compactActions + brand }
  var showsExpandedActions: Bool {
    width >= Self.labeledTabsWidth + windowChrome + expandedActions + brand
  }
}
