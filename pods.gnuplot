set terminal png size 1400,900 enhanced font "Arial,12"
set output "pods.png"

# Inline datablocks for the bar charts
$PINNED << EOD
0   44.15
1   44.47
EOD

$UNPINNED2 << EOD
3.5 43.80
4.5 54.81
EOD

$UNPINNED4 << EOD
6.5 39.92
7.5 27.61
8.5 52.29
9.5 40.67
EOD

set multiplot layout 2,1

# ============================================================
# Top panel: Tests 2, 3, 4
# ============================================================
set tmargin 4
set bmargin 1
set lmargin 12
set rmargin 4

set title "NUMA-Pinned vs Unpinned Pod Performance\nIdentical Go workloads on AMD EPYC Genoa (r7a.48xlarge, 2 NUMA nodes)" font "Arial,14"

set ylabel "Per-Pod Throughput (GB/s)" font "Arial,12"
set yrange [0:65]
set xrange [-0.5:10.5]
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"

set style fill solid 0.85 border -1
set boxwidth 0.7

set xtics ( \
    "Pinned\nPod A\n(node 0)" 0, \
    "Pinned\nPod B\n(node 1)" 1, \
    "" 2.25, \
    "Unpinned\nPod A" 3.5, \
    "Unpinned\nPod B" 4.5, \
    "" 5.75, \
    "Unpinned\nPod 0" 6.5, \
    "Unpinned\nPod 1" 7.5, \
    "Unpinned\nPod 2" 8.5, \
    "Unpinned\nPod 3" 9.5 \
) font "Arial,10"

# Bandwidth ceiling line
set arrow from -0.5,44.3 to 10.5,44.3 nohead dt 3 lw 1.5 lc rgb "#888888"
set label "Per-NUMA-node bandwidth (~44 GB/s)" at 5.5,46 font "Arial,10" tc rgb "#888888" center

# Variance annotations
set label "Symmetric" at 0.5,49 center font "Arial,11" tc rgb "#2e7d32"
set label "25% gap" at 4,59 center font "Arial,11" tc rgb "#e65100"
set arrow from 3.5,57 to 4.5,57 heads lw 1.5 lc rgb "#e65100"
set label "1.9x spread" at 8,56 center font "Arial,11" tc rgb "#b71c1c"
set arrow from 7.5,54 to 8.5,54 heads lw 1.5 lc rgb "#b71c1c"

# Value labels on bars
set label "44.15" at 0,44.15+1.5 center font "Arial,9"
set label "44.47" at 1,44.47+1.5 center font "Arial,9"
set label "43.80" at 3.5,43.80+1.5 center font "Arial,9"
set label "54.81" at 4.5,54.81+1.5 center font "Arial,9"
set label "39.92" at 6.5,39.92+1.5 center font "Arial,9"
set label "27.61" at 7.5,27.61+1.5 center font "Arial,9"
set label "52.29" at 8.5,52.29+1.5 center font "Arial,9"
set label "40.67" at 9.5,40.67+1.5 center font "Arial,9"

# Separator lines between groups
set arrow from 2.25,0 to 2.25,62 nohead dt 2 lw 1 lc rgb "#cccccc"
set arrow from 5.75,0 to 5.75,62 nohead dt 2 lw 1 lc rgb "#cccccc"

plot $PINNED using 1:2 with boxes lc rgb "#2e7d32" title "Test 2: 2 Pods NUMA-Pinned", \
     $UNPINNED2 using 1:2 with boxes lc rgb "#e65100" title "Test 3: 2 Pods Unpinned", \
     $UNPINNED4 using 1:2 with boxes lc rgb "#b71c1c" title "Test 4: 4 Pods Unpinned"

# ============================================================
# Bottom panel: Test 5 — 200 pods sorted by throughput
# ============================================================
unset arrow
unset label
unset title

set tmargin 2
set bmargin 4
set lmargin 12
set rmargin 4

set title "Test 5: 200 Pods Unpinned (GOMAXPROCS=4 each)\nSorted by throughput — the NUMA performance lottery" font "Arial,14"

set ylabel "Per-Pod Throughput (GB/s)" font "Arial,12"
set xlabel "Pod rank (sorted worst to best)" font "Arial,12"
set yrange [0:50]
set xrange [0:201]
set xtics auto font "Arial,10"
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"

set boxwidth 0.8
set style fill solid 0.75 border -1

# Reference lines
set arrow from 0,4.40 to 201,4.40 nohead dt 3 lw 1.5 lc rgb "#2e7d32"
set label "Single-core baseline (4.40 GB/s)" at 105,5.8 font "Arial,10" tc rgb "#2e7d32" center

set arrow from 0,2.51 to 201,2.51 nohead dt 2 lw 1.5 lc rgb "#e65100"
set label "Average (2.51 GB/s)" at 60,3.6 font "Arial,10" tc rgb "#e65100" center

# Annotations
set label "236x spread\nMin: 0.19 GB/s\nMax: 44.96 GB/s" at 25,38 font "Arial,11" tc rgb "#b71c1c"
set label "~75% of pods below\nsingle-core performance" at 40,15 font "Arial,11" tc rgb "#b71c1c"

# Plot sorted data from CSV
plot "< tail -n +2 pods200.csv | sort -t, -k2 -n | awk -F, '{print NR, $2}'" \
     using 1:2 with boxes lc rgb "#c62828" notitle

unset multiplot
