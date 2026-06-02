#include "agent.h"

#include <assert.h>
#include <string.h>

static void test_health_score_bounds(void) {
    sys_metrics_t metrics = {0};
    process_snapshot_t snapshot = {0};

    metrics.total_ram = 1000;
    metrics.free_ram = 500;
    metrics.cpu_usage = 20.0;
    snapshot.count = 1;
    snapshot.processes[0].cpu_percent = 10.0;

    int score = calculate_system_health_score(&metrics, &snapshot);
    assert(score > 0);
    assert(score <= 100);

    metrics.cpu_usage = 250.0;
    metrics.free_ram = 0;
    snapshot.processes[0].cpu_percent = 99.0;
    assert(calculate_system_health_score(&metrics, &snapshot) == 0);
}

static void test_top_process_sort(void) {
    process_snapshot_t snapshot = {0};

    snapshot.count = 3;
    strcpy(snapshot.processes[0].name, "low");
    snapshot.processes[0].cpu_percent = 1.0;
    snapshot.processes[0].resident_bytes = 100;

    strcpy(snapshot.processes[1].name, "high");
    snapshot.processes[1].cpu_percent = 40.0;
    snapshot.processes[1].resident_bytes = 100;

    strcpy(snapshot.processes[2].name, "memory");
    snapshot.processes[2].cpu_percent = 40.0;
    snapshot.processes[2].resident_bytes = 200;

    sort_top_processes(&snapshot);
    assert(strcmp(snapshot.processes[0].name, "memory") == 0);
    assert(strcmp(snapshot.processes[1].name, "high") == 0);
    assert(strcmp(snapshot.processes[2].name, "low") == 0);
}

int main(void) {
    test_health_score_bounds();
    test_top_process_sort();
    return 0;
}
