#include "agent.h"

#include <arpa/inet.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static pthread_t api_thread;
static pthread_mutex_t snapshot_lock = PTHREAD_MUTEX_INITIALIZER;
static agent_snapshot_t latest_snapshot;
static int api_fd = -1;
static int api_running = 0;

static void snapshot_to_json(const agent_snapshot_t *snapshot, char *buffer, size_t size) {
    size_t used;
    size_t limit;

    used = (size_t)snprintf(buffer, size,
                            "{\"health_score\":%d,\"system\":{\"cpu\":%.2f,\"total_ram_mb\":%llu,"
                            "\"free_ram_mb\":%llu},\"top_processes\":[",
                            snapshot->health_score,
                            snapshot->system.cpu_usage,
                            (unsigned long long)snapshot->system.total_ram,
                            (unsigned long long)snapshot->system.free_ram);

    limit = snapshot->processes.count < TOP_PROCESS_LIMIT ? snapshot->processes.count : TOP_PROCESS_LIMIT;
    for (size_t i = 0; i < limit && used < size; i++) {
        const process_metrics_t *process = &snapshot->processes.processes[i];
        used += (size_t)snprintf(buffer + used, size - used,
                                 "%s{\"pid\":%d,\"name\":\"%s\",\"cpu\":%.2f,"
                                 "\"resident_bytes\":%llu,\"runtime_seconds\":%llu}",
                                 i == 0 ? "" : ",",
                                 process->pid,
                                 process->name,
                                 process->cpu_percent,
                                 (unsigned long long)process->resident_bytes,
                                 (unsigned long long)process->runtime_seconds);
    }

    if (used < size) {
        snprintf(buffer + used, size - used, "]}");
    }
}

static void send_response(int client, const char *status, const char *content_type, const char *body) {
    char header[512];
    size_t body_len = strlen(body);
    int header_len = snprintf(header, sizeof(header),
                              "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n"
                              "Connection: close\r\n\r\n",
                              status, content_type, body_len);
    send(client, header, (size_t)header_len, 0);
    send(client, body, body_len, 0);
}

static void *sse_loop(void *arg) {
    int client = (int)(intptr_t)arg;
    char body[BUFFER_SIZE];
    char frame[BUFFER_SIZE + 32];
    agent_snapshot_t snapshot;

    const char *headers =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/event-stream\r\n"
        "Cache-Control: no-cache\r\n"
        "Connection: keep-alive\r\n"
        "Access-Control-Allow-Origin: *\r\n\r\n";
    if (send(client, headers, strlen(headers), 0) < 0) {
        close(client);
        return NULL;
    }

    while (api_running) {
        pthread_mutex_lock(&snapshot_lock);
        snapshot = latest_snapshot;
        pthread_mutex_unlock(&snapshot_lock);
        snapshot_to_json(&snapshot, body, sizeof(body));

        int frame_len = snprintf(frame, sizeof(frame), "data: %s\r\n\r\n", body);
        if (frame_len <= 0) {
            break;
        }
        if (send(client, frame, (size_t)frame_len, 0) < 0) {
            break;
        }

        sleep(INTERVAL_SEC);
    }

    close(client);
    return NULL;
}

static void handle_client(int client) {
    char request[2048];
    char body[BUFFER_SIZE];
    ssize_t read_len;
    agent_snapshot_t snapshot;

    read_len = recv(client, request, sizeof(request) - 1, 0);
    if (read_len <= 0) {
        close(client);
        return;
    }
    request[read_len] = '\0';

    if (strncmp(request, "GET /stream", 11) == 0) {
        pthread_t stream_thread;
        if (pthread_create(&stream_thread, NULL, sse_loop, (void *)(intptr_t)client) != 0) {
            close(client);
            return;
        }
        pthread_detach(stream_thread);
        return;
    }

    pthread_mutex_lock(&snapshot_lock);
    snapshot = latest_snapshot;
    pthread_mutex_unlock(&snapshot_lock);
    snapshot_to_json(&snapshot, body, sizeof(body));

    if (strncmp(request, "GET /health", 11) == 0) {
        send_response(client, "200 OK", "application/json", body);
    } else if (strncmp(request, "GET /metrics", 12) == 0) {
        send_response(client, "200 OK", "application/json", body);
    } else {
        send_response(client, "404 Not Found", "application/json", "{\"error\":\"not found\"}");
    }

    close(client);
}

static void *api_loop(void *arg) {
    int port = *(int *)arg;
    struct sockaddr_in addr;
    int yes = 1;

    (void)arg;
    api_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (api_fd < 0) {
        return NULL;
    }

    setsockopt(api_fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)port);

    if (bind(api_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(api_fd, 8) < 0) {
        perror("[Miransas-API] listen failed");
        close(api_fd);
        api_fd = -1;
        return NULL;
    }

    api_running = 1;
    while (api_running) {
        int client = accept(api_fd, NULL, NULL);
        if (client >= 0) {
            int nosigpipe = 1;
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe));
            handle_client(client);
        } else if (errno != EINTR) {
            break;
        }
    }

    return NULL;
}

int api_server_start(int port) {
    static int api_port;
    api_port = port > 0 ? port : DEFAULT_API_PORT;
    if (pthread_create(&api_thread, NULL, api_loop, &api_port) != 0) {
        return -1;
    }
    return 0;
}

void api_server_stop(void) {
    api_running = 0;
    if (api_fd >= 0) {
        shutdown(api_fd, SHUT_RDWR);
        close(api_fd);
        api_fd = -1;
    }
    if (api_thread) {
        pthread_join(api_thread, NULL);
        api_thread = 0;
    }
}

void api_server_publish(const agent_snapshot_t *snapshot) {
    if (!snapshot) {
        return;
    }
    pthread_mutex_lock(&snapshot_lock);
    latest_snapshot = *snapshot;
    pthread_mutex_unlock(&snapshot_lock);
}
