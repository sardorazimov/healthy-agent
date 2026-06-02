#include "agent.h"

#include <libproc.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc_info.h>
#include <time.h>
#include <unistd.h>

typedef struct {
    int pid;
    uint64_t cpu_time_ns;
    time_t seen_at;
} process_cpu_state_t;

static process_cpu_state_t previous[MAX_TRACKED_PROCESSES];
static size_t previous_count = 0;

static uint64_t process_cpu_time_ns(const struct rusage_info_v2 *usage) {
    return usage->ri_user_time + usage->ri_system_time;
}

static process_cpu_state_t *find_previous(int pid) {
    for (size_t i = 0; i < previous_count; i++) {
        if (previous[i].pid == pid) {
            return &previous[i];
        }
    }
    return NULL;
}

static void remember_cpu_state(int pid, uint64_t cpu_time_ns, time_t seen_at) {
    process_cpu_state_t *state = find_previous(pid);
    if (state) {
        state->cpu_time_ns = cpu_time_ns;
        state->seen_at = seen_at;
        return;
    }

    if (previous_count < MAX_TRACKED_PROCESSES) {
        previous[previous_count].pid = pid;
        previous[previous_count].cpu_time_ns = cpu_time_ns;
        previous[previous_count].seen_at = seen_at;
        previous_count++;
    }
}

static void collect_process(process_snapshot_t *snapshot, int pid, time_t now) {
    struct proc_bsdinfo bsd;
    struct rusage_info_v2 usage;
    process_metrics_t *metric;
    process_cpu_state_t *old_state;
    uint64_t cpu_time_ns;

    if (snapshot->count >= MAX_TRACKED_PROCESSES || pid <= 0) {
        return;
    }

    memset(&bsd, 0, sizeof(bsd));
    memset(&usage, 0, sizeof(usage));

    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) <= 0) {
        return;
    }

    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) {
        return;
    }

    metric = &snapshot->processes[snapshot->count];
    memset(metric, 0, sizeof(*metric));
    metric->pid = pid;
    if (proc_name(pid, metric->name, sizeof(metric->name)) <= 0) {
        snprintf(metric->name, sizeof(metric->name), "pid-%d", pid);
    }
    metric->resident_bytes = usage.ri_resident_size;
    metric->started_at = (time_t)bsd.pbi_start_tvsec;
    metric->runtime_seconds = metric->started_at > 0 && now > metric->started_at
        ? (uint64_t)(now - metric->started_at)
        : 0;

    cpu_time_ns = process_cpu_time_ns(&usage);
    old_state = find_previous(pid);
    if (old_state && now > old_state->seen_at && cpu_time_ns >= old_state->cpu_time_ns) {
        double elapsed = (double)(now - old_state->seen_at);
        double cpu_delta = (double)(cpu_time_ns - old_state->cpu_time_ns) / 1000000000.0;
        long cores = sysconf(_SC_NPROCESSORS_ONLN);
        if (cores < 1) {
            cores = 1;
        }
        metric->cpu_percent = (cpu_delta / elapsed) * 100.0 / (double)cores;
    }

    remember_cpu_state(pid, cpu_time_ns, now);
    snapshot->count++;
}

int collect_process_snapshot(process_snapshot_t *snapshot) {
    int pids[MAX_TRACKED_PROCESSES * 2];
    int bytes;
    int count;
    time_t now;

    if (!snapshot) {
        return -1;
    }

    memset(snapshot, 0, sizeof(*snapshot));
    now = time(NULL);
    snapshot->collected_at = now;

    bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (bytes <= 0) {
        return -1;
    }

    count = bytes / (int)sizeof(int);
    for (int i = 0; i < count; i++) {
        collect_process(snapshot, pids[i], now);
    }

    sort_top_processes(snapshot);
    return 0;
}

void sort_top_processes(process_snapshot_t *snapshot) {
    if (!snapshot) {
        return;
    }

    for (size_t i = 0; i < snapshot->count; i++) {
        for (size_t j = i + 1; j < snapshot->count; j++) {
            double left = snapshot->processes[i].cpu_percent;
            double right = snapshot->processes[j].cpu_percent;
            if (right > left ||
                (right == left && snapshot->processes[j].resident_bytes > snapshot->processes[i].resident_bytes)) {
                process_metrics_t tmp = snapshot->processes[i];
                snapshot->processes[i] = snapshot->processes[j];
                snapshot->processes[j] = tmp;
            }
        }
    }
}

int calculate_system_health_score(const sys_metrics_t *metrics, const process_snapshot_t *snapshot) {
    double used_ram_ratio;
    double pressure;
    int score = 100;

    if (!metrics || metrics->total_ram == 0) {
        return 0;
    }

    used_ram_ratio = 1.0 - ((double)metrics->free_ram / (double)metrics->total_ram);
    score -= (int)(metrics->cpu_usage * 0.35);
    score -= (int)(used_ram_ratio * 35.0);

    if (snapshot && snapshot->count > 0) {
        pressure = snapshot->processes[0].cpu_percent;
        if (pressure > 30.0) {
            score -= 10;
        }
        if (snapshot->processes[0].resident_bytes > (uint64_t)2 * 1024 * 1024 * 1024) {
            score -= 8;
        }
    }

    if (score < 0) {
        return 0;
    }
    if (score > 100) {
        return 100;
    }
    return score;
}
