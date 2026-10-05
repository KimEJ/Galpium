import AppKit
import GalpiumCore
import SwiftUI

@MainActor
final class EditorBridge {
  weak var textView: MarkdownTextView?
  var scrollView: NSScrollView?
  var identity = ""
  func insert(_ text: String) {
    textView?.insertText(
      text, replacementRange: textView?.selectedRange() ?? NSRange(location: NSNotFound, length: 0))
  }
  func format(_ kind: String) { textView?.format(kind) }
  func insertAtEnd(_ text: String) {
    guard let view = textView else { return }
    let selection = view.selectedRange()
    view.insertText(
      text, replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
    view.setSelectedRange(selection)
    view.scrollRangeToVisible(selection)
  }
}

final class MarkdownTextView: NSTextView {
  var filesDropped: (([URL]) -> Void)?
  var imagePasted: ((Data) -> Void)?
  override func paste(_ sender: Any?) {
    let board = NSPasteboard.general
    if let urls = board.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
    {
      filesDropped?(urls)
      return
    }
    if let data = board.data(forType: .png) {
      imagePasted?(data)
      return
    }
    if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    {
      imagePasted?(png)
      return
    }
    super.paste(sender)
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingPasteboard.canReadObject(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
      ? .copy : super.draggingEntered(sender)
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
    {
      filesDropped?(urls)
      return true
    }
    return super.performDragOperation(sender)
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
      if event.charactersIgnoringModifiers == "b" {
        format("bold")
        return true
      }
      if event.charactersIgnoringModifiers == "i" {
        format("italic")
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }
  func format(_ kind: String) {
    guard !hasMarkedText() else { return }
    var range = selectedRange()
    let ns = string as NSString
    let selection = ns.substring(with: range)
    var text: String
    var start = 0
    var length = 0
    switch kind {
    case "bold", "italic", "code":
      let marker = kind == "bold" ? "**" : kind == "italic" ? "*" : "`"
      let content = selection.isEmpty ? localized("텍스트") : selection
      text = marker + content + marker
      start = marker.utf16.count
      length = content.utf16.count
    case "link":
      let label =
        selection.isEmpty ? localized("링크 텍스트") : selection.replacingOccurrences(of: "]", with: "］")
      text = "[\(label)](https://)"
      start = (text as NSString).range(of: "https://").location
      length = 8
    case "table":
      text = localized("\n| 열 1 | 열 2 |\n| --- | --- |\n| 내용 | 내용 |\n| 내용 | 내용 |\n")
      start = 3
      length = localized("열 1").utf16.count
    default:
      range = ns.lineRange(for: range)
      let value = ns.substring(with: range)
      let prefix = kind == "heading" ? "## " : kind == "quote" ? "> " : "- "
      let endsInNewline = value.hasSuffix("\n")
      let lines = value.components(separatedBy: "\n")
      text =
        (endsInNewline ? Array(lines.dropLast()) : lines).map { prefix + $0 }.joined(
          separator: "\n") + (endsInNewline ? "\n" : "")
      length = text.utf16.count
    }
    insertText(text, replacementRange: range)
    setSelectedRange(NSRange(location: range.location + start, length: length))
    window?.makeFirstResponder(self)
  }
}

struct NativeEditor: NSViewRepresentable {
  @Binding var text: String
  let identity: String
  let bridge: EditorBridge
  var onChange: () -> Void
  var onFiles: ([URL]) -> Void
  var onImage: (Data) -> Void
  var onScroll: (CGFloat) -> Void
  var onOverflow: ((String) -> Void)? = nil

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = bridge.scrollView ?? NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = true
    scroll.backgroundColor = .textBackgroundColor
    let view = (scroll.documentView as? MarkdownTextView) ?? MarkdownTextView(frame: .zero)
    view.isRichText = false
    view.allowsUndo = true
    view.isEditable = true
    view.isSelectable = true
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.isAutomaticSpellingCorrectionEnabled = false
    view.isContinuousSpellCheckingEnabled = false
    view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    view.textColor = .textColor
    view.insertionPointColor = .controlAccentColor
    view.textContainerInset = NSSize(width: 18, height: 18)
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 7
    view.defaultParagraphStyle = style
    view.typingAttributes = [
      .font: view.font!, .foregroundColor: NSColor.textColor, .paragraphStyle: style,
    ]
    view.minSize = .zero
    view.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainer?.widthTracksTextView = true
    view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    view.delegate = context.coordinator
    if bridge.identity != identity {
      view.string = text
      view.undoManager?.removeAllActions()
      bridge.identity = identity
    }
    scroll.documentView = view
    bridge.scrollView = scroll
    view.registerForDraggedTypes([.fileURL])
    view.setAccessibilityLabel(localized("Markdown 본문"))
    view.setAccessibilityIdentifier("markdown-editor")
    view.filesDropped = onFiles
    view.imagePasted = onImage
    bridge.textView = view
    context.coordinator.identity = identity
    scroll.contentView.postsBoundsChangedNotifications = true
    context.coordinator.observer = NotificationLifetime(
      NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
      ) { [weak scroll, weak coordinator = context.coordinator] _ in
        MainActor.assumeIsolated {
          guard let scroll, let height = scroll.documentView?.bounds.height else { return }
          coordinator?.parent.onScroll(
            max(
              0,
              min(
                1,
                scroll.contentView.bounds.origin.y
                  / max(1, height - scroll.contentView.bounds.height))))
        }
      })
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? MarkdownTextView else { return }
    context.coordinator.parent = self
    view.filesDropped = onFiles
    view.imagePasted = onImage
    bridge.textView = view
    // Only programmatic replacements reset content. Never touch active IME or selection on a save/preview refresh.
    if bridge.identity != identity {
      view.string = text
      view.undoManager?.removeAllActions()
      view.setSelectedRange(NSRange(location: 0, length: 0))
      context.coordinator.identity = identity
      bridge.identity = identity
    } else if view.string != text && !view.hasMarkedText() {
      let selection = view.selectedRange()
      view.string = text
      view.setSelectedRange(
        NSRange(location: min(selection.location, view.string.utf16.count), length: 0))
    }
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: NativeEditor
    var identity = ""
    var observer: NotificationLifetime?
    init(_ parent: NativeEditor) { self.parent = parent }
    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
      parent.onChange()
    }
    func textView(
      _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      guard let replacementString else { return true }
      let text = (textView.string as NSString).replacingCharacters(
        in: affectedCharRange, with: replacementString)
      guard text.utf8.count <= 256 * 1024 else {
        parent.onOverflow?(localized("기기 초안은 최대 256 KiB입니다. 큰 자료는 원본 자료로 가져오세요."))
        return false
      }
      return true
    }
  }
}

final class NotificationLifetime: @unchecked Sendable {
  private let token: NSObjectProtocol
  init(_ token: NSObjectProtocol) { self.token = token }
  deinit { NotificationCenter.default.removeObserver(token) }
}

struct PreviewScrollFollower: NSViewRepresentable {
  let fraction: CGFloat
  let enabled: Bool
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    guard enabled else { return }
    DispatchQueue.main.async {
      guard let scroll = view.enclosingScrollView, let document = scroll.documentView else {
        return
      }
      let y = fraction * max(0, document.bounds.height - scroll.contentView.bounds.height)
      scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
  }
}
