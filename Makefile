SHELL=/bin/sh
DATA1=data/?/*
DATA2=$(shell perl -le '$$_ = "embed/Apt*/*.csv"; print if glob')

all: grandtab-1.tex grandtab-2.tex grandtab.pdf

grandtab.pdf: grandtab-c.tex

grandtab-1.tex:
	@rm -f .temp
	for f in $(DATA1); do\
	  ./ratio-table2.pl $$f >> .temp;\
	  case $$f in\
	  *WATT)\
	    ./ratio-table2.pl -n1 $$f >> .temp;;\
	  *)\
	    ./ratio-table2.pl -n0.1 $$f >> .temp;;\
	  esac;\
	done
	mv .temp $@

grandtab-2.tex: unpack-embed-data
#	./ratio-table2.pl -l30000 $(DATA2) > .temp
	./ratio-table2.pl $(DATA2) > .temp
	mv .temp $@

grandtab-c.tex: grandtab-1.tex grandtab-2.tex color.pl
	./color.pl grandtab-1.tex grandtab-2.tex > .temp
	mv .temp $@

.PHONY: unpack-embed-data
unpack-embed-data:
	@for f in Apt[123]_GT_Plug.zip; do\
	    if [ -r $$f ]; then\
	        env TZ='GMT+0' unzip -u $$f -d embed/;\
	    else\
	        echo "*** warning: some test data missing ($$f)";\
	    fi;\
	done

%.pdf: %.tex
	@which pdflatex >/dev/null\
	    || (echo "*** No pdflatex, cannot build $@"; exit 1)
	pdflatex -halt-on-error $*.tex
	if grep -q Rerun $*.log; then\
	    pdflatex -halt-on-error $*.tex;\
	fi

clean:
	rm -rf embed/Apt[123]_GT_Plug
	rm -rf grandtab.aux grandtab.log grandtab-c.tex
	rm -rf vbinary*.pm
	[ -s grandtab-2.tex ] || rm -rf grandtab-2.tex

distclean: clean
	rm -rf grandtab-[12].tex grandtab.pdf
