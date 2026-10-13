# Interface design

Galpium's interface centers on reading, editing and connecting documents. New
features should fit the native macOS navigation and preserve the current task.

## Layout and navigation

Use the sidebar for library destinations and the main area for the selected page
or material. Keep reading, editing and original-material views consistent in
spacing and hierarchy. Supporting metadata should remain secondary to content.

Make the full visible row respond to selection. Distinguish hover, selection and
keyboard focus without duplicating active indicators. Retain navigation history
when moving between pages and materials.

The default window is 1240 × 830 and the minimum content size is 900 × 620.
Layout changes must preserve editor text, cursor position, input composition and
Undo history.

## Native controls and editing

Use SwiftUI for application layout and AppKit/TextKit for editing. Prefer native
menus, sheets, keyboard shortcuts, text selection and clipboard behavior.
Avoid replacing platform-owned focus, selection or disabled states with custom
decoration.

## Typography and color

Use macOS system typography and semantic surfaces that adapt to light and dark
appearance. Reading text should be selectable; code and diffs use monospace.
Galpium green identifies authored links and custom actions.

`Theme` in `Sources/GalpiumApp/MarkdownView.swift` defines the shared accent and
surface roles. Extend these roles rather than adding isolated color values.

## Language and feedback

Interface strings come from the Korean, English and Japanese localization tables.
Documents, material names and other authored content retain their own language.

Name actions by their outcome. Keep routine feedback brief and place errors near
the task they affect or in the existing notice surface. Preserve unfinished work
when an operation fails or a revision conflict requires comparison.
