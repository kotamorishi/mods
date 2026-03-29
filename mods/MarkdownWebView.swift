import SwiftUI
import WebKit

struct SearchState {
    var text: String = ""
    var addTrigger: Int = 0
    var removeTerm: String = ""
    var removeTrigger: Int = 0
    var clearTrigger: Int = 0
    var scrollToNextTerm: String = ""
    var scrollToNextTrigger: Int = 0
    var scrollToPrevTerm: String = ""
    var scrollToPrevTrigger: Int = 0
    var pushTrigger: Int = 0
    var popTrigger: Int = 0
    var restoreIndex: Int = 0
    var restoreTrigger: Int = 0
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var lastNavigatedTerm: String = ""
    var previewText: String = ""
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double
    let search: SearchState
    @Binding var activeSearchTerms: [(term: String, slot: Int, count: Int, current: Int)]
    @Binding var searchStack: [[String]]
    let printTrigger: Int
    let exportPDFTrigger: Int
    let tocScrollTarget: String

    /// WKWebView subclass that intercepts drag registration and handles file drops.
    class ModsWebView: WKWebView {
        // Override registerForDraggedTypes to ensure file URL drops always work.
        // WKWebView's internal subviews call this to register their own types;
        // by overriding, we control what actually gets registered.
        override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
            var types = Set(newTypes)
            types.insert(.fileURL)
            super.registerForDraggedTypes(Array(types))
        }

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

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
                return .copy
            }
            return super.draggingEntered(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
                return .copy
            }
            return super.draggingUpdated(sender)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
                return super.performDragOperation(sender)
            }
            let valid = urls.filter { URLValidator.isSafe($0) }
            guard !valid.isEmpty else { return super.performDragOperation(sender) }
            for url in valid {
                NotificationCenter.default.post(name: .openFileFromFinder, object: url)
            }
            return true
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var currentMarkdown: String = ""
        var isInitialLoadDone = false
        var lastHTML: String = ""
        var pendingPostLoadJS: String = ""
        var lastSearch = SearchState()
        var lastPreviewText: String = ""
        var lastZoomLevel: Double = 1.0
        var lastPrintTrigger: Int = 0
        var lastExportPDFTrigger: Int = 0
        var lastTOCTarget: String = ""
        var pendingKeywords: [String] = []
        var termsUpdateHandler: ((String) -> Void)?

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
            if !pendingKeywords.isEmpty {
                let js = Self.buildKeywordJS(pendingKeywords)
                pendingKeywords = []
                webView.evaluateJavaScript(js) { [weak self] result, _ in
                    if let json = result as? String {
                        self?.termsUpdateHandler?(json)
                    }
                }
            }
        }

        static func buildKeywordJS(_ keywords: [String]) -> String {
            var js = ""
            for keyword in keywords {
                let encoded = HTMLBuilder.jsonEncode(keyword)
                js += "window.__modsSearch.add(\(encoded), false, false);\n"
            }
            js += "window.__modsSearch.getTerms()"
            return js
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if !lastHTML.isEmpty {
                webView.loadHTMLString(lastHTML, baseURL: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "loadImage",
                  let body = message.body as? [String: String],
                  let id = body["id"],
                  let src = body["src"] else { return }
            TrustedImageDomains.handleLoadImage(id: id, src: src, webView: message.webView)
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = ModsWebView(frame: .zero, configuration: HTMLBuilder.webViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Remove existing handler (shared controller) before adding to avoid duplicate crash
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "loadImage")
        controller.add(context.coordinator, name: "loadImage")
        context.coordinator.currentMarkdown = markdown
        context.coordinator.termsUpdateHandler = { [self] json in
            self.updateActiveTerms(from: json)
        }

        if !markdown.isEmpty {
            let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
            let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
            context.coordinator.lastHTML = html
            context.coordinator.pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
            context.coordinator.pendingKeywords = HighlightKeywords.keywords()
            context.coordinator.isInitialLoadDone = true
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastZoomLevel != zoomLevel {
            context.coordinator.lastZoomLevel = zoomLevel
            let fontPx = 16.0 * zoomLevel
            webView.evaluateJavaScript("document.body.style.fontSize='\(fontPx)px'")
        }

        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown

            if context.coordinator.isInitialLoadDone && !markdown.isEmpty {
                updateContentViaJS(webView: webView, restoreHighlights: !activeSearchTerms.isEmpty)
            } else if !markdown.isEmpty {
                // First real content load — use loadHTMLString for full page setup
                let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
                let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
                context.coordinator.lastHTML = html
                context.coordinator.pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
                context.coordinator.pendingKeywords = HighlightKeywords.keywords()
                context.coordinator.isInitialLoadDone = true
                webView.loadHTMLString(html, baseURL: nil)
            }
        }

        // Search operations
        if context.coordinator.isInitialLoadDone {
            if context.coordinator.lastSearch.addTrigger != search.addTrigger {
                context.coordinator.lastSearch.addTrigger = search.addTrigger
                if search.text.count >= 2 && search.text.count <= 256 {
                    let encoded = HTMLBuilder.jsonEncode(search.text)
                    let cs = search.caseSensitive ? "true" : "false"
                    let ww = search.wholeWord ? "true" : "false"
                    evaluateSearchJS("window.__modsSearch.add(\(encoded),\(cs),\(ww))", webView: webView)
                }
            }
            if context.coordinator.lastSearch.removeTrigger != search.removeTrigger {
                context.coordinator.lastSearch.removeTrigger = search.removeTrigger
                let encoded = HTMLBuilder.jsonEncode(search.removeTerm)
                evaluateSearchJS("window.__modsSearch.remove(\(encoded))", webView: webView)
            }
            if context.coordinator.lastSearch.clearTrigger != search.clearTrigger {
                context.coordinator.lastSearch.clearTrigger = search.clearTrigger
                evaluateSearchJS("window.__modsSearch.clearAll()", webView: webView)
            }
            if context.coordinator.lastSearch.scrollToNextTrigger != search.scrollToNextTrigger {
                context.coordinator.lastSearch.scrollToNextTrigger = search.scrollToNextTrigger
                let encoded = HTMLBuilder.jsonEncode(search.scrollToNextTerm)
                evaluateSearchJS("window.__modsSearch.scrollToNext(\(encoded))", webView: webView)
            }
            if context.coordinator.lastSearch.scrollToPrevTrigger != search.scrollToPrevTrigger {
                context.coordinator.lastSearch.scrollToPrevTrigger = search.scrollToPrevTrigger
                let encoded = HTMLBuilder.jsonEncode(search.scrollToPrevTerm)
                evaluateSearchJS("window.__modsSearch.scrollToPrev(\(encoded))", webView: webView)
            }
            if context.coordinator.lastSearch.pushTrigger != search.pushTrigger {
                context.coordinator.lastSearch.pushTrigger = search.pushTrigger
                evaluateStackJS("window.__modsSearch.push()", webView: webView)
            }
            if context.coordinator.lastSearch.popTrigger != search.popTrigger {
                context.coordinator.lastSearch.popTrigger = search.popTrigger
                evaluateStackJS("window.__modsSearch.pop()", webView: webView)
            }
            if context.coordinator.lastSearch.restoreTrigger != search.restoreTrigger {
                context.coordinator.lastSearch.restoreTrigger = search.restoreTrigger
                evaluateStackJS("window.__modsSearch.restore(\(search.restoreIndex))", webView: webView)
            }
            // Live preview while typing
            if context.coordinator.lastPreviewText != search.previewText {
                context.coordinator.lastPreviewText = search.previewText
                if search.previewText.count >= 2 {
                    let encoded = HTMLBuilder.jsonEncode(search.previewText)
                    webView.evaluateJavaScript("window.__modsSearch.preview(\(encoded))")
                } else {
                    webView.evaluateJavaScript("window.__modsSearch.clearPreview()")
                }
            }
        }

        // Print
        if context.coordinator.lastPrintTrigger != printTrigger {
            context.coordinator.lastPrintTrigger = printTrigger
            if let window = webView.window {
                webView.printOperation(with: .shared).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            }
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
        panel.nameFieldStringValue = "document.pdf"
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
                        Self.showExportError("Could not save PDF: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    Self.showExportError("Could not create PDF: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func showExportError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func evaluateSearchJS(_ js: String, webView: WKWebView) {
        webView.evaluateJavaScript(js) { result, _ in
            if let json = result as? String { self.updateActiveTerms(from: json) }
        }
    }

    private func evaluateStackJS(_ js: String, webView: WKWebView) {
        webView.evaluateJavaScript(js) { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let termsJSON = try? JSONSerialization.data(withJSONObject: obj["terms"] ?? []),
               let termsStr = String(data: termsJSON, encoding: .utf8) {
                self.updateActiveTerms(from: termsStr)
            }
            if let stackArray = obj["stack"] as? [[String]] {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) { self.searchStack = stackArray }
                }
            }
        }
    }

    private func updateActiveTerms(from json: String) {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) { activeSearchTerms = [] }
            }
            return
        }
        let terms = array.compactMap { dict -> (term: String, slot: Int, count: Int, current: Int)? in
            guard let term = dict["term"] as? String,
                  let slot = dict["slot"] as? Int,
                  let count = dict["count"] as? Int else { return nil }
            let current = dict["current"] as? Int ?? 0
            return (term, slot, count, current)
        }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) { activeSearchTerms = terms }
        }
    }

    private func updateContentViaJS(webView: WKWebView, restoreHighlights: Bool = false) {
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

        webView.evaluateJavaScript(js) { _, _ in
            let addKeywords = {
                let keywords = HighlightKeywords.keywords()
                guard !keywords.isEmpty else { return }
                let kwJS = Coordinator.buildKeywordJS(keywords)
                webView.evaluateJavaScript(kwJS) { result, _ in
                    if let json = result as? String { self.updateActiveTerms(from: json) }
                }
            }

            if restoreHighlights {
                webView.evaluateJavaScript("window.__modsSearch._rebuildAll(); window.__modsSearch.getTerms()") { result, _ in
                    if let json = result as? String { self.updateActiveTerms(from: json) }
                    addKeywords()
                }
            } else {
                addKeywords()
            }
        }
    }
}
