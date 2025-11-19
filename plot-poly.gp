filename="poly.data"

set key left top

set ylabel "Polynomial"; set y2label "Absolute Error"
set y2tics ; set ytics nomirror

# Output directly to terminal. Modern terminals should be able to deal with
# it, e.g. konsole
set terminal kittycairo scroll size 800,600

# Draw sampled polynomial, _actual_ polynomial and error of the sample
plot filename with lines       lw 2     title "Iterative approximation", \
      "" using 1:3 with lines  lw 2     title "Original", \
      "" using 1:4 axes x1y2 with lines lt rgb "orange" title "Absolute Error"
