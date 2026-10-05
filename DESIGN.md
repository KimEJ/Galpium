# Galpium design conventions

Galpium is a native macOS tool for reading and maintaining a personal wiki.
Preserve the document-centered layout and familiar platform behavior.

- Use SwiftUI for the shell and AppKit/TextKit for editing, input composition,
  selection, clipboard and Undo. Reuse native menus, sheets and controls.
- Use macOS system typography and appearance-aware semantic surfaces. Keep code
  and diffs monospace; keep reading text legible and selectable.
- Use Galpium green for authored links, selections and actions. System controls
  retain their platform-owned focus, selection and disabled behavior.
- Keep the sidebar, document reader, original-material reader and editing panes
  visually consistent. A new feature should extend the incumbent hierarchy.
- Support the 900×620 minimum window and 1240×830 default size in light/dark.
  Preserve editor text, cursor, composition and Undo during layout changes.
- Translate interface text through the Korean/English/Japanese string tables.
  User documents and materials retain their original language.
- Name actions clearly, keep supporting metadata subordinate, and show errors
  beside the task or in the existing notice surface.

`Theme` in `Sources/GalpiumApp/MarkdownView.swift` owns the accent and surface
roles. Native platform semantics take precedence over web-style decoration.
