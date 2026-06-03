#ifndef AGENT_H
#define AGENT_H

#include <stdint.h>
#include <stddef.h>
#include <time.h>

#define TARGET_IP "127.0.0.1"
#define TARGET_PORT 9999
#define INTERVAL_SEC 2
#define BUFFER_SIZE 8192
#define MAX_TRACKED_PROCESSES 256
#define TOP_PROCESS_LIMIT 8
#define DEFAULT_API_PORT 9876

typedef struct {
    uint64_t total_ram;
    uint64_t free_ram;
    double cpu_usage;
} sys_metrics_t;

typedef struct {
    int pid;
    char name[256];
    uint64_t resident_bytes;
    double cpu_percent;
    time_t started_at;
    uint64_t runtime_seconds;
} process_metrics_t;

typedef struct {
    process_metrics_t processes[MAX_TRACKED_PROCESSES];
    size_t count;
    time_t collected_at;
} process_snapshot_t;

typedef struct {
    sys_metrics_t system;
    process_snapshot_t processes;
    int health_score;
} agent_snapshot_t;

int init_socket(void);
void collect_metrics(sys_metrics_t *metrics);
int send_metrics(int sock_fd, const sys_metrics_t *metrics);
int collect_process_snapshot(process_snapshot_t *snapshot);
void sort_top_processes(process_snapshot_t *snapshot);
int calculate_system_health_score(const sys_metrics_t *metrics, const process_snapshot_t *snapshot);
int api_server_start(int port);
void api_server_stop(void);
void api_server_publish(const agent_snapshot_t *snapshot);
void show_health_hud(const agent_snapshot_t *snapshot);
void show_menubar_app(void);

#endif
