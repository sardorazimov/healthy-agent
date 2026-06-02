#include "agent.h"

#include <sqlite3.h>
#include <stdio.h>
#include <string.h>

static sqlite3 *database = NULL;

static int exec_sql(const char *sql) {
    char *error = NULL;
    int rc = sqlite3_exec(database, sql, NULL, NULL, &error);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "[Miransas-Storage] SQL error: %s\n", error ? error : "unknown");
        sqlite3_free(error);
        return -1;
    }
    return 0;
}

int storage_open(const char *path) {
    const char *db_path = path && path[0] ? path : DEFAULT_DB_PATH;
    if (sqlite3_open(db_path, &database) != SQLITE_OK) {
        fprintf(stderr, "[Miransas-Storage] Cannot open database: %s\n", sqlite3_errmsg(database));
        return -1;
    }

    sqlite3_busy_timeout(database, 250);
    return storage_init();
}

void storage_close(void) {
    if (database) {
        sqlite3_close(database);
        database = NULL;
    }
}

int storage_init(void) {
    static const char *schema =
        "PRAGMA journal_mode=WAL;"
        "CREATE TABLE IF NOT EXISTS system_metrics ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "collected_at INTEGER NOT NULL,"
        "cpu_percent REAL NOT NULL,"
        "total_ram_mb INTEGER NOT NULL,"
        "free_ram_mb INTEGER NOT NULL,"
        "health_score INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_system_metrics_time ON system_metrics(collected_at DESC);"
        "CREATE TABLE IF NOT EXISTS process_metrics ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "collected_at INTEGER NOT NULL,"
        "pid INTEGER NOT NULL,"
        "name TEXT NOT NULL,"
        "cpu_percent REAL NOT NULL,"
        "resident_bytes INTEGER NOT NULL,"
        "started_at INTEGER NOT NULL,"
        "runtime_seconds INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_process_metrics_time ON process_metrics(collected_at DESC);"
        "CREATE INDEX IF NOT EXISTS idx_process_metrics_name ON process_metrics(name, collected_at DESC);";

    if (!database) {
        return -1;
    }
    return exec_sql(schema);
}

int storage_save_snapshot(const agent_snapshot_t *snapshot) {
    sqlite3_stmt *stmt = NULL;
    int rc;
    size_t limit;

    if (!database || !snapshot) {
        return -1;
    }

    if (exec_sql("BEGIN IMMEDIATE TRANSACTION;") < 0) {
        return -1;
    }

    rc = sqlite3_prepare_v2(database,
                            "INSERT INTO system_metrics "
                            "(collected_at, cpu_percent, total_ram_mb, free_ram_mb, health_score) "
                            "VALUES (?, ?, ?, ?, ?);",
                            -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        exec_sql("ROLLBACK;");
        return -1;
    }

    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)snapshot->processes.collected_at);
    sqlite3_bind_double(stmt, 2, snapshot->system.cpu_usage);
    sqlite3_bind_int64(stmt, 3, (sqlite3_int64)snapshot->system.total_ram);
    sqlite3_bind_int64(stmt, 4, (sqlite3_int64)snapshot->system.free_ram);
    sqlite3_bind_int(stmt, 5, snapshot->health_score);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        sqlite3_finalize(stmt);
        exec_sql("ROLLBACK;");
        return -1;
    }
    sqlite3_finalize(stmt);

    rc = sqlite3_prepare_v2(database,
                            "INSERT INTO process_metrics "
                            "(collected_at, pid, name, cpu_percent, resident_bytes, started_at, runtime_seconds) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?);",
                            -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        exec_sql("ROLLBACK;");
        return -1;
    }

    limit = snapshot->processes.count < TOP_PROCESS_LIMIT ? snapshot->processes.count : TOP_PROCESS_LIMIT;
    for (size_t i = 0; i < limit; i++) {
        const process_metrics_t *process = &snapshot->processes.processes[i];
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)snapshot->processes.collected_at);
        sqlite3_bind_int(stmt, 2, process->pid);
        sqlite3_bind_text(stmt, 3, process->name, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, process->cpu_percent);
        sqlite3_bind_int64(stmt, 5, (sqlite3_int64)process->resident_bytes);
        sqlite3_bind_int64(stmt, 6, (sqlite3_int64)process->started_at);
        sqlite3_bind_int64(stmt, 7, (sqlite3_int64)process->runtime_seconds);

        if (sqlite3_step(stmt) != SQLITE_DONE) {
            sqlite3_finalize(stmt);
            exec_sql("ROLLBACK;");
            return -1;
        }
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
    }

    sqlite3_finalize(stmt);
    return exec_sql("COMMIT;");
}

int storage_export_report(const char *path, const agent_snapshot_t *snapshot) {
    FILE *file;
    size_t limit;

    if (!path || !snapshot) {
        return -1;
    }

    file = fopen(path, "w");
    if (!file) {
        return -1;
    }

    fprintf(file, "Miransas Pulse Diagnostics Report\n");
    fprintf(file, "Collected at: %ld\n", (long)snapshot->processes.collected_at);
    fprintf(file, "System CPU: %.2f%%\n", snapshot->system.cpu_usage);
    fprintf(file, "RAM free: %llu MB / %llu MB\n",
            (unsigned long long)snapshot->system.free_ram,
            (unsigned long long)snapshot->system.total_ram);
    fprintf(file, "Health score: %d\n\n", snapshot->health_score);
    fprintf(file, "Top resource consumers\n");

    limit = snapshot->processes.count < TOP_PROCESS_LIMIT ? snapshot->processes.count : TOP_PROCESS_LIMIT;
    for (size_t i = 0; i < limit; i++) {
        const process_metrics_t *process = &snapshot->processes.processes[i];
        fprintf(file, "%zu. %s pid=%d cpu=%.2f%% ram=%llu runtime=%llus\n",
                i + 1,
                process->name,
                process->pid,
                process->cpu_percent,
                (unsigned long long)process->resident_bytes,
                (unsigned long long)process->runtime_seconds);
    }

    fclose(file);
    return 0;
}
