all: difference-engine.pdf

%.pdf: %.tex
	@pdflatex $<
	pdflatex $<

clean:
	rm -f difference-engine.pdf *.aux *.log *.out *.toc *.bbl *.blg
