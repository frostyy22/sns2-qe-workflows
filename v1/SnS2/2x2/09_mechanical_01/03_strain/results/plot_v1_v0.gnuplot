set terminal pngcairo size 1500,650 enhanced font "Sans,14"
set output "SnS2/2x2/09_mechanical_01/03_strain/results/v1_vs_v0.png"

set datafile separator comma
set key top center horizontal
set grid xtics ytics lc rgb "#dddddd" lw 1
set border lw 1.2
set xtics (-5,-3,-1,0,1,3,5)
set multiplot layout 1,2 margins 0.07,0.98,0.14,0.88 spacing 0.10,0.08

set title "Relative energy"
set xlabel "Biaxial strain (%)"
set ylabel "Delta E (eV per 2x2 cell)"
set yrange [0:*]
plot \
  "SnS2/2x2/09_mechanical_01/03_strain/results/scf_results.csv" every ::1 using 1:9 with linespoints lw 3 pt 7 ps 1.1 lc rgb "#0072B2" title "v1 (PAW)", \
  "/home/frost/projects/dft_SnS2/v0/SnS2/2x2/09_mechanical_01/03_strain/results/scf_results.csv" every ::1 using 1:9 with linespoints lw 3 pt 5 ps 1.1 dt 2 lc rgb "#D55E00" title "v0 (USPP)"

set title "In-plane stress"
set xlabel "Biaxial strain (%)"
set ylabel "Mean of sigma_xx and sigma_yy (kbar)"
set yrange [*:*]
set arrow 1 from graph 0, first 0 to graph 1, first 0 nohead dt 3 lw 1.5 lc rgb "#555555"
plot \
  "SnS2/2x2/09_mechanical_01/03_strain/results/scf_results.csv" every ::1 using 1:(($13+$14)/2) with linespoints lw 3 pt 7 ps 1.1 lc rgb "#0072B2" title "v1 (PAW)", \
  "/home/frost/projects/dft_SnS2/v0/SnS2/2x2/09_mechanical_01/03_strain/results/scf_results.csv" every ::1 using 1:(($13+$14)/2) with linespoints lw 3 pt 5 ps 1.1 dt 2 lc rgb "#D55E00" title "v0 (USPP)"

unset multiplot
