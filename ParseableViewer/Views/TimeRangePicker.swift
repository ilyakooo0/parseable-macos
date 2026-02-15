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

                HStack {
                    // Quick presets
                    Menu("Presets") {
                        Button("Last hour") {
                            customStart = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
                            customEnd = Date()
                        }
                        Button("Today") {
                            customStart = Calendar.current.startOfDay(for: Date())
                            customEnd = Date()
                        }
                        Button("Yesterday") {
                            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                            customStart = Calendar.current.startOfDay(for: yesterday)
                            customEnd = Calendar.current.startOfDay(for: Date())
                        }
                        Button("Last 7 days") {
                            customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                            customEnd = Date()
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
