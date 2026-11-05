ALL: version.h

version.h: FORCE
	bash ../../Tools/generate_version_header.sh

.PHONY: install clean distclean FORCE

FORCE:

install: ALL

clean:
	-rm version.h 2>/dev/null

distclean: clean
