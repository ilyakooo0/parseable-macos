import AppKit
import SwiftUI

/// A syntax-highlighted SQL editor backed by NSTextView.
struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String

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
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isEditing = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            text.wrappedValue = textView.string
            applyHighlighting(to: textView)
            isEditing = false
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            textStorage.beginEditing()
            SQLSyntaxHighlighter.highlight(textView.string, in: textStorage, baseFont: SQLEditorView.editorFont)
            textStorage.endEditing()
        }
    }
}
