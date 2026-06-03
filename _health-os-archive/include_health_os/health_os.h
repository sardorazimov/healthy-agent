#ifndef HEALTH_OS_H
#define HEALTH_OS_H

#include <stddef.h>
#include <stdint.h>
#include <time.h>

#define HEALTH_OS_ID_LEN 64
#define HEALTH_OS_TEXT_LEN 512
#define HEALTH_OS_NAME_LEN 128
#define HEALTH_OS_MAX_RESULTS 8

typedef enum {
    HEALTH_OS_SEX_UNSPECIFIED = 0,
    HEALTH_OS_SEX_FEMALE,
    HEALTH_OS_SEX_MALE,
    HEALTH_OS_SEX_OTHER
} health_os_sex_t;

typedef enum {
    HEALTH_OS_EVENT_NOTE = 0,
    HEALTH_OS_EVENT_NUTRITION,
    HEALTH_OS_EVENT_SLEEP,
    HEALTH_OS_EVENT_FITNESS,
    HEALTH_OS_EVENT_BIOMETRIC,
    HEALTH_OS_EVENT_MEDICATION,
    HEALTH_OS_EVENT_REMINDER
} health_os_event_type_t;

typedef enum {
    HEALTH_OS_GOAL_ACTIVE = 0,
    HEALTH_OS_GOAL_PAUSED,
    HEALTH_OS_GOAL_COMPLETED
} health_os_goal_status_t;

typedef enum {
    HEALTH_OS_AGENT_NUTRITION = 0,
    HEALTH_OS_AGENT_SLEEP,
    HEALTH_OS_AGENT_FITNESS
} health_os_agent_type_t;

typedef enum {
    HEALTH_OS_SAFETY_OK = 0,
    HEALTH_OS_SAFETY_CAUTION,
    HEALTH_OS_SAFETY_BLOCKED
} health_os_safety_level_t;

typedef struct {
    char id[HEALTH_OS_ID_LEN];
    char display_name[HEALTH_OS_NAME_LEN];
    int birth_year;
    health_os_sex_t sex;
    double height_cm;
    double weight_kg;
    char locale[16];
    time_t created_at;
    time_t updated_at;
} health_os_profile_t;

typedef struct {
    char id[HEALTH_OS_ID_LEN];
    char user_id[HEALTH_OS_ID_LEN];
    health_os_event_type_t type;
    time_t occurred_at;
    char title[HEALTH_OS_NAME_LEN];
    char body[HEALTH_OS_TEXT_LEN];
    double value;
    char unit[32];
    char source[64];
} health_os_timeline_event_t;

typedef struct {
    char id[HEALTH_OS_ID_LEN];
    char user_id[HEALTH_OS_ID_LEN];
    char title[HEALTH_OS_NAME_LEN];
    char metric[64];
    double target_value;
    double current_value;
    char unit[32];
    time_t due_at;
    health_os_goal_status_t status;
} health_os_goal_t;

typedef struct {
    char id[HEALTH_OS_ID_LEN];
    char user_id[HEALTH_OS_ID_LEN];
    char text[HEALTH_OS_TEXT_LEN];
    char tags[128];
    time_t observed_at;
    double importance;
} health_os_memory_t;

typedef struct {
    char id[HEALTH_OS_ID_LEN];
    char user_id[HEALTH_OS_ID_LEN];
    char title[HEALTH_OS_NAME_LEN];
    char instructions[HEALTH_OS_TEXT_LEN];
    time_t due_at;
    int repeat_minutes;
    int delivered;
} health_os_reminder_t;

typedef struct {
    char id[HEALTH_OS_ID_LEN];
    char title[HEALTH_OS_NAME_LEN];
    char content[HEALTH_OS_TEXT_LEN];
    char citation[HEALTH_OS_NAME_LEN];
    double score;
} health_os_knowledge_doc_t;

typedef struct {
    char summary[HEALTH_OS_TEXT_LEN];
    char action[HEALTH_OS_TEXT_LEN];
    health_os_safety_level_t safety_level;
} health_os_agent_response_t;

typedef struct {
    int score;
    int nutrition_score;
    int sleep_score;
    int fitness_score;
    int safety_score;
} health_os_score_t;

typedef struct {
    health_os_knowledge_doc_t documents[HEALTH_OS_MAX_RESULTS];
    size_t count;
} health_os_rag_result_t;

int health_os_validate_profile(const health_os_profile_t *profile, char *error, size_t error_size);
double health_os_goal_progress(const health_os_goal_t *goal);
health_os_score_t health_os_calculate_score(double nutrition_quality,
                                            double sleep_hours,
                                            double active_minutes,
                                            int open_safety_flags);
health_os_safety_level_t health_os_check_medical_safety(const char *input,
                                                        char *message,
                                                        size_t message_size);
health_os_agent_response_t health_os_run_agent(health_os_agent_type_t agent,
                                               const health_os_profile_t *profile,
                                               const health_os_goal_t *goals,
                                               size_t goal_count,
                                               const health_os_rag_result_t *context);
health_os_rag_result_t health_os_retrieve(const char *query,
                                          const health_os_knowledge_doc_t *documents,
                                          size_t document_count);
int health_os_reminder_due(const health_os_reminder_t *reminder, time_t now);

#endif
