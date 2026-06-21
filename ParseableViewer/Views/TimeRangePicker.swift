import SwiftUI

struct TimeRangePicker: View {
    @Binding var option: QueryViewModel.TimeRangeOption
    @Binding var customStart: Date
    @Binding var customEnd: Date
    var onCommit: (() -> Void)?
    @State private var showCustomPicker = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)

            Picker("Time Range", selection: $option) {
                ForEach(QueryViewModel.TimeRangeOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .frame(width: 180)
            .onChange(of: option) { _, newValue in
                if newValue == .custom {
                    showCustomPicker = true
                }
            }

            if option == .custom {
                Button("Set Range...") {
                    showCustomPicker = true
                }
                .font(.caption)
            }
        }
        .onChange(of: showCustomPicker) { _, isShown in
            // Dismissing the popover by clicking outside bypasses the "Done"
            // button's `customEnd > customStart` validation, which could leave an
            // inverted or zero-width range selected (the menu already set
            // `option == .custom`). Sanitize on close so a backwards range can
            // never reach a query.
            guard !isShown else { return }
            if customEnd <= customStart {
                customEnd = customStart.addingTimeInterval(3600)
            }
            // Commit on *every* close path, not just the "Done" button. Closing
            // the popover by clicking outside is the common dismissal gesture;
            // without this the picker reads "Custom" while results still reflect
            // the previously selected preset, since QueryView only re-queries on
            // `timeRangeOption` changes (which it skips for `.custom`) — never on
            // the custom dates. Done sets `showCustomPicker = false` and lets this
            // handler do the single commit, so there's no double-query.
            if option == .custom {
                onCommit?()
            }
        }
        .popover(isPresented: $showCustomPicker) {
            VStack(spacing: 12) {
                Text("Custom Time Range")
                    .font(.headline)

                DatePicker("Start:", selection: $customStart)
                    .datePickerStyle(.field)
                DatePicker("End:", selection: $customEnd)
                    .datePickerStyle(.field)

                if customEnd <= customStart {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("End date must be after start date")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                HStack {
                    // Quick presets
                    Menu("Presets") {
                        Button("Last hour") {
                            let now = Date()
                            customStart = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now.addingTimeInterval(-3600)
                            customEnd = now
                        }
                        Button("Today") {
                            customStart = Calendar.current.startOfDay(for: Date())
                            customEnd = Date()
                        }
                        Button("Yesterday") {
                            let now = Date()
                            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86400)
                            customStart = Calendar.current.startOfDay(for: yesterday)
                            customEnd = Calendar.current.startOfDay(for: now)
                        }
                        Button("Last 7 days") {
                            let now = Date()
                            customStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-604800)
                            customEnd = now
                        }
                    }

                    Spacer()

                    Button("Done") {
                        // Just close — the `showCustomPicker` change handler is the
                        // single commit point for all close paths (Done + click-out).
                        showCustomPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customEnd <= customStart)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
}
