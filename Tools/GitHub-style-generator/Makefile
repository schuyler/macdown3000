SASS = node_modules/.bin/sass
TOKENS = node_modules/@primer/primitives/dist/css/base/size/size.css \
	node_modules/@primer/primitives/dist/css/functional/themes/light.css

target = ../../MacDown/Resources/Styles/GitHub-2020.css

all: $(target)

$(target): index.sass tokens.js package-lock.json
	$(SASS) --load-path node_modules $< > build.css
	sed s/.markdown-body/body/ build.css > build.body.css
	node tokens.js $(TOKENS) < build.body.css > build.out.css
	mv build.out.css $@
	$(RM) build.css build.body.css

clean:
	$(RM) $(target) build.css build.body.css build.out.css

.PHONY: all clean
