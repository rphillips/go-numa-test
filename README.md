# NUMA Performance Analysis on AMD EPYC (Genoa)

## Reference: [golang/go#78044](https://github.com/golang/go/issues/78044)

## Test Environment

- **Instance**: AWS r7a.48xlarge (192 vCPUs, AMD EPYC Genoa)
- **NUMA Topology**: 2 nodes, 96 CPUs each (NPS2)
- **NUMA Distance**: 32 between nodes
- **GC**: Disabled (`debug.SetGCPercent(-1)`) to isolate NUMA effects

---

## Benchmark Results (GC Disabled)

| Test | Setup | Combined GB/s |
|------|-------|---------------|
| 1 | Single process, 192 CPUs | 78.43 |
| 2 | 2 pods, NUMA-pinned | 88.62 |
| 3 | 2 pods, unpinned | 98.61 |
| 4 | 4 pods, unpinned | 160.49 |

### Test 2: NUMA-Pinned (Ideal Scheduling)

Both processes received **symmetric, predictable performance**:

- Process A (NUMA node 0): 44.15 GB/s
- Process B (NUMA node 1): 44.47 GB/s

### Test 3: Unpinned (Real K8s Behavior)

Identical workloads received **uneven performance** — a 25% gap:

- Process A: 43.80 GB/s
- Process B: 54.81 GB/s

### Test 4: 4 Pods Unpinned (Higher Density)

Massive variance — a **1.9x difference** between identical pods:

- Process 0: 39.92 GB/s
- Process 1: 27.61 GB/s
- Process 2: 52.29 GB/s
- Process 3: 40.67 GB/s

Process 1 at 1 core started at 0.82 GB/s (vs the normal 4.2 GB/s), indicating it was stuck accessing remote NUMA memory.

---

## Key Findings

### GC Is Not the Main Problem

The scaling curves are almost identical with GC enabled and disabled. Throughput plateaus around 32 cores (~78 GB/s) and adding cores beyond that provides no benefit. The bottleneck is **memory bandwidth saturation** — each NUMA node's memory controllers can only push ~44-45 GB/s regardless of how many cores are requesting data.

### GOMAXPROCS Is Not a NUMA Fix

Setting GOMAXPROCS lower reduces the number of goroutines running simultaneously, which reduces concurrent memory requests hitting the memory controllers. This lowers bus saturation and improves per-core throughput — but it does **not** fix the NUMA problem. Memory is still allocated on random nodes, and goroutines still migrate across NUMA boundaries freely.

### The Real Problem: Go's NUMA-Unaware Runtime

Go's memory allocator places pages without regard to which NUMA node the goroutine is running on, and the scheduler freely migrates goroutines across NUMA boundaries. The result is identical pods getting wildly different performance depending on luck.

---

## Effects of Oversubscription

Running many pods on a single NUMA node (e.g., 200 pods on 96 CPUs) compounds the problem:

1. **CPU oversubscription** — Constant context switching flushes CPU caches (L1, L2, TLB). Every pod resumes with cold caches and must reload from DRAM.
2. **Go scheduler thrashing** — Each pod has its own Go runtime. Even GOMAXPROCS=2 per pod means 400 P's fighting for 96 CPUs.
3. **Memory pressure** — Pods can exhaust local NUMA memory, causing the kernel to silently allocate pages on the remote node — incurring cross-NUMA penalties even with pinning.
4. **Tail latency explosion** — "Unlucky" pods get hit by all three problems simultaneously, causing latency spikes orders of magnitude worse than "lucky" pods.

---

## Why AMD EPYC Is More Affected Than Intel

### AMD EPYC: Chiplet Architecture

- Multiple small dies (CCDs) connected by **Infinity Fabric**
- Each CCD has its own **32MB L3 cache** — not shared with other CCDs
- Memory controllers sit on a separate **I/O die (IOD)**, physically distant from some CCDs
- Even within a single socket, cross-CCD access traverses Infinity Fabric, adding latency
- BIOS NPS settings can expose 1, 2, or 4 NUMA nodes **per socket**
- Genoa has 12 CCDs per socket — even within one NUMA node, 6 CCDs have non-uniform latency

### Intel Xeon: Historically Monolithic

- All cores on a single die connected by a mesh interconnect
- **L3 cache shared** across all cores — roughly uniform access latency
- NUMA only appeared at the **socket boundary** (2-socket systems)
- Sub-NUMA Clustering (SNC) exists but is optional and off by default

### The Practical Difference

On Intel, NUMA penalties only occur when crossing between physical sockets — a clear, coarse boundary. On AMD, non-uniform latency exists at **multiple levels**:

| Access Pattern | Relative Latency |
|---------------|-----------------|
| Core to core within a CCD | Fast |
| CCD to CCD within a NUMA node | Slower (Infinity Fabric) |
| NUMA node to NUMA node | Slowest (longer Infinity Fabric path) |

Go's NUMA-unaware scheduler hurts more on AMD because there are **more opportunities for bad placement decisions**. On Intel, random scheduling within a single socket was mostly fine because everything was uniform. On AMD, "within a socket" is no longer uniform.

> **Note**: Intel is moving to chiplets too (Xeon 6 Granite Rapids), so this problem will become relevant for Intel as well.

---

## Possible Mitigations

Until Go's runtime is made NUMA-aware, the available workarounds are external:

- **`taskset`** — Pin a process to one NUMA node's CPUs
- **Multiple smaller processes** — Run one per NUMA node, each pinned
- **Kubernetes Topology Manager** — Enable CPU Manager with `static` policy and Topology Manager to assign pods to specific NUMA nodes

None of these are Go-level fixes — they are external workarounds.
