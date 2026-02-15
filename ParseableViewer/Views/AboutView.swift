import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    private let repoURL = URL(string: "https://github.com/ilyakooo0/parseable-macos")!
    private let parseableURL = URL(string: "https://www.parseable.com")!

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Parseable Viewer")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("A native macOS log viewer for Parseable.")
                .font(.body)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("GitHub", destination: repoURL)
                Link("parseable.com", destination: parseableURL)
            }
            .font(.callout)
        }
        .padding(32)
        .frame(width: 320)
    }
}
