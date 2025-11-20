/**
 * Detects reference points (headers and standalone images) in the preview document.
 * Returns an array of y-coordinates (relative to document top) for scroll synchronization.
 *
 * Standalone images are defined as:
 * - An image alone in a paragraph
 * - An image wrapped in a link that's alone in a paragraph
 * - An image that's the only child of its parent element
 *
 * @returns {Array<number>} Array of y-coordinates for reference points, in document order
 */
(function() {
    try {
        if (!document.body) return [];

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
            return a.node.compareDocumentPosition(b.node) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
        });

        // Return y-coordinates
        return result.map(function(item) {
            return item.node.getBoundingClientRect().top;
        });
    } catch (e) {
        return [];
    }
})()
