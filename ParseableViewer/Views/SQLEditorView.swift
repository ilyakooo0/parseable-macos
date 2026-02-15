import AppKit
import SwiftUI

/// A syntax-highlighted SQL editor backed by NSTextView with autocomplete support.
struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    var streamNames: [String] = []
    var schemaFields: [SchemaField] = []

    static let editorFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.font = Self.editorFont
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator

        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        context.coordinator.streamNames = streamNames
        context.coordinator.schemaFields = schemaFields

        // Only update when text changed externally (not from user typing)
        if textView.string != text && !context.coordinator.isEditing {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            let validRanges = selectedRanges.filter { NSMaxRange($0.rangeValue) <= textView.string.count }
            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, streamNames: streamNames, schemaFields: schemaFields)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isEditing = false
        var streamNames: [String]
        var schemaFields: [SchemaField]

        private let completionPopup = SQLCompletionPopup()
        /// Tracks whether we are inserting a completion so that `textDidChange`
        /// doesn't re-trigger the popup for the replacement.
        private var isInsertingCompletion = false

        init(text: Binding<String>, streamNames: [String], schemaFields: [SchemaField]) {
            self.text = text
            self.streamNames = streamNames
            self.schemaFields = schemaFields
            super.init()

            completionPopup.onAccept = { [weak self] item in
                self?.insertCompletion(item)
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            text.wrappedValue = textView.string
            applyHighlighting(to: textView)
            isEditing = false

            if !isInsertingCompletion {
                updateCompletions(for: textView)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard completionPopup.isVisible else { return false }

            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                completionPopup.moveSelectionDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                completionPopup.moveSelectionUp()
                return true
            case #selector(NSResponder.insertTab(_:)):
                completionPopup.acceptSelection()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                completionPopup.acceptSelection()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                completionPopup.hide()
                return true
            default:
                return false
            }
        }

        // MARK: - Completions

        private func updateCompletions(for textView: NSTextView) {
            let cursorPosition = textView.selectedRange().location
            let result = SQLCompletionProvider.completions(
                for: textView.string,
                cursorPosition: cursorPosition,
                streamNames: streamNames,
                schemaFields: schemaFields
            )

            guard !result.items.isEmpty else {
                completionPopup.hide()
                return
            }

            completionPopup.update(items: result.items)

            if !completionPopup.isVisible, let window = textView.window {
                let screenPoint = cursorScreenPoint(for: textView)
                completionPopup.show(at: screenPoint, in: window)
            }
        }

        private func insertCompletion(_ item: SQLCompletionItem) {
            // Find the text view — walk up from the popup's parent window
            guard let textView = findTextView() else { return }

            let cursorPosition = textView.selectedRange().location
            let nsText = textView.string as NSString

            // Find the prefix range to replace
            var wordStart = cursorPosition
            while wordStart > 0 {
                let ch = nsText.character(at: wordStart - 1)
                if SQLCompletionProvider.isWordCharacter(ch) {
                    wordStart -= 1
                } else {
                    break
                }
            }

            let replaceRange = NSRange(location: wordStart, length: cursorPosition - wordStart)

            isInsertingCompletion = true
            defer { isInsertingCompletion = false }

            if textView.shouldChangeText(in: replaceRange, replacementString: item.text) {
                textView.replaceCharacters(in: replaceRange, with: item.text)
                textView.didChangeText()
                // Update the binding
                isEditing = true
                text.wrappedValue = textView.string
                applyHighlighting(to: textView)
                isEditing = false
            }
        }

        private weak var lastTextView: NSTextView?

        private func findTextView() -> NSTextView? {
            lastTextView
        }

        /// Called from textDidChange / doCommandBy to record the active text view.
        func textDidBeginEditing(_ notification: Notification) {
            if let tv = notification.object as? NSTextView {
                lastTextView = tv
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let tv = notification.object as? NSTextView {
                lastTextView = tv
                // Hide popup when cursor moves without typing (e.g. mouse click)
                if !isEditing && !isInsertingCompletion {
                    completionPopup.hide()
                }
            }
        }

        // MARK: - Helpers

        func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            textStorage.beginEditing()
            SQLSyntaxHighlighter.highlight(textView.string, in: textStorage, baseFont: SQLEditorView.editorFont)
            textStorage.endEditing()
            // Keep track of the text view for completion insertion
            lastTextView = textView
        }

        private func cursorScreenPoint(for textView: NSTextView) -> NSPoint {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else {
                // Fallback: bottom-left of the text view
                let fallback = NSPoint(x: textView.frame.origin.x, y: textView.frame.maxY)
                let windowPoint = textView.convert(fallback, to: nil)
                return textView.window?.convertPoint(toScreen: windowPoint) ?? windowPoint
            }
            let cursorRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: cursorRange.location, length: 0),
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            // textContainerOrigin already accounts for textContainerInset
            let origin = textView.textContainerOrigin
            let viewPoint = NSPoint(
                x: rect.origin.x + origin.x,
                y: rect.maxY + origin.y + 2
            )
            let windowPoint = textView.convert(viewPoint, to: nil)
            return textView.window?.convertPoint(toScreen: windowPoint) ?? windowPoint
        }
    }
}
