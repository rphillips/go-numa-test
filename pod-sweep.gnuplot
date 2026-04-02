set terminal png size 1600,1200 enhanced font "Arial,13"
set output "pod-sweep.png"

$DATA << EOD
1    44.74  44.74  44.74  44.74  1.0
2    44.63  44.83  44.73  89.46  1.0
4    29.19  45.03  39.05  156.21 1.5
8    24.64  43.39  37.19  297.50 1.8
16   13.02  38.25  22.90  366.38 2.9
24   5.39   22.00  9.97   239.30 4.1
32   2.86   11.60  5.48   175.33 4.1
48   1.98   30.85  4.48   215.03 15.6
64   1.26   19.96  3.14   200.80 15.8
96   0.79   14.77  2.01   192.73 18.7
128  0.25   22.43  1.63   209.04 89.7
200  0.18   29.91  1.26   252.58 166.2
EOD

set multiplot

# ============================================================
# Top panel: Per-pod average + combined throughput
# ============================================================
set origin 0.0, 0.52
set size 1.0, 0.48

set tmargin 5
set bmargin 4
set lmargin 12
set rmargin 12

set title "Pod Density Saturation Curve\nGOMAXPROCS=4 per pod, AMD EPYC Genoa (r7a.48xlarge, 2 NUMA nodes)" font "Arial,16"

set xlabel ""
set ylabel "Per-Pod Avg Throughput (GB/s)" font "Arial,13"
set y2label "Combined Throughput (GB/s)" font "Arial,13"
set yrange [0:50]
set y2range [0:400]
set xrange [0.5:220]
set logscale x 2
set xtics ("1" 1, "2" 2, "4" 4, "8" 8, "16" 16, "24" 24, "32" 32, "48" 48, "64" 64, "96" 96, "128" 128, "200" 200) font "Arial,11"
set format x ""
set ytics nomirror
set y2tics
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"

# Single-core baseline
set arrow from 0.5,4.40 to 220,4.40 nohead dt 3 lw 1.5 lc rgb "#888888"
set label "Single-core baseline (4.40 GB/s)" at 60,6.5 font "Arial,10" tc rgb "#888888" center

# Saturation annotation
set arrow from 16,22.90 to 16,0 nohead dt 2 lw 2 lc rgb "#cc0000"
set label "Saturation\n(16 pods)" at 16,30 center font "Arial,11" tc rgb "#cc0000"

plot $DATA using 1:4 axes x1y1 with linespoints pt 7 ps 1.2 lw 2.5 lc rgb "#1565c0" title "Per-Pod Avg (GB/s)", \
     $DATA using 1:5 axes x1y2 with linespoints pt 9 ps 1.2 lw 2.5 lc rgb "#2e7d32" title "Combined (GB/s)"

# ============================================================
# Bottom panel: Spread (max/min ratio)
# ============================================================
unset arrow
unset label

set origin 0.0, 0.0
set size 1.0, 0.50

set tmargin 2
set bmargin 6
set lmargin 12
set rmargin 12

unset title
unset y2label
unset y2tics

set xlabel "Number of Pods" font "Arial,14"
set ylabel "Spread (max/min ratio)" font "Arial,13"
set yrange [0:180]
set xrange [0.5:220]
set xtics ("1" 1, "2" 2, "4" 4, "8" 8, "16" 16, "24" 24, "32" 32, "48" 48, "64" 64, "96" 96, "128" 128, "200" 200) font "Arial,11"
set format x "%g"
set ytics mirror
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"

# Phase annotations
set object 1 rect from 0.5,0 to 12,180 fc rgb "#e8f5e9" fs solid 0.3 behind
set label "Linear\nscaling" at 3,160 center font "Arial,10" tc rgb "#2e7d32"

set object 2 rect from 12,0 to 20,180 fc rgb "#fff3e0" fs solid 0.3 behind
set label "Peak" at 16,160 center font "Arial,10" tc rgb "#e65100"

set object 3 rect from 20,0 to 220,180 fc rgb "#ffebee" fs solid 0.3 behind
set label "Collapse" at 80,160 center font "Arial,10" tc rgb "#b71c1c"

plot $DATA using 1:6 with linespoints pt 7 ps 1.2 lw 2.5 lc rgb "#c62828" title "Spread (max/min)"

unset multiplot
