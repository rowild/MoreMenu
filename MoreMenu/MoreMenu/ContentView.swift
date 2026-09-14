//
//  ContentView.swift
//  MoreMenu
//
//  Created by Robert Wildling on 2026-04-07.
//

import AppKit
import SwiftUI
import FinderSync

private enum SettingsPane: String, CaseIterable, Identifiable {
    case finder
    case fileTypes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finder:
            return "Finder"
        case .fileTypes:
            return "File Types"
        }
    }

    var symbolName: String {
        switch self {
        case .finder:
            return "finder"
        case .fileTypes:
            return "doc.text"
        }
    }
}

struct ContentView: View {
    @State private var selectedPane: SettingsPane = .finder
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsPane.allCases, id: \.self) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        SidebarRow(
                            pane: pane,
                            isSelected: selectedPane == pane
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 250)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch selectedPane {
                case .finder:
                    FinderSettingsPane(isMenuEnabled: settings.isMenuEnabled) {
                        settings.setMenuEnabled($0)
                    }
                case .fileTypes:
                    FileTypesPane(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(minWidth: 920, minHeight: 640)
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.symbolName)
                .frame(width: 18)
            Text(pane.title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .foregroundStyle(.primary)
    }
}

private struct FinderSettingsPane: View {
    let isMenuEnabled: Bool
    let onSetMenuEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "Finder",
                subtitle: "Control whether MoreMenu shows its commands in Finder. macOS still owns the actual Finder extension switch."
            )

            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    "Enable MoreMenu in Finder",
                    isOn: Binding(
                        get: { isMenuEnabled },
                        set: onSetMenuEnabled
                    )
                )
                .toggleStyle(.switch)

                Button("Open Finder Extension Settings") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }

                Text("Use the macOS Finder Extensions settings if the menu does not appear at all. The switch above only hides or shows MoreMenu's own commands.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 0)
        }
    }
}

private struct FileTypesPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(
                    title: "File Types",
                    subtitle: "Choose which document types appear in Finder's first-level context menu."
                )

                ForEach(FileTypeCategory.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(category.rawValue)
                                .font(.headline)
                            Spacer()
                            Text("\(settings.enabledCount(in: category)) enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(DocumentKind.allCases.filter { $0.category == category }.enumerated()), id: \.element.id) { index, preference in
                                HStack(alignment: .top, spacing: 12) {
                                    Toggle("\(preference.title) (.\(preference.fileExtension))", isOn: settings.binding(for: preference))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()

                                    Image(systemName: preference.symbolName)
                                        .frame(width: 18)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(preference.title) (.\(preference.fileExtension))")
                                        Text(preference.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)

                                if index < DocumentKind.allCases.filter({ $0.category == category }).count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(18)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
