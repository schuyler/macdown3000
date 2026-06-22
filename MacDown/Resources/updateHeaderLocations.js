/**
 * Detects reference points (headers and standalone images) in the preview document.
 * Returns parallel arrays of y-coordinates and kind codes (in document order) for
 * scroll synchronization.
 *
 * Standalone images are defined as:
 * - An image alone in a paragraph
 * - An image wrapped in a link that's alone in a paragraph
 * - An image that's the only child of its parent element
 *
 * Issue #436: The y-coordinates alone are not enough to keep the editor and preview
 * in sync, because the editor (regex over markdown) and the preview (this DOM query)
 * can disagree about which reference points exist mid-document. Each reference point is
 * therefore tagged with a "kind" code so the ObjC side can align the two sequences:
 *   - image  -> 0
 *   - header -> header level (h1 -> 1, h2 -> 2, ... h6 -> 6)
 *
 * @returns {{ys: Array<number>, kinds: Array<number>}} Parallel arrays of y-coordinates
 *          and kind codes for reference points, in document order.
 */
(function() {
    try {
        if (!document.body) return {ys: [], kinds: []};

        var headers = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
        var images = document.querySelectorAll('img');
        var result = [];

        // Collect all headers
        for (var i = 0; i < headers.length; i++) {
            result.push({node: headers[i], type: 'header'});
        }

        // Filter images to only include standalone images
        for (var i = 0; i < images.length; i++) {
            var img = images[i];
            var parent = img.parentElement;
            var isStandalone = false;

            if (!parent) {
                isStandalone = false;
            } else if (parent.tagName === 'P') {
                // Count images in paragraph
                var imgCount = 0;
                for (var j = 0; j < parent.children.length; j++) {
                    if (parent.children[j].tagName === 'IMG') imgCount++;
                }
                isStandalone = (imgCount === 1);
            } else if (parent.children.length === 1) {
                // Image is the only child
                isStandalone = true;
            } else if (parent.tagName === 'A' && parent.children.length === 1) {
                // Image wrapped in link
                var grandparent = parent.parentElement;
                if (grandparent && grandparent.tagName === 'P') {
                    // Count images/links-with-images in grandparent paragraph
                    var imgCount = 0;
                    for (var j = 0; j < grandparent.children.length; j++) {
                        var node = grandparent.children[j];
                        if (node.tagName === 'IMG' ||
                            (node.tagName === 'A' && node.children.length === 1 && node.children[0].tagName === 'IMG')) {
                            imgCount++;
                        }
                    }
                    isStandalone = (imgCount === 1);
                } else if (grandparent && grandparent.children.length === 1) {
                    isStandalone = true;
                }
            }

            if (isStandalone) {
                result.push({node: img, type: 'image'});
            }
        }

        // Sort by document order
        result.sort(function(a, b) {
            var position = a.node.compareDocumentPosition(b.node);
            if (position & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
            if (position & Node.DOCUMENT_POSITION_PRECEDING) return 1;
            return 0;  // Same node or disconnected
        });

        // Return y-coordinates (document-absolute) and kind codes for all reference points.
        // Uses window.scrollY + rect.top so the result is independent of current scroll position.
        // No pre-filtering - the syncScrollers algorithm handles end-of-document cases.
        var ys = [];
        var kinds = [];
        for (var k = 0; k < result.length; k++) {
            var item = result[k];
            var rect = item.node.getBoundingClientRect();
            ys.push(window.scrollY + rect.top);
            if (item.type === 'image') {
                kinds.push(0);
            } else {
                // tagName is like 'H3'; the second character is the header level.
                var level = parseInt(String(item.node.tagName).charAt(1), 10);
                kinds.push((level >= 1 && level <= 6) ? level : 1);
            }
        }
        return {ys: ys, kinds: kinds};
    } catch (e) {
        return {ys: [], kinds: []};
    }
})()
