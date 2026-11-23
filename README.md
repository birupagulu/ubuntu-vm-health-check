# Ubuntu VM Health Check

A Bash script that reports whether an Ubuntu virtual machine is healthy based on
CPU, memory, and root filesystem utilization.

The VM is **HEALTHY** only when all three metrics are below 60%. If any metric
is 60% or higher, the VM is **NOT HEALTHY**.

## Usage

```bash
./vm-health.sh
./vm-health.sh explain
```

The `explain` option prints the health status and each measured utilization
with its threshold result. CPU utilization is sampled over one second. Memory
utilization uses Linux's `MemAvailable` value, and disk utilization is for the
filesystem mounted at `/`.

The script uses standard Ubuntu utilities and kernel files: Bash, `awk`,
`df`, `sleep`, `/proc/stat`, and `/proc/meminfo`.
