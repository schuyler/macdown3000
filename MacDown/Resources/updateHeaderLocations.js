/**
 * Detects reference points (headers and standalone images) in the preview document.
 * Returns reference point y-coordinates and preview geometry for scroll synchronization.
 *
 * Standalone images are defined as:
 * - An image alone in a paragraph
 * - An image wrapped in a link that's alone in a paragraph
 * - An image that's the only child of its parent element
 *
 * @returns {{locations: number[], contentHeight: number, visibleHeight: number}}
 *   locations: document-absolute y-coordinates of reference points;
 *   contentHeight: document.body.scrollHeight in CSS pixels;
 *   visibleHeight: window.innerHeight in CSS pixels.
 */
(function() {
    try {
        if (!document.body) return {locations: [], contentHeight: 0, visibleHeight: 0};

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

        // Return y-coordinates (document-absolute) for all reference points.
        // Uses window.scrollY + rect.top so the result is independent of current scroll position.
        // No pre-filtering - the syncScrollers algorithm handles end-of-document cases.
        var locations = result.map(function(item) {
            var rect = item.node.getBoundingClientRect();
            return window.scrollY + rect.top;
        });
        return {
            locations: locations,
            contentHeight: document.body.scrollHeight,
            visibleHeight: window.innerHeight
        };
    } catch (e) {
        return {locations: [], contentHeight: 0, visibleHeight: 0};
    }
})()
