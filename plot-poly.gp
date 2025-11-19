filename="poly.data"

set ylabel "Polynomial"; set y2label "Error Percent"
set y2range [-0.5:0.5] ; set y2tics 0.1 ; set ytics nomirror

# Output directly to terminal. Modern terminals should be able to deal with
# it, e.g. konsole
set terminal kittycairo scroll size 800,600

# Draw sampled polynomial, _actual_ polynomial and error of the sample
plot filename with lines    lw 2   title "Original", \
      "" using 1:3 with lines lw 2   title "Iterative approximation", \
      "" using 1:5 axes x1y2         title "Error"
