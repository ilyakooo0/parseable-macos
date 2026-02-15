import SwiftUI

struct TimeRangePicker: View {
    @Binding var option: QueryViewModel.TimeRangeOption
    @Binding var customStart: Date
    @Binding var customEnd: Date
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
        .popover(isPresented: $showCustomPicker) {
            VStack(spacing: 12) {
                Text("Custom Time Range")
                    .font(.headline)

                DatePicker("Start:", selection: $customStart)
                    .datePickerStyle(.field)
                DatePicker("End:", selection: $customEnd)
                    .datePickerStyle(.field)

                if customEnd < customStart {
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
                        showCustomPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
}
