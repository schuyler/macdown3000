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

            // After initial timeout, continue monitoring for late image loads
            // This handles lazy-loaded images that load after the timeout
            setupLateImageMonitoring();
        }
    }, 5000);

    // Monitor for images that load after the initial timeout
    // This handles WebKit lazy loading and slow network conditions
    var lateLoadCount = 0;
    var maxLateLoads = 5;  // Prevent infinite re-syncs
    var debounceTimer = null;

    function setupLateImageMonitoring() {
        function onLateImageLoad() {
            // Debounce: wait 250ms for additional images to load together
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(function() {
                if (lateLoadCount >= maxLateLoads) {
                    console.log('MacDown: Reached max late image load re-syncs (' + maxLateLoads + ')');
                    return;
                }
                lateLoadCount++;
                console.log('MacDown: Late image loaded, re-syncing scroll position (' + lateLoadCount + '/' + maxLateLoads + ')');

                // Notify Objective-C to re-sync scroll positions
                ImageLoadListener.invokeCallbackForKey_('LateImageLoad');
            }, 250);
        }

        // Attach persistent listeners to images that haven't loaded yet
        for (var i = 0; i < images.length; i++) {
            var img = images[i];
            if (!img.complete) {
                img.addEventListener('load', onLateImageLoad);
                img.addEventListener('error', onLateImageLoad);
            }
        }

        // Cleanup on page unload to prevent memory leaks
        window.addEventListener('unload', function() {
            for (var i = 0; i < images.length; i++) {
                images[i].removeEventListener('load', onLateImageLoad);
                images[i].removeEventListener('error', onLateImageLoad);
            }
        });
    }
})();
