SASS = node_modules/.bin/sass
TOKENS = node_modules/@primer/primitives/dist/css/base/size/size.css \
	node_modules/@primer/primitives/dist/css/functional/themes/light.css

target = ../../MacDown/Resources/Styles/GitHub-2020.css

all: $(target)

# Xcode consumes the reviewed, committed stylesheet without requiring Node.
$(target):
	@test -f "$@" || { \
		echo "Missing committed stylesheet: $@. Run make regenerate explicitly." >&2; \
		exit 1; }

# Regeneration is a developer action, never an implicit side effect of a build.
regenerate: index.sass tokens.js package-lock.json $(SASS) $(TOKENS)
	@set -e; raw=; body=; css=; \
	trap 'rm -f "$$raw" "$$body" "$$css"' EXIT; \
	trap 'exit 1' HUP INT TERM; \
	raw=$$(mktemp "$(target).sass.XXXXXX"); \
	body=$$(mktemp "$(target).body.XXXXXX"); \
	css=$$(mktemp "$(target).css.XXXXXX"); \
	$(SASS) --load-path node_modules index.sass > "$$raw"; \
	sed 's/\.markdown-body/body/g' "$$raw" > "$$body"; \
	node tokens.js $(TOKENS) < "$$body" > "$$css"; \
	chmod 644 "$$css"; \
	mv "$$css" "$(target)"

clean:
	$(RM) build.css build.body.css build.out.css

.PHONY: all regenerate clean
