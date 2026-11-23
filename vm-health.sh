#!/usr/bin/env bash
set -euo pipefail

threshold=60

usage() {
    printf 'Usage: %s [explain]\n' "$0" >&2
}

if [[ $# -gt 1 || ( $# -eq 1 && $1 != "explain" ) ]]; then
    usage
    exit 2
fi

cpu_snapshot() {
    awk '
        /^cpu / {
            total = 0
            for (i = 2; i <= 9 && i <= NF; i++) {
                total += $i
            }
            idle = $5
            if (NF >= 6) {
                idle += $6
            }
            printf "%.0f %.0f\n", total, idle
            found = 1
            exit
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' /proc/stat
}

cpu_before=$(cpu_snapshot) || {
    printf 'Error: could not read CPU counters from /proc/stat.\n' >&2
    exit 1
}
read -r total_before idle_before <<< "$cpu_before"
sleep 1
cpu_after=$(cpu_snapshot) || {
    printf 'Error: could not read CPU counters from /proc/stat.\n' >&2
    exit 1
}
read -r total_after idle_after <<< "$cpu_after"

cpu_usage=$(awk \
    -v total_before="$total_before" -v idle_before="$idle_before" \
    -v total_after="$total_after" -v idle_after="$idle_after" '
    BEGIN {
        total_delta = total_after - total_before
        idle_delta = idle_after - idle_before
        if (total_delta <= 0 || idle_delta < 0 || idle_delta > total_delta) {
            exit 1
        }
        usage = (total_delta - idle_delta) * 100 / total_delta
        if (usage < 0) usage = 0
        if (usage > 100) usage = 100
        printf "%.2f", usage
    }
') || {
    printf 'Error: could not calculate CPU utilization.\n' >&2
    exit 1
}

memory_usage=$(awk '
    /^MemTotal:/ { total = $2; found_total = 1 }
    /^MemAvailable:/ { available = $2; found_available = 1 }
    END {
        if (!found_total || !found_available || total <= 0 || available < 0 || available > total) {
            exit 1
        }
        printf "%.2f", (total - available) * 100 / total
    }
' /proc/meminfo) || {
    printf 'Error: could not calculate memory utilization from /proc/meminfo.\n' >&2
    exit 1
}

disk_usage=$(df -P / | awk '
    NR == 2 {
        usage = $5
        sub(/%$/, "", usage)
        if (usage !~ /^[0-9]+$/) {
            exit 1
        }
        print usage
        found = 1
        exit
    }
    END {
        if (!found) {
            exit 1
        }
    }
') || {
    printf 'Error: could not calculate disk utilization for the root filesystem.\n' >&2
    exit 1
}

is_at_or_above_threshold() {
    awk -v value="$1" -v threshold="$threshold" 'BEGIN { exit !(value >= threshold) }'
}

status="HEALTHY"
if is_at_or_above_threshold "$cpu_usage" \
    || is_at_or_above_threshold "$memory_usage" \
    || is_at_or_above_threshold "$disk_usage"; then
    status="NOT HEALTHY"
fi

printf 'VM health: %s\n' "$status"

if [[ ${1:-} == "explain" ]]; then
    explain_metric() {
        local name="$1"
        local value="$2"
        if is_at_or_above_threshold "$value"; then
            printf '%s: %s%% (not healthy: at or above the %s%% threshold)\n' \
                "$name" "$value" "$threshold"
        else
            printf '%s: %s%% (healthy: below the %s%% threshold)\n' \
                "$name" "$value" "$threshold"
        fi
    }

    explain_metric "CPU utilization (1-second sample)" "$cpu_usage"
    explain_metric "Memory utilization" "$memory_usage"
    explain_metric "Root filesystem utilization" "$disk_usage"
fi
