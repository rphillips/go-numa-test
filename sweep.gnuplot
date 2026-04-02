set terminal png size 1200,800 enhanced font "Arial,12"
set output "sweep.png"

set multiplot layout 2,1 title "GOMAXPROCS Scaling on AMD EPYC Genoa (r7a.48xlarge, 192 vCPUs, 2 NUMA nodes)\nGo issue #78044 — NUMA-unaware runtime" font "Arial,14"

# --- Top plot: Aggregate throughput ---
set tmargin 3
set bmargin 0
set lmargin 12
set rmargin 8

set xrange [0:196]
set yrange [0:80]
set xtics format ""
set ylabel "Aggregate Throughput (GB/s)" font "Arial,12"
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"
set grid xtics lt 0 lw 0.5 lc rgb "#cccccc"

# NUMA boundary annotation
set arrow from 96,0 to 96,80 nohead dt 2 lw 2 lc rgb "#cc0000"
set label "NUMA node boundary (96 CPUs)" at 98,75 font "Arial,10" tc rgb "#cc0000"

# Saturation zone
set object 1 rect from 16,0 to 196,80 fc rgb "#fff3e0" fs solid 0.3 behind
set label "Memory bandwidth saturated" at 100,8 font "Arial,10" tc rgb "#996600"

plot "sweep.dat" using 1:2 with points pt 7 ps 0.6 lc rgb "#1565c0" notitle, \
     "sweep.dat" using 1:2 smooth bezier lw 2 lc rgb "#1565c0" title "Aggregate GB/s"

# --- Bottom plot: Per-core efficiency ---
unset arrow
unset label
unset object 1

set tmargin 0
set bmargin 4

set xrange [0:196]
set yrange [0:5]
set xtics format "%g" font "Arial,10"
set xlabel "GOMAXPROCS" font "Arial,12"
set ylabel "Per-Core Throughput (GB/s)" font "Arial,12"

# NUMA boundary
set arrow from 96,0 to 96,5 nohead dt 2 lw 2 lc rgb "#cc0000"
set label "NUMA boundary" at 98,4.7 font "Arial,10" tc rgb "#cc0000"

# Annotations
set label "94% efficiency loss\n(4.40 → 0.27 GB/s/core)" at 120,2.5 font "Arial,11" tc rgb "#b71c1c"
set label "50% lost by\n24 cores" at 28,3.2 font "Arial,10" tc rgb "#e65100"
set arrow from 24,2.8 to 24,2.259 head lw 1.5 lc rgb "#e65100"

plot "sweep.dat" using 1:3 with points pt 7 ps 0.6 lc rgb "#c62828" notitle, \
     "sweep.dat" using 1:3 smooth bezier lw 2 lc rgb "#c62828" title "Per-Core GB/s", \
     "sweep.dat" using 1:(4.398) with lines dt 3 lw 1 lc rgb "#888888" title "Ideal (single-core rate)"

unset multiplot
