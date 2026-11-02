(function () {

MathJax.Hub.Config({
	'showProcessingMessages': false,
	'messageStyle': 'none',

	// The HTML-CSS output jax prefers fonts installed on the machine over
	// MathJax's own, and its default availableFonts list names STIX. macOS
	// ships STIX 1.x as system-reserved faces that WebKit resolves by name, so
	// the preview picks them up and typesets digits and operators in
	// STIXGeneral-Regular — a Times-metric face indistinguishable from body
	// text. Browsers that do not enumerate those faces, such as Firefox, load
	// MathJax's TeX fonts instead and render the same document correctly.
	//
	// Emptying the list makes the preview do the same. preferredFont is nulled
	// alongside it because MathJax tests the preferred font even when it is
	// absent from availableFonts, so the list alone would still take the local
	// path on a machine carrying MathJax's own TeX fonts.
	'HTML-CSS': {
		'availableFonts': [],
		'preferredFont': null
	}
});

if (typeof MathJaxListener !== 'undefined') {
	MathJax.Hub.Register.StartupHook('End', function () {
		MathJaxListener.invokeCallbackForKey_('End');
	});
}

})();
