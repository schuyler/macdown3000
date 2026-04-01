(function () {

MathJax.Hub.Config({
	'showProcessingMessages': false,
	'messageStyle': 'none'
});

// WKWebView compatibility: Check for webkit message handlers
if (typeof webkit !== 'undefined' && webkit.messageHandlers && webkit.messageHandlers.MathJaxListener) {
	MathJax.Hub.Register.StartupHook('End', function () {
		webkit.messageHandlers.MathJaxListener.postMessage('End');
	});
}

})();
