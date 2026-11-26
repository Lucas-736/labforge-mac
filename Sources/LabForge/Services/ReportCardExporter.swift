import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Renders `ReportCardView` with `ImageRenderer` at `scale = 2.0` (1080 × 1440 PNG) and exports it.
@MainActor
enum ReportCardExporter {

    enum ExportError: LocalizedError {
        case renderFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "战报渲染失败，请重试。"
            case .writeFailed(let detail): return "保存战报失败：\(detail)"
            }
        }
    }

    static func pngData(snapshot: ReportCardSnapshot, variant: ReportCardVariant) -> Data? {
        let card = ReportCardView(snapshot: snapshot, variant: variant)
            .environment(\.colorScheme, variant == .dark ? .dark : .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(width: ReportCardView.size.width, height: ReportCardView.size.height)
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = ReportCardView.size // 72-dpi point size → 144-dpi @2x metadata
        return rep.representation(using: .png, properties: [:])
    }

    /// `LabForge-战报-YYYY-MM-DD.png`
    static func defaultFileName(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "LabForge-战报-%04d-%02d-%02d.png", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Writes to `~/Desktop`, appending ` 2`, ` 3`… if a file with the same name already exists.
    static func saveToDesktop(snapshot: ReportCardSnapshot, variant: ReportCardVariant) throws -> URL {
        guard let data = pngData(snapshot: snapshot, variant: variant) else { throw ExportError.renderFailed }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        let base = (defaultFileName(for: snapshot.date) as NSString).deletingPathExtension
        var url = desktop.appendingPathComponent("\(base).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appendingPathComponent("\(base) \(n).png")
            n += 1
        }
        do { try data.write(to: url, options: .atomic) } catch { throw ExportError.writeFailed(error.localizedDescription) }
        return url
    }

    /// Shows an `NSSavePanel`; returns `nil` when the user cancels.
    static func saveWithPanel(snapshot: ReportCardSnapshot, variant: ReportCardVariant) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出今日科研战报"
        panel.nameFieldStringValue = defaultFileName(for: snapshot.date)
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = pngData(snapshot: snapshot, variant: variant) else { throw ExportError.renderFailed }
        do { try data.write(to: url, options: .atomic) } catch { throw ExportError.writeFailed(error.localizedDescription) }
        return url
    }

    /// Copies both image representations to `NSPasteboard.general`.
    static func copyToPasteboard(snapshot: ReportCardSnapshot, variant: ReportCardVariant) throws {
        guard let png = pngData(snapshot: snapshot, variant: variant),
              let tiff = NSImage(data: png)?.tiffRepresentation else { throw ExportError.renderFailed }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else {
            throw ExportError.writeFailed("无法准备剪贴板图像")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ExportError.writeFailed("无法写入剪贴板") }
    }
}
