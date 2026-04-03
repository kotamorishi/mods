// HTML Diff Algorithm
// Token-based HTML diffing inspired by html-diff-js.
// Compares two HTML strings and produces merged HTML with <ins>/<del> markers.

(function() {
    'use strict';

    // --- Phase 1: Tokenizer ---

    function htmlToTokens(html) {
        var tokens = [];
        var mode = 'char'; // 'char' | 'tag' | 'whitespace'
        var current = '';

        for (var i = 0; i < html.length; i++) {
            var ch = html[i];

            if (mode === 'tag') {
                current += ch;
                if (ch === '>') {
                    tokens.push(current);
                    current = '';
                    mode = 'char';
                }
            } else if (ch === '<') {
                if (current.length > 0) {
                    tokens.push(current);
                }
                current = '<';
                mode = 'tag';
            } else if (/\s/.test(ch)) {
                if (mode !== 'whitespace') {
                    if (current.length > 0) {
                        tokens.push(current);
                    }
                    current = '';
                    mode = 'whitespace';
                }
                current += ch;
            } else {
                if (mode === 'whitespace') {
                    if (current.length > 0) {
                        tokens.push(current);
                    }
                    current = '';
                }
                mode = 'char';
                current += ch;
            }
        }
        if (current.length > 0) {
            tokens.push(current);
        }
        return tokens;
    }

    function isTag(token) {
        return token.length > 0 && token[0] === '<' && token[token.length - 1] === '>';
    }

    function isWhitespace(token) {
        return /^\s+$/.test(token);
    }

    // Strip attributes from tags for comparison purposes
    function stripTagAttributes(token) {
        if (!isTag(token)) return token;
        var m = token.match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)/);
        if (!m) return token;
        var isClosing = token[1] === '/';
        var isSelfClosing = token[token.length - 2] === '/';
        if (isClosing) return '</' + m[1] + '>';
        if (isSelfClosing) return '<' + m[1] + '/>';
        return '<' + m[1] + '>';
    }

    // --- Phase 2: Matching (LCS-based block matching) ---

    function createIndex(tokens) {
        var index = {};
        for (var i = 0; i < tokens.length; i++) {
            var key = stripTagAttributes(tokens[i]);
            if (!index[key]) index[key] = [];
            index[key].push(i);
        }
        return index;
    }

    function findMatchingBlocks(beforeTokens, afterTokens) {
        var matches = [];
        recursivelyFindMatchingBlocks(
            beforeTokens, afterTokens,
            0, beforeTokens.length,
            0, afterTokens.length,
            createIndex(beforeTokens),
            matches
        );
        // Sort by afterStart
        matches.sort(function(a, b) { return a.afterStart - b.afterStart; });
        return matches;
    }

    function recursivelyFindMatchingBlocks(beforeTokens, afterTokens, beforeStart, beforeEnd, afterStart, afterEnd, beforeIndex, matches) {
        var match = findLongestMatch(beforeTokens, afterTokens, beforeStart, beforeEnd, afterStart, afterEnd, beforeIndex);
        if (!match) return;

        if (match.beforeStart > beforeStart && match.afterStart > afterStart) {
            recursivelyFindMatchingBlocks(beforeTokens, afterTokens, beforeStart, match.beforeStart, afterStart, match.afterStart, beforeIndex, matches);
        }
        matches.push(match);
        var matchBeforeEnd = match.beforeStart + match.length;
        var matchAfterEnd = match.afterStart + match.length;
        if (matchBeforeEnd < beforeEnd && matchAfterEnd < afterEnd) {
            recursivelyFindMatchingBlocks(beforeTokens, afterTokens, matchBeforeEnd, beforeEnd, matchAfterEnd, afterEnd, beforeIndex, matches);
        }
    }

    function findLongestMatch(beforeTokens, afterTokens, beforeStart, beforeEnd, afterStart, afterEnd, beforeIndex) {
        var bestBeforeStart = beforeStart;
        var bestAfterStart = afterStart;
        var bestLength = 0;

        // matchLengths[beforeIdx] = current run length ending at beforeIdx
        var matchLengths = {};

        for (var j = afterStart; j < afterEnd; j++) {
            var key = stripTagAttributes(afterTokens[j]);
            var newMatchLengths = {};
            var positions = beforeIndex[key] || [];

            for (var k = 0; k < positions.length; k++) {
                var i = positions[k];
                if (i < beforeStart) continue;
                if (i >= beforeEnd) continue;

                var prevLen = (i > 0 && matchLengths[i - 1]) ? matchLengths[i - 1] : 0;
                var newLen = prevLen + 1;
                newMatchLengths[i] = newLen;

                if (newLen > bestLength) {
                    bestLength = newLen;
                    bestBeforeStart = i - newLen + 1;
                    bestAfterStart = j - newLen + 1;
                }
            }
            matchLengths = newMatchLengths;
        }

        if (bestLength === 0) return null;
        return { beforeStart: bestBeforeStart, afterStart: bestAfterStart, length: bestLength };
    }

    // --- Phase 3: Calculate Operations ---

    function calculateOperations(beforeTokens, afterTokens) {
        var matchingBlocks = findMatchingBlocks(beforeTokens, afterTokens);
        var operations = [];
        var beforeIdx = 0;
        var afterIdx = 0;

        for (var i = 0; i < matchingBlocks.length; i++) {
            var block = matchingBlocks[i];
            var action = 'none';

            if (beforeIdx < block.beforeStart && afterIdx < block.afterStart) {
                action = 'replace';
            } else if (beforeIdx < block.beforeStart) {
                action = 'delete';
            } else if (afterIdx < block.afterStart) {
                action = 'insert';
            }

            if (action !== 'none') {
                operations.push({
                    action: action,
                    beforeStart: beforeIdx,
                    beforeEnd: block.beforeStart,
                    afterStart: afterIdx,
                    afterEnd: block.afterStart
                });
            }

            operations.push({
                action: 'equal',
                beforeStart: block.beforeStart,
                beforeEnd: block.beforeStart + block.length,
                afterStart: block.afterStart,
                afterEnd: block.afterStart + block.length
            });

            beforeIdx = block.beforeStart + block.length;
            afterIdx = block.afterStart + block.length;
        }

        // Handle remaining tokens after last match
        if (beforeIdx < beforeTokens.length || afterIdx < afterTokens.length) {
            var action = 'none';
            if (beforeIdx < beforeTokens.length && afterIdx < afterTokens.length) {
                action = 'replace';
            } else if (beforeIdx < beforeTokens.length) {
                action = 'delete';
            } else {
                action = 'insert';
            }
            operations.push({
                action: action,
                beforeStart: beforeIdx,
                beforeEnd: beforeTokens.length,
                afterStart: afterIdx,
                afterEnd: afterTokens.length
            });
        }

        return postProcessOperations(operations, beforeTokens, afterTokens);
    }

    // Merge consecutive replace operations and handle single whitespace edges
    function postProcessOperations(ops, beforeTokens, afterTokens) {
        var result = [];
        for (var i = 0; i < ops.length; i++) {
            var op = ops[i];
            // Skip empty equal ops
            if (op.action === 'equal' && op.beforeStart === op.beforeEnd) continue;

            // Check if a single-whitespace equal between two replaces should be absorbed
            if (op.action === 'equal' && op.beforeEnd - op.beforeStart === 1) {
                var token = beforeTokens[op.beforeStart];
                if (isWhitespace(token)) {
                    var prev = result.length > 0 ? result[result.length - 1] : null;
                    var next = i + 1 < ops.length ? ops[i + 1] : null;
                    if (prev && next && prev.action === 'replace' && next.action === 'replace') {
                        // Absorb whitespace into the previous replace
                        prev.beforeEnd = op.beforeEnd;
                        prev.afterEnd = op.afterEnd;
                        continue;
                    }
                }
            }
            result.push(op);
        }
        return result;
    }

    // --- Phase 4: Render ---

    // Wrap non-tag tokens in the given tag (ins or del) with diff marker class
    function wrapTokens(tokens, start, end, tagName) {
        var out = '';
        var inWrap = false;
        for (var i = start; i < end; i++) {
            var token = tokens[i];
            if (isTag(token)) {
                if (inWrap) {
                    out += '</' + tagName + '>';
                    inWrap = false;
                }
                out += token;
            } else {
                if (!inWrap) {
                    out += '<' + tagName + ' class="mods-diff">';
                    inWrap = true;
                }
                out += token;
            }
        }
        if (inWrap) {
            out += '</' + tagName + '>';
        }
        return out;
    }

    function renderOperations(beforeTokens, afterTokens, operations) {
        var html = '';
        for (var i = 0; i < operations.length; i++) {
            var op = operations[i];
            switch (op.action) {
                case 'equal':
                    for (var j = op.afterStart; j < op.afterEnd; j++) {
                        html += afterTokens[j];
                    }
                    break;
                case 'insert':
                    html += wrapTokens(afterTokens, op.afterStart, op.afterEnd, 'ins');
                    break;
                case 'delete':
                    html += wrapTokens(beforeTokens, op.beforeStart, op.beforeEnd, 'del');
                    break;
                case 'replace':
                    html += wrapTokens(beforeTokens, op.beforeStart, op.beforeEnd, 'del');
                    html += wrapTokens(afterTokens, op.afterStart, op.afterEnd, 'ins');
                    break;
            }
        }
        return html;
    }

    // --- Public API ---

    window.__modsHtmlDiff = function(beforeHTML, afterHTML) {
        var beforeTokens = htmlToTokens(beforeHTML);
        var afterTokens = htmlToTokens(afterHTML);
        var operations = calculateOperations(beforeTokens, afterTokens);
        return renderOperations(beforeTokens, afterTokens, operations);
    };
})();
