LATEX	= pdflatex -halt-on-error
BIBTEX	= bibtex
MAKEINDEX = makeindex
COPY = if test -r $(<:%.tex=%.toc); then cp $(<:%.tex=%.toc) $(<:%.tex=%.toc.bak); fi
RM = rm -f
RERUN = "(There were undefined references|Rerun to get (cross-references|the bars) right)"
RERUNBIB = "No file.*\.bbl|Citation.*undefined"
MAKEIDX = "^[^%]*\\makeindex"

define run-latex
		echo $<
	  $(COPY);echo "run a";$(LATEX) $<
	  egrep -q $(MAKEIDX) $< && ($(MAKEINDEX) $(<:%.tex=%);$(COPY);echo "run b";$(LATEX) $<) ; true
	  egrep -c $(RERUNBIB) $(<:%.tex=%.log) && ($(BIBTEX) $(<:%.tex=%);$(COPY);echo "run c";$(LATEX) $<) ; true
	  egrep -q $(RERUN) $(<:%.tex=%.log) && ($(COPY);echo "run d";$(LATEX) $<) ; true
	  egrep -q $(RERUN) $(<:%.tex=%.log) && ($(COPY);echo "run e";$(LATEX) $<) ; true
#	  if cmp -s $(<:%.tex=%.toc) $(<:%.tex=%.toc.bak); then true ;else echo "run f";$(LATEX) $< ; fi
	  $(RM) $(<:%.tex=%.toc.bak)
	  # Display relevant warnings
	  egrep -i "(Reference|Citation).*undefined" $(<:%.tex=%.log) ; true
endef

TEXF	:= $(shell egrep -l '^[^%]*\\begin\{document\}' *.tex)
PDFF	:= $(TEXF:%.tex=%.pdf)
PDFCOPY	:= $(TEXF:%.tex=%.copy.pdf)

all : $(PDFCOPY)

$(PDFF) : $(TEXF) content*.tex
	@$(run-latex)

$(PDFCOPY) : $(PDFF)
	cp -a $(PDFF) $(PDFCOPY)

clean	:
	  -rm -f $(PDFF:%.pdf=%.tex) $(PDFF:%.pdf=%.aux) $(PDFF:%.pdf=%.bbl) $(PDFF:%.pdf=%.blg) $(PDFF:%.pdf=%.log) $(PDFF:%.pdf=%.out) $(PDFF:%.pdf=%.idx) $(PDFF:%.pdf=%.ilg) $(PDFF:%.pdf=%.ind) $(PDFF:%.pdf=%.toc) $(DEP:%.tex=%.aux Rplots.pdf )
