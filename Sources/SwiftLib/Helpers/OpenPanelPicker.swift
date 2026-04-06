import AppKit
import UniformTypeIdentifiers

enum OpenPanelPicker {
    @MainActor
    static func pickBibTeXFile() -> URL? {
        pickSingleFile(
            title: "导入 BibTeX",
            prompt: "导入",
            allowedContentTypes: [type(forExtension: "bib", fallback: .plainText)]
        )
    }

    @MainActor
    static func pickRISFile() -> URL? {
        pickSingleFile(
            title: "导入 RIS",
            prompt: "导入",
            allowedContentTypes: [type(forExtension: "ris", fallback: .plainText)]
        )
    }

    @MainActor
    static func pickCitationStyleFiles() -> [URL] {
        pickFiles(
            title: "导入引文样式",
            prompt: "导入",
            allowedContentTypes: [.xml, type(forExtension: "csl", fallback: .xml)]
        )
    }

    @MainActor
    static func pickPDFFile() -> URL? {
        pickSingleFile(
            title: "选择 PDF",
            prompt: "选择",
            allowedContentTypes: [.pdf]
        )
    }

    @MainActor
    private static func pickSingleFile(title: String, prompt: String, allowedContentTypes: [UTType]) -> URL? {
        let panel = configuredPanel(title: title, prompt: prompt, allowedContentTypes: allowedContentTypes)
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private static func pickFiles(title: String, prompt: String, allowedContentTypes: [UTType]) -> [URL] {
        let panel = configuredPanel(title: title, prompt: prompt, allowedContentTypes: allowedContentTypes)
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    private static func configuredPanel(title: String, prompt: String, allowedContentTypes: [UTType]) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.allowedContentTypes = allowedContentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        return panel
    }

    private static func type(forExtension pathExtension: String, fallback: UTType) -> UTType {
        UTType(filenameExtension: pathExtension) ?? fallback
    }
}
