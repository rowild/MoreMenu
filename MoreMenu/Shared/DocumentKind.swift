import Foundation

enum FileTypeCategory: String, CaseIterable {
    case core = "Core"
    case data = "Data"
    case web = "Web & App"
    case scripts = "Scripts"
}

/// Persistent identifiers and presentation metadata shared by the app and Finder extension.
enum DocumentKind: String, CaseIterable, Identifiable {
    case plainText
    case markdown
    case richText
    case json
    case yaml
    case toml
    case xml
    case csv
    case log
    case html
    case css
    case scss
    case javascript
    case jsx
    case typescript
    case tsx
    case vue
    case shellScript
    case python

    var id: String { rawValue }
    var title: String { metadata.title }
    var fileExtension: String { metadata.fileExtension }
    var menuTitle: String { metadata.menuTitle }
    var category: FileTypeCategory { metadata.category }
    var note: String { metadata.note }
    var defaultEnabled: Bool { category == .core }
    var symbolName: String {
        switch self {
        case .plainText: return "doc.plaintext"
        case .richText: return "doc.richtext"
        default: return "doc.text"
        }
    }

    var initialContents: Data {
        guard self == .richText else { return Data() }
        return Data(#"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs24 }"#.utf8)
    }

    private struct Metadata {
        let title: String
        let fileExtension: String
        let menuTitle: String
        let category: FileTypeCategory
        let note: String
    }

    private var metadata: Metadata {
        switch self {
        case .plainText:
            return Metadata(title: "Text", fileExtension: "txt", menuTitle: "New Textfile", category: .core, note: "Plain text documents")
        case .markdown:
            return Metadata(title: "Markdown", fileExtension: "md", menuTitle: "New Markdown File", category: .core, note: "Notes, docs, and README files")
        case .richText:
            return Metadata(title: "Rich Text", fileExtension: "rtf", menuTitle: "New Rich Text File", category: .core, note: "Formatted text for TextEdit and similar apps")
        case .json:
            return Metadata(title: "JSON", fileExtension: "json", menuTitle: "New JSON File", category: .data, note: "Configuration, API payloads, package metadata")
        case .yaml:
            return Metadata(title: "YAML", fileExtension: "yml", menuTitle: "New YAML File", category: .data, note: "CI files, manifests, infrastructure config")
        case .toml:
            return Metadata(title: "TOML", fileExtension: "toml", menuTitle: "New TOML File", category: .data, note: "Tooling config such as Cargo or uv")
        case .xml:
            return Metadata(title: "XML", fileExtension: "xml", menuTitle: "New XML File", category: .data, note: "Structured data and feed files")
        case .csv:
            return Metadata(title: "CSV", fileExtension: "csv", menuTitle: "New CSV File", category: .data, note: "Spreadsheet-style flat data")
        case .log:
            return Metadata(title: "Log", fileExtension: "log", menuTitle: "New Log File", category: .data, note: "Plain log output")
        case .html:
            return Metadata(title: "HTML", fileExtension: "html", menuTitle: "New HTML File", category: .web, note: "Web pages and Angular templates")
        case .css:
            return Metadata(title: "CSS", fileExtension: "css", menuTitle: "New CSS File", category: .web, note: "Stylesheets")
        case .scss:
            return Metadata(title: "SCSS", fileExtension: "scss", menuTitle: "New SCSS File", category: .web, note: "Sass styles used in Vue, React, and Angular projects")
        case .javascript:
            return Metadata(title: "JavaScript", fileExtension: "js", menuTitle: "New JavaScript File", category: .web, note: "Runtime and tooling scripts")
        case .jsx:
            return Metadata(title: "JSX", fileExtension: "jsx", menuTitle: "New JSX File", category: .web, note: "React components")
        case .typescript:
            return Metadata(title: "TypeScript", fileExtension: "ts", menuTitle: "New TypeScript File", category: .web, note: "Typed app and framework code")
        case .tsx:
            return Metadata(title: "TSX", fileExtension: "tsx", menuTitle: "New TSX File", category: .web, note: "Typed React components")
        case .vue:
            return Metadata(title: "Vue Single-File Component", fileExtension: "vue", menuTitle: "New Vue Component", category: .web, note: "Vue components")
        case .shellScript:
            return Metadata(title: "Shell Script", fileExtension: "sh", menuTitle: "New Shell Script", category: .scripts, note: "Shell commands and utility scripts")
        case .python:
            return Metadata(title: "Python", fileExtension: "py", menuTitle: "New Python File", category: .scripts, note: "Python scripts and tools")
        }
    }
}
