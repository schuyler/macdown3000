// Image load detection for remote images without dimensions
// Monitors images that lack width/height attributes and notifies when they complete loading

(function() {
    if (typeof ImageLoadListener === 'undefined') {
        return;
    }

    // Find all images without width/height attributes (remote images)
    var images = document.querySelectorAll('img:not([width])');
    var totalImages = images.length;
    var loadedImages = 0;
    var timeoutId = null;
    var completed = false;

    function notifyComplete() {
        if (completed) return;
        completed = true;
        if (timeoutId) clearTimeout(timeoutId);
        ImageLoadListener.invokeCallbackForKey_('Complete');
    }

    // If no images without dimensions, complete immediately
    if (totalImages === 0) {
        notifyComplete();
        return;
    }

    function onImageLoadOrError() {
        loadedImages++;
        if (loadedImages >= totalImages) {
            notifyComplete();
        }
    }

    // Attach listeners to images
    for (var i = 0; i < images.length; i++) {
        var img = images[i];
        if (img.complete) {
            // Image already loaded (cached)
            loadedImages++;
        } else {
            // Image still loading - attach listeners
            img.addEventListener('load', onImageLoadOrError);
            img.addEventListener('error', onImageLoadOrError);
        }
    }

    // Check if all images were already loaded
    if (loadedImages >= totalImages) {
        notifyComplete();
        return;
    }

    // Fallback timeout (5 seconds) - sync anyway if images take too long
    timeoutId = setTimeout(function() {
        if (!completed) {
            console.warn('MacDown: Image load timeout after 5s, syncing scroll position anyway');
            notifyComplete();
        }
    }, 5000);
})();
