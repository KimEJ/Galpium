import AppKit
import SwiftUI

@MainActor
final class NavigationSwipePresentation: ObservableObject {
  @Published private(set) var amount: CGFloat = 0
  func update(_ amount: CGFloat) {
    self.amount = amount.isFinite ? min(1, max(-1, amount)) : 0
  }
  func reset() { if amount != 0 { amount = 0 } }
}

struct NavigationSwipeAnimation: ViewModifier {
  @ObservedObject var presentation: NavigationSwipePresentation

  func body(content: Content) -> some View {
    GeometryReader { geometry in
      let amount = presentation.amount
      let progress = abs(amount)
      let backward = amount > 0
      ZStack(alignment: backward ? .leading : .trailing) {
        Theme.field
        content
          .offset(x: amount * min(128, geometry.size.width * 0.22))
          .opacity(1 - progress * 0.08)
        if progress > 0 {
          Image(systemName: backward ? "chevron.left" : "chevron.right")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 36, height: 36)
            .background(Theme.paper, in: Circle())
            .padding(.horizontal, 14)
            .opacity(min(1, progress * 3))
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }.clipShape(RoundedRectangle(cornerRadius: 14))
    }
  }
}

struct NavigationGestures: NSViewRepresentable {
  var model: AppModel
  func makeNSView(context: Context) -> NavigationGestureView {
    let view = NavigationGestureView()
    view.navigator.model = model
    return view
  }
  func updateNSView(_ view: NavigationGestureView, context: Context) {
    view.navigator.model = model
  }
  static func dismantleNSView(_ view: NavigationGestureView, coordinator: ()) { view.detach() }
}

final class NavigationGestureView: NSView {
  let navigator = NavigationGestureResponder()
  private weak var installedWindow: NSWindow?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    detach()
    if let window {
      navigator.nextResponder = window.nextResponder
      window.nextResponder = navigator
      installedWindow = window
    }
  }
  func detach() {
    if let installedWindow, installedWindow.nextResponder === navigator {
      installedWindow.nextResponder = navigator.nextResponder
    }
    installedWindow = nil
    navigator.nextResponder = nil
    navigator.tracking = false
    navigator.model?.swipePresentation.reset()
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class NavigationGestureResponder: NSResponder {
  weak var model: AppModel?
  var tracking = false
  private var cancelled = false

  override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
    axis == .horizontal && NSEvent.isSwipeTrackingFromScrollEventsEnabled
      && (model?.canGoBack == true || model?.canGoForward == true)
  }
  override func swipe(with event: NSEvent) {
    withAnimation(.easeOut(duration: 0.16)) {
      if event.deltaX < 0 { model?.goBack() } else if event.deltaX > 0 { model?.goForward() }
    }
  }
  override func scrollWheel(with event: NSEvent) {
    guard !tracking, event.hasPreciseScrollingDeltas,
      NSEvent.isSwipeTrackingFromScrollEventsEnabled,
      event.phase.contains(.began) || event.phase.contains(.changed),
      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
      let model, model.canGoBack || model.canGoForward
    else {
      super.scrollWheel(with: event)
      return
    }
    // Scroll views forward only their horizontal edge gestures through this responder chain.
    let backSign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
    let negative = backSign < 0 ? model.canGoBack : model.canGoForward
    let positive = backSign > 0 ? model.canGoBack : model.canGoForward
    tracking = true
    cancelled = false
    model.swipePresentation.reset()
    event.trackSwipeEvent(
      options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: negative ? -1 : 0,
      max: positive ? 1 : 0
    ) { [weak self] amount, phase, complete, _ in
      self?.completeSwipe(amount: amount, phase: phase, complete: complete, backSign: backSign)
    }
  }
  func completeSwipe(amount: CGFloat, phase: NSEvent.Phase, complete: Bool, backSign: CGFloat) {
    guard tracking else { return }
    guard let model, !model.isEditing, !model.isBusy, !model.isRenamingAttachment else {
      tracking = false
      self.model?.swipePresentation.reset()
      return
    }
    model.swipePresentation.update(amount * backSign)
    if phase.contains(.cancelled) { cancelled = true }
    guard complete else { return }
    tracking = false
    defer {
      cancelled = false
      model.swipePresentation.reset()
    }
    guard !cancelled, abs(amount) >= 0.5 else { return }
    withAnimation(.easeOut(duration: 0.16)) {
      if amount * backSign > 0 { model.goBack() } else { model.goForward() }
    }
  }
}
