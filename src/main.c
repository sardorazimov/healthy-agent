#include "agent.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <signal.h>

#define MENUBAR_LOCK_PATH "/tmp/miransas-pulse.lock"

static volatile sig_atomic_t keep_running = 1;

static void handle_shutdown(int signal_number) {
    (void)signal_number;
    keep_running = 0;
}

static void print_usage(const char *program_name) {
    printf("Usage: %s [--foreground] [--once] [--hud] [--menubar] [--api-port PORT] [--help]\n", program_name);
    printf("  --foreground  Terminalde calisir, loglari stdout/stderr'e yazar.\n");
    printf("  --once        Bir metrik paketi gonderip cikar.\n");
    printf("  --hud         Kucuk transparan health panelini gosterir.\n");
    printf("  --menubar     macOS menubar uygulamasini baslatir (canli health score).\n");
    printf("  --api-port    Local REST/SSE API portu. Varsayilan: %d.\n", DEFAULT_API_PORT);
    printf("  --help        Bu yardimi gosterir.\n");
}

static int install_signal_handlers(void) {
    struct sigaction action;

    memset(&action, 0, sizeof(action));
    action.sa_handler = handle_shutdown;

    if (sigaction(SIGTERM, &action, NULL) < 0) {
        return -1;
    }

    if (sigaction(SIGINT, &action, NULL) < 0) {
        return -1;
    }

    return 0;
}

static int daemonize(void) {
    pid_t pid;
    int fd;

    pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    if (setsid() < 0) {
        return -1;
    }

    signal(SIGCHLD, SIG_IGN);
    signal(SIGHUP, SIG_IGN);

    pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    umask(0);

    if (chdir("/") < 0) {
        return -1;
    }

    fd = open("/dev/null", O_RDWR);
    if (fd < 0) {
        return -1;
    }

    if (dup2(fd, STDIN_FILENO) < 0 ||
        dup2(fd, STDOUT_FILENO) < 0 ||
        dup2(fd, STDERR_FILENO) < 0) {
        close(fd);
        return -1;
    }

    close(fd);
    return 0;
}

int main(int argc, char *argv[]) {
    int sock_fd;
    agent_snapshot_t snapshot;
    int foreground = 0;
    int once = 0;
    int hud = 0;
    int menubar = 0;
    int api_port = DEFAULT_API_PORT;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--foreground") == 0) {
            foreground = 1;
        } else if (strcmp(argv[i], "--once") == 0) {
            once = 1;
            foreground = 1;
        } else if (strcmp(argv[i], "--hud") == 0) {
            hud = 1;
            foreground = 1;
            once = 1;
        } else if (strcmp(argv[i], "--menubar") == 0) {
            menubar = 1;
            foreground = 1;
        } else if (strcmp(argv[i], "--api-port") == 0 && i + 1 < argc) {
            api_port = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Bilinmeyen arguman: %s\n", argv[i]);
            print_usage(argv[0]);
            return 2;
        }
    }

    if (!foreground && daemonize() < 0) {
        perror("[Miransas-Agent] Daemon baslatilamadi");
        return 1;
    }

    if (install_signal_handlers() < 0) {
        perror("[Miransas-Agent] Sinyal handler kurulumu basarisiz");
        return 1;
    }

    if (menubar) {
        int lock_fd = open(MENUBAR_LOCK_PATH, O_RDWR | O_CREAT, 0644);
        if (lock_fd < 0) {
            fprintf(stderr, "[Miransas-Pulse] Kilit dosyasi acilamadi (%s): %s\n",
                    MENUBAR_LOCK_PATH, strerror(errno));
            return 1;
        }
        if (flock(lock_fd, LOCK_EX | LOCK_NB) < 0) {
            fprintf(stderr, "[Miransas-Pulse] Miransas Pulse zaten calisiyor.\n");
            close(lock_fd);
            return 0;
        }

        if (api_server_start(api_port) < 0) {
            fprintf(stderr, "[Miransas-Pulse] API server baslamadi (port %d kullanimda olabilir). "
                            "Menubar API'sez devam ediyor.\n",
                    api_port);
        }

        show_menubar_app();

        api_server_stop();
        flock(lock_fd, LOCK_UN);
        close(lock_fd);
        return 0;
    }

    if (hud) {
        memset(&snapshot, 0, sizeof(snapshot));
        collect_metrics(&snapshot.system);
        collect_process_snapshot(&snapshot.processes);
        snapshot.health_score = calculate_system_health_score(&snapshot.system, &snapshot.processes);
        show_health_hud(&snapshot);
        return 0;
    }

    if (api_server_start(api_port) < 0) {
        return 1;
    }

    sock_fd = init_socket();
    if (sock_fd < 0) {
        api_server_stop();
        return 1;
    }

    do {
        memset(&snapshot, 0, sizeof(snapshot));
        collect_metrics(&snapshot.system);
        collect_process_snapshot(&snapshot.processes);
        snapshot.health_score = calculate_system_health_score(&snapshot.system, &snapshot.processes);
        api_server_publish(&snapshot);

        if (send_metrics(sock_fd, &snapshot.system) < 0 && once) {
            close(sock_fd);
            api_server_stop();
            return 1;
        }

        if (!once) {
            sleep(INTERVAL_SEC);
        }
    } while (keep_running && !once);

    close(sock_fd);
    api_server_stop();
    return 0;
}
