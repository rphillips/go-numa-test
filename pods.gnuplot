set terminal png size 1200,600 enhanced font "Arial,12"
set output "pods.png"

set title "NUMA-Pinned vs Unpinned Pod Performance\nIdentical Go workloads on AMD EPYC Genoa (r7a.48xlarge, 2 NUMA nodes)" font "Arial,14"

set ylabel "Per-Pod Throughput (GB/s)" font "Arial,12"
set yrange [0:65]
set xrange [-0.5:10.5]
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"

set style fill solid 0.85 border -1
set boxwidth 0.7

# X-axis labels
set xtics ( \
    "Pinned\nPod A\n(node 0)" 0, \
    "Pinned\nPod B\n(node 1)" 1, \
    "" 2, \
    "Unpinned\nPod A" 3.5, \
    "Unpinned\nPod B" 4.5, \
    "" 5.5, \
    "Unpinned\nPod 0" 6.5, \
    "Unpinned\nPod 1" 7.5, \
    "Unpinned\nPod 2" 8.5, \
    "Unpinned\nPod 3" 9.5 \
) font "Arial,10"

# Group labels
set label "Test 2\n2 Pods, NUMA-Pinned" at 0.5,-10 center font "Arial,11,Bold" tc rgb "#2e7d32"
set label "Test 3\n2 Pods, Unpinned" at 4,-10 center font "Arial,11,Bold" tc rgb "#e65100"
set label "Test 4\n4 Pods, Unpinned" at 8,-10 center font "Arial,11,Bold" tc rgb "#b71c1c"

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
set label "44.15" at 0,44.15+1 center font "Arial,9"
set label "44.47" at 1,44.47+1 center font "Arial,9"
set label "43.80" at 3.5,43.80+1 center font "Arial,9"
set label "54.81" at 4.5,54.81+1 center font "Arial,9"
set label "39.92" at 6.5,39.92+1 center font "Arial,9"
set label "27.61" at 7.5,27.61+1 center font "Arial,9"
set label "52.29" at 8.5,52.29+1 center font "Arial,9"
set label "40.67" at 9.5,40.67+1 center font "Arial,9"

# Separator lines between groups
set arrow from 2.25,0 to 2.25,62 nohead dt 2 lw 1 lc rgb "#cccccc"
set arrow from 5.75,0 to 5.75,62 nohead dt 2 lw 1 lc rgb "#cccccc"

plot '-' using 1:2 with boxes lc rgb "#2e7d32" title "NUMA-Pinned", \
     '-' using 1:2 with boxes lc rgb "#e65100" title "Unpinned (2 pods)", \
     '-' using 1:2 with boxes lc rgb "#b71c1c" title "Unpinned (4 pods)"
0   44.15
1   44.47
e
3.5 43.80
4.5 54.81
e
6.5 39.92
7.5 27.61
8.5 52.29
9.5 40.67
e
