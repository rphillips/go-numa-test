#!/bin/bash
# Simulates multiple K8s Go workloads on a multi-NUMA node.
#
# Test 1: Single process, all CPUs (baseline)
# Test 2: 2 processes, each pinned to its own NUMA node (ideal NUMA-aware scheduling)
# Test 3: 2 processes, unpinned (real K8s behavior — no NUMA awareness)
# Test 4: 4 processes, unpinned (higher pod density)

BENCH=/tmp/numa-bench
ARGS="-size 256 -iters 5 -rand-accesses 1000000"
OUTDIR=/tmp/numa-sim-results
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

# Helper: add two floats without bc
add_floats() {
    awk "BEGIN {printf \"%.2f\", $1 + $2}"
}

add_floats4() {
    awk "BEGIN {printf \"%.2f\", $1 + $2 + $3 + $4}"
}

# Helper: extract the scaling sweep table from output
print_sweep() {
    local file="$1"
    local label="$2"
    echo "  $label:"
    # Print the sweep lines (they start with a number after the header)
    awk '/GOMAXPROCS Scaling/,/^$/' "$file" | grep -E '^[0-9]'  | while read line; do
        echo "    $line"
    done
}

# Helper: get aggregate GB/s for the highest GOMAXPROCS in the sweep
get_max_sweep_gbps() {
    local file="$1"
    awk '/GOMAXPROCS Scaling/,/^$/' "$file" | grep -E '^[0-9]' | tail -1 | awk '{print $2}'
}

echo "============================================================"
echo "  K8s NUMA Simulation on $(hostname)"
echo "============================================================"
echo ""

# --- Test 1: Single process, all CPUs ---
echo ">>> Test 1: Single process, GOMAXPROCS=192 (baseline)"
GOMAXPROCS=192 $BENCH $ARGS > "$OUTDIR/single.txt" 2>&1
print_sweep "$OUTDIR/single.txt" "Scaling sweep"
SINGLE_GBPS=$(get_max_sweep_gbps "$OUTDIR/single.txt")
echo "  Peak throughput (single process): ${SINGLE_GBPS:-N/A} GB/s"
echo ""

# --- Test 2: 2 processes pinned to separate NUMA nodes ---
echo ">>> Test 2: 2 processes, each pinned to its own NUMA node"
echo "    Process A: taskset -c 0-95 (NUMA node 0, GOMAXPROCS=96)"
echo "    Process B: taskset -c 96-191 (NUMA node 1, GOMAXPROCS=96)"
GOMAXPROCS=96 taskset -c 0-95 $BENCH $ARGS > "$OUTDIR/pinned-0.txt" 2>&1 &
PID_A=$!
GOMAXPROCS=96 taskset -c 96-191 $BENCH $ARGS > "$OUTDIR/pinned-1.txt" 2>&1 &
PID_B=$!
wait $PID_A $PID_B

print_sweep "$OUTDIR/pinned-0.txt" "Process A (NUMA node 0)"
print_sweep "$OUTDIR/pinned-1.txt" "Process B (NUMA node 1)"

A_GBPS=$(get_max_sweep_gbps "$OUTDIR/pinned-0.txt")
B_GBPS=$(get_max_sweep_gbps "$OUTDIR/pinned-1.txt")
COMBINED=$(add_floats "${A_GBPS:-0}" "${B_GBPS:-0}")
echo "  Process A: ${A_GBPS:-N/A} GB/s"
echo "  Process B: ${B_GBPS:-N/A} GB/s"
echo "  Combined throughput (NUMA-pinned): $COMBINED GB/s"
echo ""

# --- Test 3: 2 processes unpinned ---
echo ">>> Test 3: 2 processes, unpinned (simulating 2 K8s pods, no NUMA awareness)"
echo "    Both processes: GOMAXPROCS=96, no CPU pinning"
GOMAXPROCS=96 $BENCH $ARGS > "$OUTDIR/unpinned-0.txt" 2>&1 &
PID_A=$!
GOMAXPROCS=96 $BENCH $ARGS > "$OUTDIR/unpinned-1.txt" 2>&1 &
PID_B=$!
wait $PID_A $PID_B

print_sweep "$OUTDIR/unpinned-0.txt" "Process A"
print_sweep "$OUTDIR/unpinned-1.txt" "Process B"

A_GBPS=$(get_max_sweep_gbps "$OUTDIR/unpinned-0.txt")
B_GBPS=$(get_max_sweep_gbps "$OUTDIR/unpinned-1.txt")
COMBINED=$(add_floats "${A_GBPS:-0}" "${B_GBPS:-0}")
echo "  Process A: ${A_GBPS:-N/A} GB/s"
echo "  Process B: ${B_GBPS:-N/A} GB/s"
echo "  Combined throughput (unpinned): $COMBINED GB/s"
echo ""

# --- Test 4: 4 processes unpinned ---
echo ">>> Test 4: 4 processes, unpinned (simulating 4 K8s pods, no NUMA awareness)"
echo "    All processes: GOMAXPROCS=48, no CPU pinning"
GOMAXPROCS=48 $BENCH $ARGS > "$OUTDIR/dense-0.txt" 2>&1 &
PID_A=$!
GOMAXPROCS=48 $BENCH $ARGS > "$OUTDIR/dense-1.txt" 2>&1 &
PID_B=$!
GOMAXPROCS=48 $BENCH $ARGS > "$OUTDIR/dense-2.txt" 2>&1 &
PID_C=$!
GOMAXPROCS=48 $BENCH $ARGS > "$OUTDIR/dense-3.txt" 2>&1 &
PID_D=$!
wait $PID_A $PID_B $PID_C $PID_D

GBPS_ALL=""
for i in 0 1 2 3; do
    print_sweep "$OUTDIR/dense-$i.txt" "Process $i"
    GBPS=$(get_max_sweep_gbps "$OUTDIR/dense-$i.txt")
    echo "  Process $i peak: ${GBPS:-N/A} GB/s"
    if [ -z "$GBPS_ALL" ]; then
        GBPS_ALL="$GBPS"
    else
        GBPS_ALL="$GBPS_ALL $GBPS"
    fi
done

# Sum all 4
set -- $GBPS_ALL
COMBINED=$(add_floats4 "${1:-0}" "${2:-0}" "${3:-0}" "${4:-0}")
echo "  Combined throughput (4 pods unpinned): $COMBINED GB/s"
echo ""

echo "============================================================"
echo "  SUMMARY"
echo "============================================================"
echo ""
echo "Test 1 (single process, 192 CPUs):     ${SINGLE_GBPS:-N/A} GB/s"

A_P=$(get_max_sweep_gbps "$OUTDIR/pinned-0.txt")
B_P=$(get_max_sweep_gbps "$OUTDIR/pinned-1.txt")
PINNED_COMBINED=$(add_floats "${A_P:-0}" "${B_P:-0}")
echo "Test 2 (2 pods, NUMA-pinned):          $PINNED_COMBINED GB/s combined"

A_U=$(get_max_sweep_gbps "$OUTDIR/unpinned-0.txt")
B_U=$(get_max_sweep_gbps "$OUTDIR/unpinned-1.txt")
UNPINNED_COMBINED=$(add_floats "${A_U:-0}" "${B_U:-0}")
echo "Test 3 (2 pods, unpinned):             $UNPINNED_COMBINED GB/s combined"

echo "Test 4 (4 pods, unpinned):             $COMBINED GB/s combined"
echo ""
echo "NUMA-pinned pods should show higher combined throughput and"
echo "more consistent per-process performance than unpinned pods."
