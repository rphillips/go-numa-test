# NUMA Benchmark Runbook

## Prerequisites

- `kubectl` configured with access to the cluster
- KUBECONFIG set: `export KUBECONFIG=~/Downloads/kubeconfig`
- Target nodes: r7a.48xlarge workers (192 vCPU, AMD EPYC Genoa, 2 NUMA nodes)

## Step 1: Build the binary

```bash
cd ~/Downloads/numa-bench
go mod tidy
go build -o numa-bench .
```

## Step 2: Create a privileged pod on the target node

The pod needs:
- Privileged security context (for mbind syscall and host access)
- Host /tmp mounted for file transfer
- hostPID for nsenter
- 1 hour sleep to keep it alive during the full test run

```bash
export KUBECONFIG=~/Downloads/kubeconfig
NODE="<worker-node-name>"  # e.g., kubectl get nodes -l node-role.kubernetes.io/worker=

kubectl run numa-copy-1 \
  --image=registry.access.redhat.com/ubi9/ubi:latest \
  --overrides='{
    "spec": {
      "nodeName": "'$NODE'",
      "tolerations": [{"operator": "Exists"}],
      "hostPID": true,
      "containers": [{
        "name": "numa-copy-1",
        "image": "registry.access.redhat.com/ubi9/ubi:latest",
        "command": ["sleep", "3600"],
        "securityContext": {"privileged": true},
        "volumeMounts": [{"name": "host", "mountPath": "/host"}]
      }],
      "volumes": [{"name": "host", "hostPath": {"path": "/tmp", "type": "Directory"}}]
    }
  }' \
  --restart=Never

kubectl wait --for=condition=Ready pod/numa-copy-1 --timeout=120s
```

## Step 3: Copy the binary and simulation script to the node

`kubectl cp` writes to the container filesystem. Then `cp` moves it to
the host-mounted `/host` (which is `/tmp` on the node).

```bash
export KUBECONFIG=~/Downloads/kubeconfig

kubectl cp ~/Downloads/numa-bench/numa-bench default/numa-copy-1:/tmp/numa-bench
kubectl exec numa-copy-1 -- cp /tmp/numa-bench /host/numa-bench
kubectl exec numa-copy-1 -- chmod +x /host/numa-bench

kubectl cp ~/Downloads/numa-bench/k8s-sim.sh default/numa-copy-1:/tmp/k8s-sim.sh
kubectl exec numa-copy-1 -- cp /tmp/k8s-sim.sh /host/k8s-sim.sh
kubectl exec numa-copy-1 -- chmod +x /host/k8s-sim.sh
```

## Step 4: Run the standalone benchmark

This runs all 3 test runs (GOMAXPROCS=all, GOMAXPROCS=1 NUMA node, scaling sweep).
Uses `nsenter` to break out of the container into the host namespace so the
benchmark sees the full CPU/NUMA topology.

```bash
export KUBECONFIG=~/Downloads/kubeconfig

kubectl exec numa-copy-1 -- \
  nsenter -t 1 -m -u -i -n -p -- \
  /tmp/numa-bench -size 256 -iters 10 -rand-accesses 2000000
```

Expected runtime: ~5-10 minutes.

## Step 5: Run the K8s multi-pod simulation

This runs 4 tests simulating K8s pod workloads:
- Test 1: Single process, all CPUs (baseline)
- Test 2: 2 processes, each pinned to its own NUMA node (ideal)
- Test 3: 2 processes, unpinned (real K8s behavior)
- Test 4: 4 processes, unpinned (higher pod density)

```bash
export KUBECONFIG=~/Downloads/kubeconfig

kubectl exec numa-copy-1 -- \
  nsenter -t 1 -m -u -i -n -p -- \
  /bin/bash /tmp/k8s-sim.sh
```

Expected runtime: ~20-30 minutes.

## Step 6: Cleanup

```bash
export KUBECONFIG=~/Downloads/kubeconfig
kubectl delete pod numa-copy-1 --force
```

## Troubleshooting

### Pod shows "Completed" before you finish

The sleep timer expired. Recreate the pod (Step 2). The binary and script
may still be on the node at `/tmp/numa-bench` and `/tmp/k8s-sim.sh` — verify
with `kubectl exec` after recreating.

### `kubectl cp` fails with "tar not found"

Use `registry.access.redhat.com/ubi9/ubi:latest` (full image), not
`ubi9/ubi-minimal` which lacks tar.

### `kubectl cp` fails with "Permission denied"

The pod needs `"securityContext": {"privileged": true}` to write to the
host-mounted volume.

### mbind warning in benchmark output

The benchmark falls back to first-touch memory placement if mbind fails.
Results are still valid but memory placement is less deterministic. Running
with `sudo` (or as root via nsenter as above) should resolve this.

### Benchmark shows only 1 NUMA node

You're running inside the container's cgroup, not the host namespace.
Make sure you're using `nsenter -t 1 -m -u -i -n -p --` before the command.
