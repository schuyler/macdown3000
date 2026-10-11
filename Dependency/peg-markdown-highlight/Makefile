ALL : pmh_parser.c

GREGDIR=greg
GREG=$(GREGDIR)/greg

$(GREG): $(GREGDIR)/greg.c $(GREGDIR)/compile.c $(GREGDIR)/tree.c $(GREGDIR)/greg.h $(GREGDIR)/Makefile
	$(MAKE) -C $(GREGDIR)

pmh_parser_core.c : pmh_grammar.leg $(GREG)
	$(GREG) -o $@ $<

pmh_parser.c : pmh_parser_core.c pmh_parser_head.c pmh_parser_foot.c tools/combine_parser_files.sh
	./tools/combine_parser_files.sh > $@.tmp && mv $@.tmp $@

.PHONY: build install clean distclean

build install: ALL

clean:
	rm -f pmh_parser_core.c pmh_parser.c *.o; \
	rm -rf *.dSYM; \
	$(MAKE) -C $(GREGDIR) spotless

distclean: clean