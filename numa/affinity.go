package numa

import (
	"fmt"
	"os"
	"runtime"
	"unsafe"

	"golang.org/x/sys/unix"
)

const (
	mpolBind = 2 // MPOL_BIND
)

// PinToCPU locks the current goroutine to its OS thread and sets
// CPU affinity to a single CPU.
func PinToCPU(cpu int) error {
	runtime.LockOSThread()
	var set unix.CPUSet
	set.Zero()
	set.Set(cpu)
	return unix.SchedSetaffinity(0, &set)
}

// PinToNode locks the current goroutine to its OS thread and sets
// CPU affinity to all CPUs on the given NUMA node.
func PinToNode(nodeID int, topo *Topology) error {
	runtime.LockOSThread()
	var set unix.CPUSet
	set.Zero()
	for _, n := range topo.Nodes {
		if n.ID == nodeID {
			for _, cpu := range n.CPUs {
				set.Set(cpu)
			}
			return unix.SchedSetaffinity(0, &set)
		}
	}
	return fmt.Errorf("node %d not found", nodeID)
}

// AllocOnNode allocates size bytes of memory bound to the specified NUMA node
// using mmap + mbind. Falls back to first-touch if mbind fails.
func AllocOnNode(size int, nodeID int) (buf []byte, usedMbind bool, err error) {
	buf, err = unix.Mmap(-1, 0, size,
		unix.PROT_READ|unix.PROT_WRITE,
		unix.MAP_PRIVATE|unix.MAP_ANONYMOUS)
	if err != nil {
		return nil, false, fmt.Errorf("mmap: %w", err)
	}

	// Try mbind to bind pages to the target NUMA node
	mbindErr := mbind(buf, nodeID)
	usedMbind = mbindErr == nil
	if mbindErr != nil {
		fmt.Fprintf(os.Stderr, "warning: mbind failed (%v), using first-touch fallback\n", mbindErr)
	}

	// Touch all pages to force physical allocation (first-touch policy
	// will place them on the current node if mbind failed)
	pageSize := os.Getpagesize()
	for i := 0; i < len(buf); i += pageSize {
		buf[i] = 0
	}

	return buf, usedMbind, nil
}

func mbind(buf []byte, nodeID int) error {
	// Build nodemask: a bitmask where bit nodeID is set
	// The kernel expects unsigned long array, so we use 8-byte (64-bit) chunks
	maskLen := (nodeID/64 + 1) * 8
	nodemask := make([]byte, maskLen)
	nodemask[nodeID/8] |= 1 << (uint(nodeID) % 8)

	_, _, errno := unix.Syscall6(
		unix.SYS_MBIND,
		uintptr(unsafe.Pointer(&buf[0])),
		uintptr(len(buf)),
		mpolBind,
		uintptr(unsafe.Pointer(&nodemask[0])),
		uintptr(nodeID+2), // maxnode is 1-indexed, plus 1 for safety
		0,                 // flags
	)
	if errno != 0 {
		return errno
	}
	return nil
}

// FreeNodeAlloc releases memory allocated by AllocOnNode.
func FreeNodeAlloc(buf []byte) error {
	return unix.Munmap(buf)
}
