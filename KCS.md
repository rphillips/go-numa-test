# Go applications exhibit unpredictable performance variance on multi-NUMA systems in OpenShift

## Issue

Go applications running as pods on OpenShift nodes with NUMA processors exhibit large, unpredictable performance variance between identical pods. Symptoms include:

- Identical pods on the same node show orders-of-magnitude differences in memory throughput.
- Memory-bandwidth-sensitive workloads plateau in aggregate throughput at 16-24 cores despite having 192 vCPUs available.
- Per-core efficiency drops.
- Increasing pod density causes "performance lottery" behavior where most pods get near-zero throughput while a few get near-full NUMA node bandwidth.
- Tail latency spikes appear for "unlucky" pods with no apparent cause.

## Environment

- Red Hat OpenShift Container Platform 4.x
- Master or Worker nodes using NUMA processors
- Go applications compiled with any Go version (the Go runtime is NUMA-unaware as of Go 1.25)

## Root Cause

Go's runtime is **NUMA-unaware**. Three runtime subsystems contribute to the problem:

1. **Memory allocator** — Go's allocator places pages without regard to which NUMA node the goroutine is running on. A memory span allocated by a goroutine on NUMA node 0 can later be handed to a goroutine on node 1, causing cross-NUMA memory accesses.

2. **Goroutine scheduler** — The scheduler freely migrates goroutines across NUMA boundaries. A goroutine whose heap resides on node 0 may be moved to node 1's CPUs, incurring remote memory access penalties on every heap read/write.

3. **Garbage collector** — GC workers scan the entire heap from any CPU. There is no partitioning to keep scan work local to each NUMA node.

This issue is tracked upstream at [golang/go#78044](https://github.com/golang/go/issues/78044).

## Diagnostic Steps

### Step 1: Verify NUMA topology on the node

Create a privileged debug pod on the affected worker node:

```bash
NODE="<worker-node-name>"

kubectl run numa-debug \
  --image=registry.access.redhat.com/ubi9/ubi:latest \
  --overrides='{
    "spec": {
      "nodeName": "'$NODE'",
      "tolerations": [{"operator": "Exists"}],
      "hostPID": true,
      "containers": [{
        "name": "numa-debug",
        "image": "registry.access.redhat.com/ubi9/ubi:latest",
        "command": ["sleep", "3600"],
        "securityContext": {"privileged": true},
        "volumeMounts": [{"name": "host", "mountPath": "/host"}]
      }],
      "volumes": [{"name": "host", "hostPath": {"path": "/tmp", "type": "Directory"}}]
    }
  }' \
  --restart=Never

kubectl wait --for=condition=Ready pod/numa-debug --timeout=120s
```

Check the NUMA topology:

```bash
kubectl exec numa-debug -- nsenter -t 1 -m -u -i -n -p -- numactl --hardware
```

On a 2-node NUMA system you might see output similar to:

```
available: 2 nodes (0-1)
node 0 cpus: 0-95
node 1 cpus: 96-191
node distances:
node   0   1
  0:  10  32
  1:  32  10
```

A NUMA distance of 32 between nodes confirms significant cross-node memory access penalties.

## Resolution

There is no fix available in the Go runtime at this time. The following workarounds mitigate the issue with decreasing complexity:

### Workaround 1: Enable Kubernetes Topology Manager (Recommended)

Configure the kubelet with CPU Manager `static` policy and Topology Manager to assign pods to specific NUMA nodes. This ensures pods' CPU and memory resources are aligned to the same NUMA node. See the Red Hat documentation for [CPU Manager and Topology Manager](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/scalability_and_performance/using-cpu-manager) and [Workload Partitioning](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/scalability_and_performance/enabling-workload-partitioning).

> **Note:** This workaround should be considered alongside Workaround 3 (CRI-O GOMAXPROCS injection) and Workaround 4 (setting GOMAXPROCS appropriately) for maximum effectiveness.

In OpenShift, apply a `PerformanceProfile` or configure the kubelet via `KubeletConfig`:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: numa-aware-config
spec:
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/worker: ""
  kubeletConfig:
    cpuManagerPolicy: "static"
    topologyManagerPolicy: "single-numa-node"
    reservedSystemCPUs: "0-3"
```

Pods must specify integer CPU requests and limits (Guaranteed QoS class) to be eligible for static CPU assignment:

```yaml
resources:
  requests:
    cpu: "4"
    memory: "8Gi"
  limits:
    cpu: "4"
    memory: "8Gi"
```

### Workaround 2: Use smaller instance types

Select instance types that fit within a single NUMA node to avoid the problem entirely. For example, use `r7a.24xlarge` (96 vCPUs, single NUMA node) instead of `r7a.48xlarge` (192 vCPUs, 2 NUMA nodes).

### Workaround 3: Enable CRI-O GOMAXPROCS injection

CRI-O can automatically inject a `GOMAXPROCS` environment variable into containers at creation time.

Enable it by deploying a CRI-O drop-in configuration file via a `MachineConfig`:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-crio-inject-gomaxprocs
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - path: /etc/crio/crio.conf.d/99-inject-gomaxprocs.conf
          mode: 0644
          overwrite: true
          contents:
            source: data:text/plain;charset=utf-8;base64,W2NyaW8ucnVudGltZV0KaW5qZWN0X2dvbWF4cHJvY3MgPSAxNgo=
```

The base64-encoded content decodes to the following CRI-O drop-in configuration:

```toml
[crio.runtime]
inject_gomaxprocs = 16
```

The `inject_gomaxprocs` value sets the minimum floor for `GOMAXPROCS`. Apply the `MachineConfig` to the cluster:

```bash
oc apply -f 99-crio-inject-gomaxprocs.yaml
```

The Machine Config Operator will roll out the change to all worker nodes, restarting CRI-O with the new configuration.

This applies to burstable and best-effort pods only — guaranteed QoS and workload-partitioned pods are skipped. The hook calculates `GOMAXPROCS` from the container's CPU shares and will not override an existing `GOMAXPROCS` environment variable. Individual pods can opt out with the `skip-gomaxprocs.crio.io` annotation.

### Workaround 4: Set GOMAXPROCS appropriately

Regardless of other mitigations, set GOMAXPROCS to a value appropriate for the workload. Memory bandwidth saturates at 16-24 cores. Setting GOMAXPROCS higher than this for bandwidth-bound workloads wastes CPU without improving throughput and increases cross-NUMA contention.

Go 1.25+ [automatically sets GOMAXPROCS](https://go.dev/blog/container-aware-gomaxprocs) to match the container's CPU limit when one is configured. However, this only helps pods with explicit CPU limits (Guaranteed QoS). For burstable and best-effort pods without CPU limits, GOMAXPROCS still defaults to the full host core count (e.g., 192 on an r7a.48xlarge), which is why Workaround 3 (CRI-O injection) or manually setting GOMAXPROCS remains necessary.

`GOMAXPROCS` can be set directly in the pod spec as an environment variable:

```yaml
env:
  - name: GOMAXPROCS
    value: "16"
```

## Additional Information

- **The problem worsens with sustained load.** Short-burst workloads may not see the full impact because some pods finish before the scheduler migrates goroutines across NUMA boundaries. Under sustained load, every pod eventually gets churned across nodes, caches are perpetually cold, and the memory bus is fully saturated by cross-NUMA traffic.

- **Node saturation point.** On a 192 vCPU AMD EPYC Genoa system, performance collapse begins at approximately 16 pods (GOMAXPROCS=4 each, 64 active P's total). Beyond this point, per-pod throughput drops sharply, combined throughput decreases due to contention overhead, and fairness spread increases exponentially.

- **This is not specific to OpenShift.** Any Go application on multi-NUMA hardware exhibits this behavior. 

- **Other languages handle NUMA natively.** Languages like Java (via ZGC and G1 NUMA-aware modes), C/C++ (via `libnuma` and `numa_alloc_onnode`), and Rust (via `libnuma` bindings) have NUMA-aware memory allocators built in or available as libraries. Go is an outlier in lacking this support.

- **Upstream tracking:** [golang/go#78044](https://github.com/golang/go/issues/78044)

## Future Plans

- **NUMA-aware Go runtime.** The long-term goal is to work with the Go upstream community to add NUMA-aware memory allocation to the Go runtime. This would allow the Go allocator to place memory pages on the same NUMA node where the goroutine is executing, eliminating cross-NUMA memory access penalties at the source. Progress on this effort is tracked at [golang/go#78044](https://github.com/golang/go/issues/78044).

- **HyperShift NUMA tuning.** Work with the HyperShift team to ensure hosted control plane components are correctly tuned for NUMA-aware scheduling and resource allocation on multi-NUMA worker nodes.
