#!/bin/bash
# Test 5: 200 processes unpinned — simulating dense K8s pod scheduling
#
# Each process runs a single go-default trial with reduced buffer (16MB)
# to avoid OOM. GOMAXPROCS=1 per pod to simulate lightweight pods.
# Total memory: 200 * 16 * 16MB = ~51GB (fits in r7a.48xlarge 1536GB RAM)

BENCH=/tmp/numa-bench
OUTDIR=/tmp/numa-200-pods
NUM_PODS=200
POD_GOMAXPROCS=4
SIZE_MB=16
ITERS=5
RAND_ACCESSES=500000

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

echo "============================================================"
echo "  Test 5: $NUM_PODS Pods Unpinned on $(hostname)"
echo "  GOMAXPROCS=$POD_GOMAXPROCS per pod, ${SIZE_MB}MB buffer"
echo "============================================================"
echo ""
echo "  Launching $NUM_PODS processes..."

# Launch all pods
PIDS=""
for i in $(seq 0 $((NUM_PODS - 1))); do
    GOMAXPROCS=$POD_GOMAXPROCS $BENCH -single -size $SIZE_MB -iters $ITERS -rand-accesses $RAND_ACCESSES \
        > "$OUTDIR/pod-$i.txt" 2>&1 &
    PIDS="$PIDS $!"
done

echo "  Waiting for all $NUM_PODS processes to complete..."
wait $PIDS
echo "  Done."
echo ""

# Collect results
echo "=== Per-Pod Throughput (GB/s) ==="
echo ""

RESULTS=""
TOTAL=0
MIN=999999
MAX=0
COUNT=0

for i in $(seq 0 $((NUM_PODS - 1))); do
    GBPS=$(tail -1 "$OUTDIR/pod-$i.txt" 2>/dev/null)
    if [ -n "$GBPS" ] && [ "$GBPS" != "" ]; then
        RESULTS="$RESULTS $GBPS"
        TOTAL=$(awk "BEGIN {printf \"%.2f\", $TOTAL + $GBPS}")
        MIN=$(awk "BEGIN {if ($GBPS < $MIN) print $GBPS; else print $MIN}")
        MAX=$(awk "BEGIN {if ($GBPS > $MAX) print $GBPS; else print $MAX}")
        COUNT=$((COUNT + 1))
    fi
done

AVG=$(awk "BEGIN {printf \"%.2f\", $TOTAL / $COUNT}")
SPREAD=$(awk "BEGIN {printf \"%.1f\", ($MAX - $MIN) / $AVG * 100}")
RATIO=$(awk "BEGIN {printf \"%.2f\", $MAX / $MIN}")

# Print sorted histogram-style
echo "Pod results (sorted by throughput):"
echo "$RESULTS" | tr ' ' '\n' | sort -n | awk '{printf "  %.2f\n", $1}'
echo ""

echo "=== Summary ==="
echo "  Pods:      $COUNT / $NUM_PODS"
echo "  Min:       $MIN GB/s"
echo "  Max:       $MAX GB/s"
echo "  Average:   $AVG GB/s"
echo "  Spread:    ${RATIO}x (min to max)"
echo "  Variance:  ${SPREAD}%"
echo "  Combined:  $TOTAL GB/s"
echo ""

# Write CSV for graphing
echo "pod,gbps" > "$OUTDIR/results.csv"
I=0
for GBPS in $RESULTS; do
    echo "$I,$GBPS" >> "$OUTDIR/results.csv"
    I=$((I + 1))
done
echo "  CSV written to $OUTDIR/results.csv"
