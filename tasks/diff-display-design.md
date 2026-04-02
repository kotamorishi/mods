# Diff Display Design Document

## 要件
1. 差分は変更行の**直前（すぐ上）**に表示
2. 差分とコンテンツが**重ならない**
3. 差分以外の要素は**増減しない**（視覚的に1つのブロックに見える）
4. 差分テキストはレンダリング済み（マークダウン記法ではなく読みやすいテキスト）

## 現状の問題
- blockIndex マッピングがずれる（cmark AST とレンダリング後の HTML 子要素数が一致しない場合がある）
- テーブル行のような複合要素で位置が正しく計算されない
- 要素タイプごとに異なるロジックが必要だが統一されていない

## アプローチ: HTML レンダリング後の DOM 操作で統一

### 方針転換
**cmark AST の行番号マッピングを廃止**し、代わりに:
1. diff の各 hunk から**変更後のテキスト**を取得
2. レンダリング済み HTML の DOM を走査して、そのテキストを含む要素を特定
3. その要素の**直前**に diff ブロックを挿入

これにより行番号↔ブロックインデックスの変換が不要になり、マッピングのずれが根本的に解消される。

### DOM テキスト検索の方法
```
1. diff hunk の addedLines から最初の意味のあるテキストを抽出
2. マークダウン記法を除去して純粋テキストにする
3. DOM の全ブロック要素を走査し、textContent にそのテキストが含まれる要素を見つける
4. 見つかった要素の直前に diff ブロックを挿入
```

### 要素タイプ別の分割戦略

すべての要素で同じパターン: **親要素を分割 → 上半分 + diff + 下半分 → CSS でシームレスに見せる**

#### コードブロック (`<pre><code>`)
```
分割単位: テキスト行（\n で split）
上半分: <pre class="mods-diff-el-top"><code>lines before</code></pre>
diff:    <div class="mods-diff-block mods-diff-inline">...</div>
下半分: <pre class="mods-diff-el-bottom"><code>lines from change</code></pre>
```

#### リスト (`<ul>`, `<ol>`)
```
分割単位: <li> 要素
上半分: <ul class="mods-diff-el-top"><li>items before</li></ul>
diff:    <div class="mods-diff-block mods-diff-inline">...</div>
下半分: <ul class="mods-diff-el-bottom"><li>changed item + rest</li></ul>
```

#### テーブル (`<table>`)
```
分割しない — テーブル内に diff 用の <tr> を挿入
変更された <tr> の直前に、diff 内容を colspan で1つのセルにまとめた <tr> を挿入:

<table>
  <thead><tr><th>Left</th><th>Center</th><th>Right</th></tr></thead>
  <tbody>
    <tr><td>L1</td><td>C1</td><td>R1</td></tr>
    <tr class="mods-diff-tr-del"><td colspan="3">- L2 | C2 | R2</td></tr>
    <tr class="mods-diff-tr-add"><td colspan="3">+ L2 | C2 | Rvs2</td></tr>
    <tr><td>L2</td><td>C2</td><td>Rvs2</td></tr>
    <tr><td>L3</td><td>C3</td><td>R3</td></tr>
  </tbody>
</table>

CSS: .mods-diff-tr-del td, .mods-diff-tr-add td に赤/緑背景
```

#### 段落 (`<p>`)、見出し (`<h1>`-`<h6>`)
```
分割不要 — 単一要素なので直前に diff ブロックを挿入するだけ
diff:    <div class="mods-diff-block mods-diff-inline">...</div>
element: <p>changed text</p>
```

#### ブロック引用 (`<blockquote>`)
```
分割単位: 子要素（<p> など）
上半分: <blockquote class="mods-diff-el-top">children before</blockquote>
diff:    <div class="mods-diff-block mods-diff-inline">...</div>
下半分: <blockquote class="mods-diff-el-bottom">changed child + rest</blockquote>
```

### CSS クラス設計

```css
/* 分割された要素の上半分 */
.mods-diff-el-top {
    margin-bottom: 0 !important;
    padding-bottom: 0 !important;
    border-bottom: none !important;
    border-bottom-left-radius: 0 !important;
    border-bottom-right-radius: 0 !important;
}

/* 分割された要素の下半分 */
.mods-diff-el-bottom {
    margin-top: 0 !important;
    padding-top: 0 !important;
    border-top: none !important;
    border-top-left-radius: 0 !important;
    border-top-right-radius: 0 !important;
}

/* 要素間に挿入される diff ブロック */
.mods-diff-inline {
    border-radius: 0 !important;
    margin-top: 0 !important;
    margin-bottom: 0 !important;
}

/* テーブル内 diff 行 */
.mods-diff-tr-del td {
    background-color: rgba(248, 81, 73, 0.2);
    color: #cf222e;
    font-family: monospace;
    font-size: 13px;
    border: none;
}
.mods-diff-tr-add td {
    background-color: rgba(46, 160, 67, 0.2);
    color: #116329;
    font-family: monospace;
    font-size: 13px;
    border: none;
}
```

### 変更対象の要素を見つける JS ロジック

```javascript
function findTargetElement(content, anchorText) {
    // ブロック要素を全て取得（直接の子 + ネストされた li, tr）
    var allBlocks = content.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, tr, pre, blockquote');
    for (var i = 0; i < allBlocks.length; i++) {
        var el = allBlocks[i];
        if (el.textContent.trim().indexOf(anchorText) !== -1) {
            return el;
        }
    }
    return null;
}

function insertDiff(target, diffBlock) {
    var parent = target.parentElement;
    var tag = parent ? parent.tagName : '';

    // 段落/見出し: 直前に挿入（分割不要）
    if (['P','H1','H2','H3','H4','H5','H6'].includes(target.tagName)) {
        target.parentNode.insertBefore(diffBlock, target);
        return;
    }

    // リスト内の <li>: 親 <ul>/<ol> を分割
    if (target.tagName === 'LI' && (tag === 'UL' || tag === 'OL')) {
        splitContainer(parent, target, diffBlock);
        return;
    }

    // テーブル内の <tr>: テーブル内に diff 行を挿入（分割しない）
    if (target.tagName === 'TR') {
        var colCount = target.querySelectorAll('td,th').length;
        insertTableDiffRows(target, diffBlock, colCount);
        return;
    }

    // コードブロック内: <pre> を行で分割
    if (target.tagName === 'PRE') {
        splitCodeBlock(target, anchorText, diffBlock);
        return;
    }

    // フォールバック: 要素の直前に挿入
    target.parentNode.insertBefore(diffBlock, target);
}
```

### diff テキストの表示形式

マークダウン記法を除去したプレーンテキスト:
- `| L2 | C2 | R2 |` → `L2 | C2 | R2`
- `- [x] Completed` → `Completed`
- `## Heading` → `Heading`
- `**bold** text` → `bold text`
- `` `code` `` → `code`
- コードブロック内の行 → そのまま表示

### diff 行のインデント

diff 行（`- old` / `+ new`）は、元のコンテンツと同じインデント位置に表示する。
左に寄せない。

例: ネストされた blockquote 内の変更
```
正しい:
    > > - Deeper quote     ← 元の表示位置
    > > + Deeper quotes    ← 同じインデント

間違い:
- Deeper quote             ← 左に寄っている
+ Deeper quotes
    > > Deeper quotes      ← 元のコンテンツ
```

**実装方法**: diff ブロックの `padding-left` を、挿入先の要素と同じにする。
JS で挿入先要素の `offsetLeft` または `getComputedStyle().paddingLeft` を取得し、
diff ブロックの `padding-left` に適用する。

```javascript
var targetLeft = target.getBoundingClientRect().left - content.getBoundingClientRect().left;
diffBlock.style.paddingLeft = targetLeft + 'px';
```

### Hide diff の復元ロジック

```javascript
// 1. 分割された要素を再結合
document.querySelectorAll('.mods-diff-el-top').forEach(function(top) {
    var diff = top.nextElementSibling;
    var bottom = diff && diff.nextElementSibling;
    if (!diff || !bottom) return;
    if (!diff.classList.contains('mods-diff-block')) return;
    if (!bottom.classList.contains('mods-diff-el-bottom')) return;

    // pre の場合: code の innerHTML を結合
    var codeTop = top.querySelector('code');
    var codeBottom = bottom.querySelector('code');
    if (codeTop && codeBottom) {
        codeTop.innerHTML += '\n' + codeBottom.innerHTML;
    } else {
        // list/table/blockquote: 子要素を移動
        while (bottom.firstChild) top.appendChild(bottom.firstChild);
    }
    top.classList.remove('mods-diff-el-top');
    diff.remove();
    bottom.remove();
});

// 2. 分割されていない diff ブロック（p, h* の直前）を削除
document.querySelectorAll('.mods-diff-block').forEach(function(el) { el.remove(); });
```

## ファイル変更一覧
- `mods/MarkdownWebView.swift` — JS 全面書き換え（DOM テキスト検索 + 統一分割ロジック）
- `mods/MarkdownRenderer.swift` — `mapHunksToBlocks` を簡略化（blockIndex/subIndex 不要に）、`renderLinesToText` 改善
- `mods/Resources/mods.css` — 統一 CSS クラス
- `mods/modsApp.swift` — DiffHunk の blockIndex/subIndex を anchorText に変更

## diff ナビゲーション

トーストピル（画面下部）をクリックすると次の差分箇所にスクロールする。

### 動作
- ピルのサマリーテキスト部分（"+N -M"）をクリック → 次の diff ブロックにスムーズスクロール
- 複数の diff がある場合、順番に巡回（最後の diff の次は最初に戻る）
- 現在位置を `@State private var currentDiffIndex: Int = 0` で管理

### 実装
- diff ブロックには共通クラス `.mods-diff-block` または `.mods-diff-tr-del` が付いている
- JS で全 diff 要素を取得し、指定インデックスの要素に `scrollIntoView({ behavior: 'smooth', block: 'center' })` を実行
- ピルクリック時に `scrollToDiffTrigger += 1` をインクリメント
- MarkdownWebView の `updateNSView` でトリガー検出 → JS 実行

### ピルの表示変更
```
現在: "File updated (+2 -1)  [Hide diff]"
変更: "File updated (+2 -1) ▼  [Hide diff]"
                             ↑ クリックで次の差分へ
```

もしくはサマリーテキスト全体をクリック可能にして、テキスト自体がナビゲーションボタンになる。

## テストケース
1. コードブロック内の1行変更 → コード行の直前に diff、コードブロックは1つに見える
2. リストアイテムの変更 → li の直前に diff、リストは1つに見える
3. テーブルセルの変更 → tr の直前に diff、テーブルは1つに見える
4. 段落テキストの変更 → p の直前に diff
5. 見出しの変更 → h* の直前に diff
6. Hide diff → 全ての分割が復元、差分表示が消える
