package numa

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type NUMANode struct {
	ID        int
	CPUs      []int
	Distances []int
}

type Topology struct {
	Nodes []NUMANode
}

func (t *Topology) CPUsPerNode() int {
	if len(t.Nodes) == 0 {
		return 0
	}
	return len(t.Nodes[0].CPUs)
}

func Discover() (*Topology, error) {
	matches, err := filepath.Glob("/sys/devices/system/node/node[0-9]*")
	if err != nil {
		return nil, fmt.Errorf("glob NUMA nodes: %w", err)
	}
	if len(matches) == 0 {
		return nil, fmt.Errorf("no NUMA nodes found in /sys/devices/system/node/")
	}

	var nodes []NUMANode
	for _, dir := range matches {
		base := filepath.Base(dir)
		idStr := strings.TrimPrefix(base, "node")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			continue
		}

		cpus, err := readCPUList(filepath.Join(dir, "cpulist"))
		if err != nil {
			return nil, fmt.Errorf("read cpulist for node %d: %w", id, err)
		}

		distances, err := readDistances(filepath.Join(dir, "distance"))
		if err != nil {
			return nil, fmt.Errorf("read distance for node %d: %w", id, err)
		}

		nodes = append(nodes, NUMANode{ID: id, CPUs: cpus, Distances: distances})
	}

	sort.Slice(nodes, func(i, j int) bool { return nodes[i].ID < nodes[j].ID })

	return &Topology{Nodes: nodes}, nil
}

func (t *Topology) Print() {
	fmt.Println("=== NUMA Topology ===")
	for _, n := range t.Nodes {
		fmt.Printf("Node %d: %d CPUs (%s)\n", n.ID, len(n.CPUs), formatCPUList(n.CPUs))
	}
	fmt.Println()
	fmt.Println("NUMA distances:")
	// Header
	fmt.Printf("%6s", "")
	for _, n := range t.Nodes {
		fmt.Printf("  node%d", n.ID)
	}
	fmt.Println()
	for _, n := range t.Nodes {
		fmt.Printf("node%d:", n.ID)
		for _, d := range n.Distances {
			fmt.Printf("  %5d", d)
		}
		fmt.Println()
	}
	fmt.Println()
}

func readCPUList(path string) ([]int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return parseCPUList(strings.TrimSpace(string(data)))
}

func parseCPUList(s string) ([]int, error) {
	if s == "" {
		return nil, nil
	}
	var cpus []int
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if strings.Contains(part, "-") {
			bounds := strings.SplitN(part, "-", 2)
			lo, err := strconv.Atoi(bounds[0])
			if err != nil {
				return nil, err
			}
			hi, err := strconv.Atoi(bounds[1])
			if err != nil {
				return nil, err
			}
			for i := lo; i <= hi; i++ {
				cpus = append(cpus, i)
			}
		} else {
			v, err := strconv.Atoi(part)
			if err != nil {
				return nil, err
			}
			cpus = append(cpus, v)
		}
	}
	return cpus, nil
}

func readDistances(path string) ([]int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	fields := strings.Fields(strings.TrimSpace(string(data)))
	var dists []int
	for _, f := range fields {
		v, err := strconv.Atoi(f)
		if err != nil {
			return nil, err
		}
		dists = append(dists, v)
	}
	return dists, nil
}

func formatCPUList(cpus []int) string {
	if len(cpus) == 0 {
		return ""
	}
	sorted := make([]int, len(cpus))
	copy(sorted, cpus)
	sort.Ints(sorted)

	var parts []string
	start := sorted[0]
	end := sorted[0]
	for i := 1; i < len(sorted); i++ {
		if sorted[i] == end+1 {
			end = sorted[i]
		} else {
			if start == end {
				parts = append(parts, strconv.Itoa(start))
			} else {
				parts = append(parts, fmt.Sprintf("%d-%d", start, end))
			}
			start = sorted[i]
			end = sorted[i]
		}
	}
	if start == end {
		parts = append(parts, strconv.Itoa(start))
	} else {
		parts = append(parts, fmt.Sprintf("%d-%d", start, end))
	}
	return strings.Join(parts, ",")
}
