# mods — Markdown Viewer

A lightweight, fast markdown viewer for macOS with GitHub-style rendering.

## Features

- **Full GFM Support** — tables, task lists, footnotes, alerts
- **Syntax Highlighting** — 16+ programming languages
- **Math & Diagrams** — KaTeX and Mermaid support
- **QuickLook** — preview .md files in Finder with Space key

## Code Example

```swift
struct ContentView: View {
    var body: some View {
        Text("Hello, World!")
            .font(.title)
            .foregroundStyle(.primary)
    }
}
```

```python
def fibonacci(n):
    a, b = 0, 1
    for _ in range(n):
        yield a
        a, b = b, a + b

print(list(fibonacci(10)))
```

## Task List

- [x] GitHub Flavored Markdown
- [x] Syntax highlighting
- [x] Dark mode support
- [x] QuickLook extension
- [x] Multiple windows
- [x] Find in document

## Table

| Feature | Status | Notes |
|---------|--------|-------|
| GFM rendering | ✅ | cmark-gfm engine |
| Code blocks | ✅ | highlight.js |
| Math | ✅ | KaTeX |
| Diagrams | ✅ | Mermaid |
| Security | ✅ | Sandboxed, CSP |

## Alerts

> [!NOTE]
> mods uses the same markdown engine as GitHub.

> [!TIP]
> Press `Cmd+Shift+T` to toggle the outline sidebar.

## Math

Einstein's famous equation: $E = mc^2$

The quadratic formula:

$$
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
$$

## Diagram

```mermaid
graph LR
    A[Markdown] --> B[cmark-gfm]
    B --> C[HTML]
    C --> D[WebKit]
    D --> E[Display]
```

## Emoji

Built with :heart: for developers :rocket:

---

*mods* — view markdown, beautifully. `#0969DA`
