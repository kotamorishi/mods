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
    @Binding var zoomLevel: Double
    let search: SearchState
    @Binding var activeSearchTerms: [(term: String, slot: Int, count: Int, current: Int)]
    @Binding var searchStack: [[String]]
    let printTrigger: Int
    let exportPDFTrigger: Int
    let copyRichTextTrigger: Int
    let tocScrollTarget: String
    let scrollToTopTrigger: Int
    let diffHunks: [MarkdownRenderer.DiffHunk]
    let applyDiffTrigger: Int
    let clearDiffTrigger: Int
    let scrollToDiffTrigger: Int

    /// WKWebView subclass that intercepts drag registration and handles file drops and magnification.
    class ModsWebView: WKWebView {
        var onMagnify: ((Double) -> Void)?
        var scrollToTopOnNextUpdate: Bool = false
        private var magnifyScale: Double = 1.0

        func printContent() {
            guard let window = self.window else { return }
            let printInfo = NSPrintInfo()
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isVerticallyCentered = false
            printInfo.isHorizontallyCentered = false
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36
            let op = self.printOperation(with: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.view?.frame = self.bounds
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }

        override func magnify(with event: NSEvent) {
            switch event.phase {
            case .began:
                magnifyScale = 1.0
            case .changed:
                magnifyScale += event.magnification * 0.1
                onMagnify?(magnifyScale)
            default:
                break
            }
        }

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
        var lastCopyRichTextTrigger: Int = 0
        var lastApplyDiffTrigger: Int = 0
        var lastClearDiffTrigger: Int = 0
        var lastScrollToDiffTrigger: Int = 0
        var currentDiffIndex: Int = 0
        var lastTOCTarget: String = ""
        var pendingKeywords: [String] = []
        var termsUpdateHandler: ((String) -> Void)?
        var renderTask: Task<Void, Never>?
        var magnifyBaseZoom: Double = 1.0
        var lastScrollToTopTrigger: Int = 0

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

        (webView as? ModsWebView)?.onMagnify = { [self] scale in
            let baseZoom = context.coordinator.magnifyBaseZoom
            self.zoomLevel = max(0.25, min(5.0, baseZoom * scale))
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
            context.coordinator.magnifyBaseZoom = zoomLevel
            let fontPx = 16.0 * zoomLevel
            webView.evaluateJavaScript("document.body.style.fontSize='\(fontPx)px'")
        }

        if context.coordinator.lastScrollToTopTrigger != scrollToTopTrigger {
            context.coordinator.lastScrollToTopTrigger = scrollToTopTrigger
            (webView as? ModsWebView)?.scrollToTopOnNextUpdate = true
        }

        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown
            let currentMarkdown = markdown
            let restoreHighlights = !activeSearchTerms.isEmpty

            if context.coordinator.isInitialLoadDone && !currentMarkdown.isEmpty {
                context.coordinator.renderTask?.cancel()
                context.coordinator.renderTask = Task.detached(priority: .userInitiated) {
                    let bodyHTML = MarkdownRenderer.renderToHTML(currentMarkdown)
                    let postLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
                    await MainActor.run {
                        self.updateContentViaJS(webView: webView, bodyHTML: bodyHTML, postLoadJS: postLoadJS, restoreHighlights: restoreHighlights)
                    }
                }
            } else if !currentMarkdown.isEmpty {
                // First real content load — synchronous for immediate display
                let bodyHTML = MarkdownRenderer.renderToHTML(currentMarkdown)
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
            (webView as? ModsWebView)?.printContent()
        }

        // Copy as rich text
        if context.coordinator.lastCopyRichTextTrigger != copyRichTextTrigger {
            context.coordinator.lastCopyRichTextTrigger = copyRichTextTrigger
            webView.evaluateJavaScript("document.getElementById('content').innerHTML") { result, _ in
                guard let html = result as? String else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                // Write as HTML (rich text) and plain text fallback
                if let data = html.data(using: .utf8) {
                    pasteboard.setData(data, forType: .html)
                }
                let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                pasteboard.setString(plain, forType: .string)
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
                var el = document.getElementById(\(jsonTarget));
                if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            })();
            """
            webView.evaluateJavaScript(js)
        }

        // Apply diff highlights
        if context.coordinator.lastApplyDiffTrigger != applyDiffTrigger {
            context.coordinator.lastApplyDiffTrigger = applyDiffTrigger
            // Delay to let content render first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.applyDiffHighlights(webView: webView)
            }
        }

        // Clear diff highlights
        if context.coordinator.lastClearDiffTrigger != clearDiffTrigger {
            context.coordinator.lastClearDiffTrigger = clearDiffTrigger
            let js = """
            (function() {
                // Rejoin split code blocks
                document.querySelectorAll('.mods-diff-el-top').forEach(function(top) {
                    var diff = top.nextElementSibling;
                    var bottom = diff ? diff.nextElementSibling : null;
                    if (!diff || !diff.classList.contains('mods-diff-block')) return;
                    if (!bottom || !bottom.classList.contains('mods-diff-el-bottom')) return;
                    var codeTop = top.querySelector('code');
                    var codeBottom = bottom.querySelector('code');
                    if (codeTop && codeBottom) {
                        codeTop.innerHTML = codeTop.innerHTML + '\\n' + codeBottom.innerHTML;
                    } else {
                        while (bottom.firstChild) top.appendChild(bottom.firstChild);
                    }
                    top.classList.remove('mods-diff-el-top');
                    diff.remove();
                    bottom.remove();
                });
                // Remove standalone diff blocks (for p, h*)
                document.querySelectorAll('.mods-diff-block').forEach(function(el) { el.remove(); });
            })();
            """
            webView.evaluateJavaScript(js)
        }

        // Scroll to next diff
        if context.coordinator.lastScrollToDiffTrigger != scrollToDiffTrigger {
            context.coordinator.lastScrollToDiffTrigger = scrollToDiffTrigger
            let idx = context.coordinator.currentDiffIndex
            let js = """
            (function() {
                var allDiffs = Array.from(document.querySelectorAll('.mods-diff-block'));
                if (allDiffs.length === 0) return -1;
                var idx = \(idx) % allDiffs.length;
                allDiffs[idx].scrollIntoView({ behavior: 'smooth', block: 'center' });
                return allDiffs.length;
            })();
            """
            webView.evaluateJavaScript(js) { result, _ in
                if let count = result as? Int, count > 0 {
                    context.coordinator.currentDiffIndex = (idx + 1) % count
                }
            }
        }
    }

    private func applyDiffHighlights(webView: WKWebView) {
        guard !diffHunks.isEmpty else { return }
        var hunksJSON: [String] = []
        for hunk in diffHunks {
            let removedRendered = HTMLBuilder.jsonEncode(hunk.removedHTML)
            let addedRendered = HTMLBuilder.jsonEncode(hunk.addedHTML)
            // Anchor text: stripped text from first meaningful added line for DOM search
            let anchor = hunk.addedLines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            let stripped = MarkdownRenderer.renderLinesToText([anchor]).first ?? ""
            let anchorJSON = HTMLBuilder.jsonEncode(stripped)
            hunksJSON.append("{removed:\(removedRendered),added:\(addedRendered),anchor:\(anchorJSON)}")
        }
        let js = """
        (function() {
            var hunks = [\(hunksJSON.joined(separator: ","))];
            var content = document.getElementById('content');
            if (!content) return;

            // Find the DOM element containing the anchor text
            function findTarget(anchor) {
                if (!anchor) return null;
                var els = content.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, tr, td, th, pre, blockquote');
                // Exact match
                for (var i = 0; i < els.length; i++) {
                    if (els[i].textContent.trim().indexOf(anchor) !== -1) {
                        var el = els[i];
                        if (el.tagName === 'TD' || el.tagName === 'TH') el = el.closest('tr') || el;
                        return el;
                    }
                }
                // Word-based match: all words must be present
                var words = anchor.split(/[\\s|,]+/).filter(function(w) { return w.length > 1; });
                if (words.length > 0) {
                    for (var i = 0; i < els.length; i++) {
                        var t = els[i].textContent;
                        if (words.every(function(w) { return t.indexOf(w) !== -1; })) {
                            var el = els[i];
                            if (el.tagName === 'TD' || el.tagName === 'TH') el = el.closest('tr') || el;
                            return el;
                        }
                    }
                }
                return null;
            }

            // Build diff block with +/- lines
            function buildDiffBlock(hunk) {
                var db = document.createElement('div');
                db.className = 'mods-diff-block mods-diff-inline';
                hunk.removed.split('\\n').filter(function(l){return l.trim();}).forEach(function(line) {
                    var d = document.createElement('div');
                    d.className = 'mods-diff-line mods-diff-del';
                    d.textContent = '\\u2212 ' + line;
                    db.appendChild(d);
                });
                hunk.added.split('\\n').filter(function(l){return l.trim();}).forEach(function(line) {
                    var d = document.createElement('div');
                    d.className = 'mods-diff-line mods-diff-add';
                    d.textContent = '+ ' + line;
                    db.appendChild(d);
                });
                return db.hasChildNodes() ? db : null;
            }

            // Split a container (ul/ol/blockquote) at a child index
            function splitContainer(parent, childIdx, diffBlock) {
                var topEl = parent.cloneNode(false);
                var bottomEl = parent.cloneNode(false);
                var items = Array.from(parent.children);
                for (var i = 0; i < items.length; i++) {
                    if (i < childIdx) topEl.appendChild(items[i].cloneNode(true));
                    else bottomEl.appendChild(items[i].cloneNode(true));
                }
                topEl.classList.add('mods-diff-el-top');
                bottomEl.classList.add('mods-diff-el-bottom');
                parent.parentNode.insertBefore(topEl, parent);
                parent.parentNode.insertBefore(diffBlock, parent);
                parent.parentNode.insertBefore(bottomEl, parent);
                parent.remove();
            }

            // Split a <pre> at a line index
            function splitCodeBlock(pre, anchor, diffBlock) {
                var code = pre.querySelector('code');
                if (!code) return false;
                var codeHTML = code.innerHTML;
                var codeLines = codeHTML.split('\\n');
                var plainLines = (code.textContent||'').split('\\n');
                var matchIdx = -1;
                for (var i = 0; i < plainLines.length; i++) {
                    if (anchor && plainLines[i].trim().indexOf(anchor) !== -1) { matchIdx = i; break; }
                }
                if (matchIdx < 0) return false;
                var lang = code.className || '';
                var preBefore = document.createElement('pre');
                var codeBefore = document.createElement('code');
                codeBefore.className = lang;
                codeBefore.innerHTML = codeLines.slice(0, matchIdx).join('\\n');
                preBefore.appendChild(codeBefore);
                preBefore.classList.add('mods-diff-el-top');
                var preAfter = document.createElement('pre');
                var codeAfter = document.createElement('code');
                codeAfter.className = lang;
                codeAfter.innerHTML = codeLines.slice(matchIdx).join('\\n');
                preAfter.appendChild(codeAfter);
                preAfter.classList.add('mods-diff-el-bottom');
                pre.parentNode.insertBefore(preBefore, pre);
                pre.parentNode.insertBefore(diffBlock, pre);
                pre.parentNode.insertBefore(preAfter, pre);
                pre.remove();
                return true;
            }

            hunks.forEach(function(hunk) {
                var target = findTarget(hunk.anchor);
                if (!target) return;
                var tag = target.tagName;
                var parent = target.parentElement;
                var parentTag = parent ? parent.tagName : '';

                // Match indent of target element
                var diffBlock = buildDiffBlock(hunk);
                if (!diffBlock) return;
                var contentRect = content.getBoundingClientRect();
                var targetRect = target.getBoundingClientRect();
                var indent = targetRect.left - contentRect.left;
                if (indent > 0) diffBlock.style.paddingLeft = indent + 'px';

                // Table row: split table at the target <tr>, insert full-width diff block between
                if (tag === 'TR') {
                    var table = target.closest('table');
                    if (!table) return;
                    diffBlock.style.paddingLeft = '0';
                    var rows = Array.from(table.querySelectorAll('tr'));
                    var trIdx = rows.indexOf(target);
                    if (trIdx <= 0) { table.parentNode.insertBefore(diffBlock, table); return; }
                    // Clone table structure for top and bottom halves
                    var topTable = table.cloneNode(false);
                    var bottomTable = table.cloneNode(false);
                    var topBody = document.createElement('tbody');
                    var bottomBody = document.createElement('tbody');
                    // Copy thead to both halves
                    var thead = table.querySelector('thead');
                    if (thead) {
                        topTable.appendChild(thead.cloneNode(true));
                        bottomTable.appendChild(thead.cloneNode(true));
                    }
                    for (var ri = 0; ri < rows.length; ri++) {
                        if (rows[ri].parentElement && rows[ri].parentElement.tagName === 'THEAD') continue;
                        if (ri < trIdx) topBody.appendChild(rows[ri].cloneNode(true));
                        else bottomBody.appendChild(rows[ri].cloneNode(true));
                    }
                    topTable.appendChild(topBody);
                    bottomTable.appendChild(bottomBody);
                    topTable.classList.add('mods-diff-el-top');
                    bottomTable.classList.add('mods-diff-el-bottom');
                    table.parentNode.insertBefore(topTable, table);
                    table.parentNode.insertBefore(diffBlock, table);
                    table.parentNode.insertBefore(bottomTable, table);
                    table.remove();
                    return;
                }

                // List item: split parent <ul>/<ol> at the target <li>
                if (tag === 'LI' && (parentTag === 'UL' || parentTag === 'OL')) {
                    var idx = Array.from(parent.children).indexOf(target);
                    if (idx > 0) { splitContainer(parent, idx, diffBlock); return; }
                }

                // Code block: split <pre> at the matching line
                if (tag === 'PRE') {
                    if (splitCodeBlock(target, hunk.anchor, diffBlock)) return;
                }
                // Inside a code block (target found inside <pre>)
                var pre = target.closest ? target.closest('pre') : null;
                if (pre) {
                    if (splitCodeBlock(pre, hunk.anchor, diffBlock)) return;
                }

                // Blockquote: split at child
                if (tag !== 'BLOCKQUOTE' && parentTag === 'BLOCKQUOTE') {
                    var idx = Array.from(parent.children).indexOf(target);
                    if (idx > 0) { splitContainer(parent, idx, diffBlock); return; }
                }

                // Simple elements (p, h*, standalone blockquote): insert before
                target.parentNode.insertBefore(diffBlock, target);
            });
        })();
        """
        webView.evaluateJavaScript(js)
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

    private func updateContentViaJS(webView: WKWebView, bodyHTML: String? = nil, postLoadJS: String? = nil, restoreHighlights: Bool = false) {
        let bodyHTML = bodyHTML ?? MarkdownRenderer.renderToHTML(markdown)
        let postLoadJS = postLoadJS ?? HTMLBuilder.conditionalJS(for: bodyHTML)

        let scrollToTop = (webView as? ModsWebView)?.scrollToTopOnNextUpdate ?? false
        (webView as? ModsWebView)?.scrollToTopOnNextUpdate = false

        let js: String
        if scrollToTop {
            // New file: update content and scroll to top
            js = """
            (function() {
                document.getElementById('content').innerHTML = \(HTMLBuilder.jsonEncode(bodyHTML));
                \(postLoadJS)
                window.scrollTo(0, 0);
            })();
            """
        } else {
            // Same file reloaded: save and restore scroll position
            js = """
            (function() {
                var marker = null;
                var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for (var i = headings.length - 1; i >= 0; i--) {
                    if (headings[i].getBoundingClientRect().top <= 10) {
                        marker = headings[i].id || headings[i].textContent.trim();
                        break;
                    }
                }
                var scrollRatio = document.documentElement.scrollHeight > window.innerHeight
                    ? window.scrollY / (document.documentElement.scrollHeight - window.innerHeight)
                    : 0;

                document.getElementById('content').innerHTML = \(HTMLBuilder.jsonEncode(bodyHTML));
                \(postLoadJS)

                if (marker) {
                    var found = marker ? document.getElementById(marker) : null;
                    if (!found) {
                        var newHeadings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                        for (var h of newHeadings) {
                            if (h.textContent.trim() === marker) { found = h; break; }
                        }
                    }
                    if (found) {
                        found.scrollIntoView({ block: 'start' });
                        return;
                    }
                }
                if (scrollRatio > 0) {
                    var newMax = document.documentElement.scrollHeight - window.innerHeight;
                    window.scrollTo(0, scrollRatio * newMax);
                }
            })();
            """
        }

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
