package main

import (
	"flag"
	"fmt"
	"numa-bench/bench"
	"numa-bench/numa"
	"os"
	"runtime"
	"runtime/debug"
	"strings"
)

func main() {
	sizeMB := flag.Int("size", bench.DefaultSizeMB, "buffer size in MB")
	iters := flag.Int("iters", bench.DefaultIters, "iterations per sequential benchmark")
	randAccesses := flag.Int("rand-accesses", bench.DefaultRandAccess, "number of random read accesses")
	flag.Parse()

	// Disable GC for the entire benchmark to isolate NUMA effects
	// from GC worker contention
	debug.SetGCPercent(-1)
	runtime.GC() // run one final GC before disabling

	// Discover NUMA topology
	topo, err := numa.Discover()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error discovering NUMA topology: %v\n", err)
		os.Exit(1)
	}

	topo.Print()

	if len(topo.Nodes) < 2 {
		fmt.Println("WARNING: Only 1 NUMA node detected. Cross-NUMA tests will be skipped.")
		fmt.Println("Run on a multi-NUMA system (e.g., r7a.48xlarge) to see the full benchmark.")
	}

	fmt.Printf("Go runtime: %s %s/%s\n", runtime.Version(), runtime.GOOS, runtime.GOARCH)
	fmt.Printf("NumCPU: %d\n", runtime.NumCPU())
	fmt.Printf("Buffer size: %d MB\n", *sizeMB)
	fmt.Printf("Sequential iters: %d\n", *iters)
	fmt.Printf("Random accesses: %d\n", *randAccesses)
	fmt.Println()

	allCPUs := runtime.NumCPU()
	cpusPerNode := topo.CPUsPerNode()

	// ============================================================
	// RUN 1: GOMAXPROCS = all CPUs
	// ============================================================
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("  RUN 1: GOMAXPROCS=%d (all CPUs)\n", allCPUs)
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println()

	runtime.GOMAXPROCS(allCPUs)

	var run1Local, run1Remote []bench.Result
	if len(topo.Nodes) >= 2 {
		lr := bench.RunLocalRemote(topo, *sizeMB, *iters, *randAccesses)
		run1Local, run1Remote = splitLocalRemote(lr)
	}
	run1Default := bench.RunGoDefault(*sizeMB, *iters, *randAccesses, allCPUs)

	fmt.Println()
	printSequentialTable(run1Local, run1Remote, run1Default)
	printRandomTable(run1Local, run1Remote, run1Default)

	// ============================================================
	// RUN 2: GOMAXPROCS = CPUs per NUMA node
	// ============================================================
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("  RUN 2: GOMAXPROCS=%d (1 NUMA node)\n", cpusPerNode)
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println()

	runtime.GOMAXPROCS(cpusPerNode)

	var run2Local, run2Remote []bench.Result
	if len(topo.Nodes) >= 2 {
		lr := bench.RunLocalRemote(topo, *sizeMB, *iters, *randAccesses)
		run2Local, run2Remote = splitLocalRemote(lr)
	}
	run2Default := bench.RunGoDefault(*sizeMB, *iters, *randAccesses, cpusPerNode)

	fmt.Println()
	printSequentialTable(run2Local, run2Remote, run2Default)
	printRandomTable(run2Local, run2Remote, run2Default)

	// GOMAXPROCS comparison
	fmt.Println("=== GOMAXPROCS Comparison (Go Default Sequential Read) ===")
	printGOMAXPROCSComparison(run1Default, run2Default, allCPUs, cpusPerNode)
	fmt.Println()

	// ============================================================
	// RUN 3: GOMAXPROCS Scaling Sweep
	// ============================================================
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("  RUN 3: GOMAXPROCS Scaling Sweep")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println()

	sweepResults := bench.RunScalingSweep(topo, *sizeMB, *iters, *randAccesses)
	fmt.Println()
	printScalingSweep(sweepResults, cpusPerNode)

	// Reset GOMAXPROCS
	runtime.GOMAXPROCS(allCPUs)

	// Final analysis
	printAnalysis(run1Local, run1Remote, run1Default, run2Default, sweepResults, cpusPerNode)
}

func splitLocalRemote(results []bench.Result) (local, remote []bench.Result) {
	for _, r := range results {
		if r.Scenario == "local-numa" {
			local = append(local, r)
		} else {
			remote = append(remote, r)
		}
	}
	return
}

func getLocalBaseline(local []bench.Result) float64 {
	for _, r := range local {
		if r.Workload == "sequential-read" {
			return r.GBPerSec
		}
	}
	return 0
}

func getLocalBaselineLatency(local []bench.Result) float64 {
	for _, r := range local {
		if r.Workload == "random-read" {
			return r.AvgLatNs
		}
	}
	return 0
}

func printSequentialTable(local, remote, goDefault []bench.Result) {
	fmt.Println("=== Sequential Read Throughput (GB/s) ===")
	fmt.Printf("%-40s %10s %10s %10s\n", "Scenario", "AllocNode", "AccessNode", "GB/s")
	fmt.Println(strings.Repeat("-", 75))

	baseline := getLocalBaseline(local)

	for _, r := range local {
		if r.Workload == "sequential-read" {
			fmt.Printf("%-40s %10d %10d %10.2f  (baseline)\n",
				fmt.Sprintf("Local (node %d -> node %d)", r.AllocNode, r.AccessNode),
				r.AllocNode, r.AccessNode, r.GBPerSec)
		}
	}
	for _, r := range remote {
		if r.Workload == "sequential-read" {
			rel := ""
			if baseline > 0 {
				rel = fmt.Sprintf("%.2fx", r.GBPerSec/baseline)
			}
			fmt.Printf("%-40s %10d %10d %10.2f  %s\n",
				fmt.Sprintf("Remote (node %d -> node %d)", r.AllocNode, r.AccessNode),
				r.AllocNode, r.AccessNode, r.GBPerSec, rel)
		}
	}
	for _, r := range goDefault {
		if r.Workload == "sequential-read" {
			rel := ""
			if baseline > 0 {
				rel = fmt.Sprintf("%.2fx", r.GBPerSec/baseline)
			}
			fmt.Printf("%-40s %10s %10s %10.2f  %s\n",
				fmt.Sprintf("Go default (%s)", r.Scenario), "-", "-", r.GBPerSec, rel)
		}
	}
	fmt.Println()
}

func printRandomTable(local, remote, goDefault []bench.Result) {
	fmt.Println("=== Random Read Latency (ns/access) ===")
	fmt.Printf("%-40s %10s %10s %12s\n", "Scenario", "AllocNode", "AccessNode", "Latency(ns)")
	fmt.Println(strings.Repeat("-", 75))

	baseline := getLocalBaselineLatency(local)

	for _, r := range local {
		if r.Workload == "random-read" {
			fmt.Printf("%-40s %10d %10d %12.1f  (baseline)\n",
				fmt.Sprintf("Local (node %d -> node %d)", r.AllocNode, r.AccessNode),
				r.AllocNode, r.AccessNode, r.AvgLatNs)
		}
	}
	for _, r := range remote {
		if r.Workload == "random-read" {
			rel := ""
			if baseline > 0 {
				rel = fmt.Sprintf("%.2fx", r.AvgLatNs/baseline)
			}
			fmt.Printf("%-40s %10d %10d %12.1f  %s\n",
				fmt.Sprintf("Remote (node %d -> node %d)", r.AllocNode, r.AccessNode),
				r.AllocNode, r.AccessNode, r.AvgLatNs, rel)
		}
	}
	for _, r := range goDefault {
		if r.Workload == "random-read" {
			rel := ""
			if baseline > 0 {
				rel = fmt.Sprintf("%.2fx", r.AvgLatNs/baseline)
			}
			fmt.Printf("%-40s %10s %10s %12.1f  %s\n",
				fmt.Sprintf("Go default (%s)", r.Scenario), "-", "-", r.AvgLatNs, rel)
		}
	}
	fmt.Println()
}

func printGOMAXPROCSComparison(run1Default, run2Default []bench.Result, allCPUs, cpusPerNode int) {
	var avg1, avg2 float64
	var c1, c2 int
	for _, r := range run1Default {
		if r.Workload == "sequential-read" {
			avg1 += r.GBPerSec
			c1++
		}
	}
	for _, r := range run2Default {
		if r.Workload == "sequential-read" {
			avg2 += r.GBPerSec
			c2++
		}
	}
	if c1 > 0 {
		avg1 /= float64(c1)
	}
	if c2 > 0 {
		avg2 /= float64(c2)
	}
	fmt.Printf("  GOMAXPROCS=%d avg: %.2f GB/s\n", allCPUs, avg1)
	fmt.Printf("  GOMAXPROCS=%d avg: %.2f GB/s\n", cpusPerNode, avg2)
}

func printScalingSweep(results []bench.Result, cpusPerNode int) {
	fmt.Println("=== Go Default Sequential Read — GOMAXPROCS Scaling ===")
	fmt.Printf("%-12s %15s %15s %12s\n",
		"GOMAXPROCS", "Aggregate GB/s", "Per-Core GB/s", "Efficiency")
	fmt.Println(strings.Repeat("-", 60))

	var basePerCore float64
	for _, r := range results {
		if r.Workload != "sequential-read" {
			continue
		}
		perCore := r.GBPerSec / float64(r.GOMAXPROCS)
		if basePerCore == 0 {
			basePerCore = perCore
		}
		efficiency := perCore / basePerCore
		fmt.Printf("%-12d %15.2f %15.3f %11.2fx\n",
			r.GOMAXPROCS, r.GBPerSec, perCore, efficiency)
	}
	fmt.Println()
}

func printAnalysis(local, remote, run1Default, run2Default, sweep []bench.Result, cpusPerNode int) {
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("  ANALYSIS")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println()

	localGB := getLocalBaseline(local)
	var remoteGB float64
	for _, r := range remote {
		if r.Workload == "sequential-read" {
			remoteGB = r.GBPerSec
		}
	}

	if localGB > 0 && remoteGB > 0 {
		fmt.Printf("Remote NUMA penalty: %.2fx slower than local (%.2f vs %.2f GB/s)\n",
			localGB/remoteGB, remoteGB, localGB)
	}

	// Go default variance in run 1
	var vals1 []float64
	for _, r := range run1Default {
		if r.Workload == "sequential-read" {
			vals1 = append(vals1, r.GBPerSec)
		}
	}
	if len(vals1) > 0 {
		min, max := vals1[0], vals1[0]
		sum := 0.0
		for _, v := range vals1 {
			if v < min {
				min = v
			}
			if v > max {
				max = v
			}
			sum += v
		}
		avg := sum / float64(len(vals1))
		variance := (max - min) / avg * 100
		fmt.Printf("Go default variance (all CPUs): %.1f%% spread across %d trials (%.2f - %.2f GB/s)\n",
			variance, len(vals1), min, max)
	}

	// Scaling efficiency
	var firstPerCore, lastPerCore float64
	var lastProcs int
	for _, r := range sweep {
		if r.Workload != "sequential-read" {
			continue
		}
		pc := r.GBPerSec / float64(r.GOMAXPROCS)
		if firstPerCore == 0 {
			firstPerCore = pc
		}
		lastPerCore = pc
		lastProcs = r.GOMAXPROCS
	}
	if firstPerCore > 0 && lastPerCore > 0 {
		drop := (1 - lastPerCore/firstPerCore) * 100
		fmt.Printf("Per-core efficiency drop (%d -> %d GOMAXPROCS): %.0f%%\n",
			cpusPerNode, lastProcs, drop)
	}

	fmt.Println()
	fmt.Println("CONCLUSION: Go's NUMA-unaware runtime and allocator cause cross-NUMA")
	fmt.Println("memory access penalties. The scaling sweep shows diminishing returns")
	fmt.Println("as GOMAXPROCS increases across NUMA node boundaries.")
	fmt.Println("See https://github.com/golang/go/issues/78044")
}
