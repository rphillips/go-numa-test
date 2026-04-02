set terminal png size 1400,800 enhanced font "Arial,13"
set output "combined.png"

$DATA << EOD
0  78.43
1  88.62
2  98.61
3  160.49
4  501.47
EOD

set title "Combined Throughput vs Per-Pod Fairness\nAMD EPYC Genoa (r7a.48xlarge, 2 NUMA nodes)" font "Arial,16"

set ylabel "Combined Throughput (GB/s)" font "Arial,14"
set yrange [0:600]
set xrange [-0.6:4.6]
set grid ytics lt 0 lw 0.5 lc rgb "#cccccc"

set style fill solid 0.85 border -1
set boxwidth 0.65

set xtics ( \
    "Test 1\n1 process\nGMP=192" 0, \
    "Test 2\n2 pods pinned\nGMP=96" 1, \
    "Test 3\n2 pods unpinned\nGMP=96" 2, \
    "Test 4\n4 pods unpinned\nGMP=48" 3, \
    "Test 5\n200 pods unpinned\nGMP=4" 4 \
) font "Arial,11"

set bmargin 6

# Per-NUMA-node bandwidth ceiling
set arrow from -0.6,88.6 to 4.6,88.6 nohead dt 3 lw 1.5 lc rgb "#888888"
set label "2-node bandwidth ceiling (~88 GB/s)" at -0.5,80 font "Arial,10" tc rgb "#888888" left

# Value labels above bars
set label "78.43" at 0,78.43+14 center font "Arial,11"
set label "88.62" at 1,88.62+14 center font "Arial,11"
set label "98.61" at 2,98.61+14 center font "Arial,11"
set label "160.49" at 3,160.49+14 center font "Arial,11"
set label "501.47" at 4,501.47+14 center font "Arial,11"

# Spread annotations below value labels
set label "0.7% spread" at 1,88.62+35 center font "Arial,9" tc rgb "#2e7d32"
set label "25% spread" at 2,98.61+35 center font "Arial,9" tc rgb "#e65100"
set label "1.9x spread" at 3,160.49+35 center font "Arial,9" tc rgb "#b71c1c"
set label "236x spread" at 4,501.47+40 center font "Arial,9" tc rgb "#b71c1c"

# Insight annotation
set label "More total bandwidth extracted,\nbut wildly unfair per-pod distribution" \
    at 1.8,450 left font "Arial,12" tc rgb "#b71c1c"
set arrow from 2.8,440 to 3.9,510 head lw 1.5 lc rgb "#b71c1c"

plot $DATA using 1:2 with boxes lc rgb "#1565c0" notitle
