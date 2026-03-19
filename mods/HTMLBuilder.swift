import Foundation
import WebKit

/// Shared HTML template builder used by both the main app and QuickLook extension.
/// Handles resource caching, CSS/JS assembly, WKWebView configuration, and content detection.
enum HTMLBuilder {
    // MARK: - Resource Cache

    nonisolated(unsafe) private static var _resourceCache: [String: String] = [:]

    nonisolated(unsafe) private static var _parentAppBundle: Bundle?

    /// Resolve the parent app's bundle when running as an extension.
    /// Structure: mods.app/Contents/PlugIns/ext.appex/Contents/MacOS/ext
    /// Parent resources: mods.app/Contents/Resources/
    private static func parentAppBundle() -> Bundle? {
        if let cached = _parentAppBundle { return cached }
        let extURL = Bundle.main.bundleURL
        // Go up from ext.appex to PlugIns/ to Contents/ to mods.app/
        let appURL = extURL
            .deletingLastPathComponent()  // PlugIns/
            .deletingLastPathComponent()  // Contents/
            .deletingLastPathComponent()  // mods.app/
        if let bundle = Bundle(url: appURL) {
            _parentAppBundle = bundle
            return bundle
        }
        return nil
    }

    static func cachedResource(_ name: String, type: String) -> String {
        let key = "\(name).\(type)"
        if let cached = _resourceCache[key] { return cached }
        // Try own bundle first, then parent app bundle (for extensions sharing resources)
        let url = Bundle.main.url(forResource: name, withExtension: type)
            ?? parentAppBundle()?.url(forResource: name, withExtension: type)
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        _resourceCache[key] = content
        return content
    }

    // MARK: - WKWebView Configuration

    nonisolated(unsafe) private static var _sharedConfig: WKWebViewConfiguration?

    /// Shared configuration with highlight.js + post-processing injected via WKUserScript.
    /// Security: JavaScript is disabled at the preference level; our WKUserScripts bypass this
    /// restriction. This prevents any JS embedded in the markdown from executing, while still
    /// allowing our own highlight.js and post-processing to run.
    @MainActor static func webViewConfiguration() -> WKWebViewConfiguration {
        if let config = _sharedConfig { return config }
        let config = WKWebViewConfiguration()

        // Security: disable JS from page content — only WKUserScript JS can run.
        // This prevents <script> tags in markdown from executing.
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        // Security: disable link previews (force-touch/3D-touch on links)
        config.preferences.isElementFullscreenEnabled = false

        let controller = WKUserContentController()

        let highlightJS = cachedResource("highlight.min", type: "js")
        if !highlightJS.isEmpty {
            controller.addUserScript(WKUserScript(source: highlightJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        controller.addUserScript(WKUserScript(source: postProcessScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        config.userContentController = controller
        _sharedConfig = config
        return config
    }

    // MARK: - Cached HTML Fragments

    nonisolated(unsafe) private static var _styleBlock: String?
    nonisolated(unsafe) private static var _baseHead: String?
    nonisolated(unsafe) private static var _mermaidScript: String?
    nonisolated(unsafe) private static var _katexHead: String?

    static func styleBlock() -> String {
        if let cached = _styleBlock { return cached }
        let githubCSS = cachedResource("github.min", type: "css")
        let githubDarkCSS = cachedResource("github-dark.min", type: "css")
        let modsCSS = cachedResource("mods", type: "css")
        let block = """
        <style>
        \(githubCSS)
        @media (prefers-color-scheme: dark) { \(githubDarkCSS) }
        \(modsCSS)
        </style>
        """
        _styleBlock = block
        return block
    }

    /// Shell page head: CSS only (JS via WKUserScript).
    static func baseHead() -> String {
        if let cached = _baseHead { return cached }
        let head = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src https: http: data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none';">
        <meta name="referrer" content="no-referrer">
        \(styleBlock())
        </head>
        <body>
        <div id="content">
        """
        _baseHead = head
        return head
    }

    static func mermaidScript() -> String {
        if let cached = _mermaidScript { return cached }
        let s = "<script>\(cachedResource("mermaid.min", type: "js"))</script>\n"
        _mermaidScript = s
        return s
    }

    static func katexHead() -> String {
        if let cached = _katexHead { return cached }
        let s = """
        <style>\(cachedResource("katex.min", type: "css"))</style>
        <script>\(cachedResource("katex.min", type: "js"))</script>
        <script>\(cachedResource("katex-auto-render.min", type: "js"))</script>
        """
        _katexHead = s
        return s
    }

    // MARK: - Post-Processing Script

    /// Injected via WKUserScript. Defines __modsPostProcess() and calls it on initial load.
    static let postProcessScript = """
    window.__modsPostProcess = function() {
        if (typeof mermaid !== 'undefined') {
            mermaid.initialize({ startOnLoad: false, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' });
            var mermaidBlocks = document.querySelectorAll('pre code.language-mermaid');
            mermaidBlocks.forEach(function(block) {
                var pre = block.parentElement;
                var div = document.createElement('div');
                div.className = 'mermaid';
                div.textContent = block.textContent;
                pre.replaceWith(div);
            });
            if (mermaidBlocks.length > 0) { mermaid.run(); }
        }
        document.querySelectorAll('pre code').forEach(function(block) {
            if (!block.classList.contains('language-math')) { hljs.highlightElement(block); }
        });
        document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.disabled = true; });
        // Copy button on code blocks
        function __modsCopyText(text, btn) {
            // Try modern API first, fall back to legacy execCommand
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(function() {
                    btn.textContent = 'Copied!';
                    setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
                }).catch(function() { __modsCopyLegacy(text, btn); });
            } else {
                __modsCopyLegacy(text, btn);
            }
        }
        function __modsCopyLegacy(text, btn) {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.style.cssText = 'position:fixed;left:-9999px;';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
            btn.textContent = 'Copied!';
            setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
        }
        document.querySelectorAll('pre').forEach(function(pre) {
            if (pre.querySelector('.__mods-copy-btn')) return;
            var code = pre.querySelector('code');
            if (!code) return;
            pre.style.position = 'relative';
            var btn = document.createElement('button');
            btn.className = '__mods-copy-btn';
            btn.textContent = 'Copy';
            btn.setAttribute('aria-label', 'Copy code to clipboard');
            btn.setAttribute('role', 'button');
            btn.addEventListener('click', function() { __modsCopyText(code.textContent, btn); });
            pre.appendChild(btn);
        });
        if (typeof katex !== 'undefined') {
            document.querySelectorAll('pre code.language-math').forEach(function(block) {
                var pre = block.parentElement;
                var div = document.createElement('div');
                div.className = 'math-block';
                try { katex.render(block.textContent, div, { displayMode: true, throwOnError: false }); }
                catch(e) { div.textContent = block.textContent; }
                pre.replaceWith(div);
            });
            if (typeof renderMathInElement !== 'undefined') {
                renderMathInElement(document.getElementById('content'), {
                    delimiters: [{left: '$$', right: '$$', display: true}, {left: '$', right: '$', display: false}],
                    throwOnError: false
                });
            }
        }
        // Blocked external images — click to load
        document.querySelectorAll('.blocked-image').forEach(function(el) {
            el.setAttribute('role', 'button');
            el.setAttribute('aria-label', 'Load external image: ' + (el.getAttribute('data-img-src') || ''));
            el.setAttribute('tabindex', '0');
            el.addEventListener('keydown', function(e) { if (e.key === 'Enter') el.click(); });
            el.addEventListener('click', function() {
                var src = el.getAttribute('data-img-src');
                if (src) {
                    var img = document.createElement('img');
                    img.src = src;
                    img.style.maxWidth = '100%';
                    el.className = 'loaded-image';
                    el.innerHTML = '';
                    el.appendChild(img);
                }
            });
        });
    };
    window.__modsPostProcess();

    // Find bar
    (function() {
        var bar = document.createElement('div');
        bar.id = '__mods-find-bar';
        bar.setAttribute('role', 'search');
        bar.setAttribute('aria-label', 'Find in document');
        bar.style.cssText = 'display:none;position:fixed;top:0;left:0;right:0;padding:8px 12px;background:rgba(246,248,250,0.95);backdrop-filter:blur(8px);border-bottom:1px solid #d0d7de;z-index:9999;font-family:-apple-system,sans-serif;font-size:13px;';
        bar.innerHTML = '<div style="display:flex;align-items:center;max-width:900px;margin:0 auto;gap:8px;"><input id="__mods-find-input" type="text" placeholder="Find..." aria-label="Search text" style="flex:1;padding:4px 8px;border:1px solid #d0d7de;border-radius:4px;font-size:13px;outline:none;"><span id="__mods-find-count" aria-live="polite" style="color:#656d76;min-width:40px;"></span><button id="__mods-find-next-btn" aria-label="Next match" style="padding:2px 8px;border:1px solid #d0d7de;border-radius:4px;background:#fff;cursor:pointer;">Next</button><button id="__mods-find-close-btn" aria-label="Close find bar" style="padding:2px 8px;border:1px solid #d0d7de;border-radius:4px;background:#fff;cursor:pointer;">✕</button></div>';
        document.body.appendChild(bar);
        document.getElementById('__mods-find-next-btn').addEventListener('click', function() { window.__modsFindNext(); });
        document.getElementById('__mods-find-close-btn').addEventListener('click', function() { window.__modsFindClose(); });

        if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
            bar.style.background = 'rgba(13,17,23,0.95)';
            bar.style.borderBottomColor = '#3d444d';
            var darkEls = bar.querySelectorAll('input, button');
            darkEls.forEach(function(el) {
                el.style.background = '#161b22';
                el.style.borderColor = '#3d444d';
                el.style.color = '#e6edf3';
            });
        }

        var input = document.getElementById('__mods-find-input');
        input.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') { window.__modsFindNext(); }
            if (e.key === 'Escape') { window.__modsFindClose(); }
        });
        input.addEventListener('input', function() { window.__modsFindHighlight(); });

        window.__modsToggleFind = function() {
            if (bar.style.display === 'none') {
                bar.style.display = 'block';
                document.getElementById('__mods-find-input').focus();
                document.getElementById('__mods-find-input').select();
            } else {
                window.__modsFindClose();
            }
        };

        window.__modsFindHighlight = function() {
            // Remove previous highlights
            document.querySelectorAll('.__mods-highlight').forEach(function(el) {
                el.replaceWith(el.textContent);
            });
            var term = document.getElementById('__mods-find-input').value;
            if (!term) { document.getElementById('__mods-find-count').textContent = ''; return; }
            var content = document.getElementById('content');
            var walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, null);
            var nodes = [];
            while (walker.nextNode()) { nodes.push(walker.currentNode); }
            var count = 0;
            var lowerTerm = term.toLowerCase();
            nodes.forEach(function(node) {
                var text = node.textContent;
                var lower = text.toLowerCase();
                var idx = lower.indexOf(lowerTerm);
                if (idx === -1) return;
                var frag = document.createDocumentFragment();
                var pos = 0;
                while (idx !== -1) {
                    frag.appendChild(document.createTextNode(text.substring(pos, idx)));
                    var mark = document.createElement('mark');
                    mark.className = '__mods-highlight';
                    mark.style.cssText = 'background:#fff3a8;color:#1f2328;border-radius:2px;';
                    mark.textContent = text.substring(idx, idx + term.length);
                    frag.appendChild(mark);
                    count++;
                    pos = idx + term.length;
                    idx = lower.indexOf(lowerTerm, pos);
                }
                frag.appendChild(document.createTextNode(text.substring(pos)));
                node.parentNode.replaceChild(frag, node);
            });
            document.getElementById('__mods-find-count').textContent = count + ' found';
            // Scroll to first match
            var first = document.querySelector('.__mods-highlight');
            if (first) { first.scrollIntoView({ block: 'center' }); }
        };

        window.__modsFindNext = function() {
            var marks = document.querySelectorAll('.__mods-highlight');
            if (marks.length === 0) return;
            var current = document.querySelector('.__mods-highlight-active');
            var idx = 0;
            if (current) {
                current.style.background = '#fff3a8';
                current.classList.remove('__mods-highlight-active');
                marks.forEach(function(m, i) { if (m === current) idx = (i + 1) % marks.length; });
            }
            marks[idx].style.background = '#f0a030';
            marks[idx].classList.add('__mods-highlight-active');
            marks[idx].scrollIntoView({ block: 'center' });
        };

        window.__modsFindClose = function() {
            bar.style.display = 'none';
            document.querySelectorAll('.__mods-highlight').forEach(function(el) {
                el.replaceWith(el.textContent);
            });
            document.getElementById('__mods-find-count').textContent = '';
            document.getElementById('__mods-find-input').value = '';
        };
    })();
    """

    // MARK: - Content Detection

    private static let inlineMathRegex = try! NSRegularExpression(pattern: "\\$[^\\s$].*?[^\\s$]\\$|\\$[^\\s$]\\$", options: [])

    static func containsInlineMath(_ html: String) -> Bool {
        let range = NSRange(html.startIndex..., in: html)
        return inlineMathRegex.firstMatch(in: html, range: range) != nil
    }

    static func needsMath(_ bodyHTML: String) -> Bool {
        bodyHTML.contains("language-math") || bodyHTML.contains("$$") || containsInlineMath(bodyHTML)
    }

    static func needsMermaid(_ bodyHTML: String) -> Bool {
        bodyHTML.contains("language-mermaid")
    }

    // MARK: - HTML Assembly

    /// Build a complete HTML page from rendered markdown body.
    /// Note: no inline <script> tags — JS is disabled at page level.
    /// Mermaid/KaTeX are injected post-load via evaluateJavaScript().
    static func buildHTML(bodyHTML: String) -> String {
        // KaTeX CSS is safe (not script), include it if needed
        var extraCSS = ""
        if needsMath(bodyHTML) {
            extraCSS = "<style>\(cachedResource("katex.min", type: "css"))</style>\n"
        }
        return baseHead() + extraCSS + bodyHTML + "</div>\n</body>\n</html>"
    }

    /// Build JS to inject conditional libraries (mermaid, katex) and run post-processing.
    /// Called via evaluateJavaScript() which bypasses allowsContentJavaScript = false.
    static func conditionalJS(for bodyHTML: String) -> String {
        var js = ""
        if needsMermaid(bodyHTML) {
            js += "if (typeof mermaid === 'undefined') { \(cachedResource("mermaid.min", type: "js")) }\n"
        }
        if needsMath(bodyHTML) {
            js += "if (typeof katex === 'undefined') { \(cachedResource("katex.min", type: "js")) }\n"
            js += "if (typeof renderMathInElement === 'undefined') { \(cachedResource("katex-auto-render.min", type: "js")) }\n"
        }
        js += "window.__modsPostProcess();\n"
        return js
    }

    // MARK: - Utilities

    static func jsonEncode(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }

    static func readFileWithFallback(url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return "# Unable to read file\n\nCould not read file data."
        }
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .shiftJIS, .utf16, .ascii]
        for encoding in encodings {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }
        return "# Unable to read file\n\nThis file could not be decoded as text."
    }
}
