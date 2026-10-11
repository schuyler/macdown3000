SASS = node_modules/.bin/sass

target = ../../MacDown/Resources/Styles/GitHub-2020.css

all: $(target)

$(target): index.sass package-lock.json Makefile $(SASS)
	@set -e; raw=$$(mktemp "$@.sass.XXXXXX"); css=$$(mktemp "$@.css.XXXXXX"); \
	trap 'rm -f "$$raw" "$$css"' EXIT HUP INT TERM; \
	$(SASS) --load-path node_modules $< > "$$raw"; \
	sed 's/\.markdown-body/body/g' "$$raw" > "$$css"; \
	mv "$$css" "$@"

clean:
	$(RM) $(target)

.PHONY: all clean
