import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double
    let searchText: String
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
        var lastSearchText: String = ""
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
        context.coordinator.lastSearchText = searchText

        if !markdown.isEmpty {
            let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
            let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
            context.coordinator.lastHTML = html
            context.coordinator.pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
            context.coordinator.isInitialLoadDone = true
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel

        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown

            if context.coordinator.isInitialLoadDone && !markdown.isEmpty {
                updateContentViaJS(webView: webView)
            } else if !markdown.isEmpty {
                // First real content load — use loadHTMLString for full page setup
                let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
                let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
                context.coordinator.lastHTML = html
                context.coordinator.pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
                context.coordinator.isInitialLoadDone = true
                webView.loadHTMLString(html, baseURL: nil)
            }
        }

        // Search highlighting
        if context.coordinator.lastSearchText != searchText {
            context.coordinator.lastSearchText = searchText
            if searchText.count >= 2 {
                let encoded = HTMLBuilder.jsonEncode(searchText)
                webView.evaluateJavaScript("document.getElementById('__mods-find-input').value=\(encoded); window.__modsFindHighlight();")
            } else {
                webView.evaluateJavaScript("window.__modsClearHighlights(); document.getElementById('__mods-find-count').textContent='';")
            }
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
            let jsonTarget = HTMLBuilder.jsonEncode(tocScrollTarget)
            let js = """
            (function() {
                var target = \(jsonTarget);
                var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for (var h of headings) {
                    if (h.textContent.trim() === target) {
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
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url)
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Could not save PDF: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Could not create PDF: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func updateContentViaJS(webView: WKWebView) {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        // Save the nearest visible heading before updating content,
        // then restore scroll position to that heading after update.
        let js = """
        (function() {
            // Find the heading closest to the current viewport top
            var marker = null;
            var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
            for (var i = headings.length - 1; i >= 0; i--) {
                if (headings[i].getBoundingClientRect().top <= 10) {
                    marker = headings[i].textContent.trim();
                    break;
                }
            }
            // If no heading is above viewport, remember scroll ratio as fallback
            var scrollRatio = document.documentElement.scrollHeight > window.innerHeight
                ? window.scrollY / (document.documentElement.scrollHeight - window.innerHeight)
                : 0;

            // Update content
            document.getElementById('content').innerHTML = \(HTMLBuilder.jsonEncode(bodyHTML));
            \(HTMLBuilder.conditionalJS(for: bodyHTML))

            // Restore position
            if (marker) {
                var newHeadings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for (var h of newHeadings) {
                    if (h.textContent.trim() === marker) {
                        h.scrollIntoView({ block: 'start' });
                        return;
                    }
                }
            }
            // Fallback: restore by scroll ratio
            if (scrollRatio > 0) {
                var newMax = document.documentElement.scrollHeight - window.innerHeight;
                window.scrollTo(0, scrollRatio * newMax);
            }
        })();
        """

        webView.evaluateJavaScript(js)
    }
}
