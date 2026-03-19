import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double
    let findTrigger: Int
    let printTrigger: Int
    let exportPDFTrigger: Int
    let tocScrollTarget: String

    /// WKWebView subclass that filters irrelevant context menu items.
    class ModsWebView: WKWebView {
        override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
            let removeSelectors: Set<String> = [
                "reload:", "goBack:", "goForward:",
                "openFrameInNewWindow:", "openLinkInNewWindow:",
            ]
            menu.items.removeAll { item in
                if let action = item.action {
                    return removeSelectors.contains(NSStringFromSelector(action))
                }
                return false
            }
            super.willOpenMenu(menu, with: event)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentMarkdown: String = ""
        var isInitialLoadDone = false
        var lastHTML: String = ""
        var pendingPostLoadJS: String = ""
        var lastFindTrigger: Int = 0
        var lastPrintTrigger: Int = 0
        var lastExportPDFTrigger: Int = 0
        var lastTOCTarget: String = ""

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Allow initial HTML string load and about:blank
            if navigationAction.navigationType == .other {
                return .allow
            }
            // All clicks open in default browser — never navigate inside WebView
            if let url = navigationAction.request.url,
               url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !pendingPostLoadJS.isEmpty {
                webView.evaluateJavaScript(pendingPostLoadJS)
                pendingPostLoadJS = ""
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if !lastHTML.isEmpty {
                webView.loadHTMLString(lastHTML, baseURL: nil)
            }
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = ModsWebView(frame: .zero, configuration: HTMLBuilder.webViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator
        context.coordinator.currentMarkdown = markdown
        context.coordinator.isInitialLoadDone = true
        context.coordinator.lastFindTrigger = findTrigger
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
        context.coordinator.lastHTML = html
        context.coordinator.pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel

        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown

            if context.coordinator.isInitialLoadDone {
                updateContentViaJS(webView: webView)
            } else {
                let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
                webView.loadHTMLString(HTMLBuilder.buildHTML(bodyHTML: bodyHTML), baseURL: nil)
                context.coordinator.isInitialLoadDone = true
            }
        }

        // Toggle find bar
        if context.coordinator.lastFindTrigger != findTrigger {
            context.coordinator.lastFindTrigger = findTrigger
            webView.evaluateJavaScript("window.__modsToggleFind();")
        }

        // Print
        if context.coordinator.lastPrintTrigger != printTrigger {
            context.coordinator.lastPrintTrigger = printTrigger
            webView.printOperation(with: .shared).runModal(for: webView.window ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
        }

        // Export PDF
        if context.coordinator.lastExportPDFTrigger != exportPDFTrigger {
            context.coordinator.lastExportPDFTrigger = exportPDFTrigger
            exportPDF(webView: webView)
        }

        // TOC scroll
        if context.coordinator.lastTOCTarget != tocScrollTarget && !tocScrollTarget.isEmpty {
            context.coordinator.lastTOCTarget = tocScrollTarget
            let escaped = tocScrollTarget.replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function() {
                var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for (var h of headings) {
                    if (h.textContent.trim() === '\(escaped)') {
                        h.scrollIntoView({ behavior: 'smooth', block: 'start' });
                        break;
                    }
                }
            })();
            """
            webView.evaluateJavaScript(js)
        }
    }

    private func exportPDF(webView: WKWebView) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (markdown.isEmpty ? "document" : URL(fileURLWithPath: "untitled").deletingPathExtension().lastPathComponent) + ".pdf"
        // Try to use the source filename
        if let name = webView.title, !name.isEmpty {
            panel.nameFieldStringValue = name.replacingOccurrences(of: ".md", with: "") + ".pdf"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        webView.createPDF { result in
            switch result {
            case .success(let data):
                try? data.write(to: url)
            case .failure:
                break
            }
        }
    }

    private func updateContentViaJS(webView: WKWebView) {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        var js = "document.getElementById('content').innerHTML = \(HTMLBuilder.jsonEncode(bodyHTML));\n"
        js += "window.scrollTo(0, 0);\n"
        js += HTMLBuilder.conditionalJS(for: bodyHTML)

        webView.evaluateJavaScript(js)
    }
}
