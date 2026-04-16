//
//  ContentView.swift
//  MoreMenu
//
//  Created by Robert Wildling on 2026-04-07.
//

import AppKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("MoreMenu")
                .font(.title)
                .fontWeight(.bold)

            Text("This app is only the container for the Finder extension. The context-menu command is provided by MoreMenuExtension.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            Text("Finder adds commands for plain text, Markdown, and rich text files. The menu icons automatically adapt to light and dark mode.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Setup")
                    .font(.headline)

                StepView(number: 1, text: "Build and install MoreMenu.app.")
                StepView(number: 2, text: "Register and enable MoreMenuExtension.")
                StepView(number: 3, text: "Restart Finder.")
                StepView(number: 4, text: "Right-click in Finder and choose a new file type.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button("Open Extension Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions")!
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("No folder-access grant is required. File creation is handled directly by the Finder Sync extension inside your home folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 420)
    }
}

struct StepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
                .foregroundStyle(.white)

            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    ContentView()
}
