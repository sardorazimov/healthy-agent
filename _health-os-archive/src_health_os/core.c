#include "health_os/health_os.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

static int clamp_score(double value) {
    if (value < 0.0) {
        return 0;
    }
    if (value > 100.0) {
        return 100;
    }
    return (int)(value + 0.5);
}

static int contains_case_insensitive(const char *haystack, const char *needle) {
    size_t needle_len;

    if (!haystack || !needle) {
        return 0;
    }

    needle_len = strlen(needle);
    if (needle_len == 0) {
        return 1;
    }

    for (const char *p = haystack; *p; p++) {
        size_t i = 0;
        while (p[i] && i < needle_len &&
               tolower((unsigned char)p[i]) == tolower((unsigned char)needle[i])) {
            i++;
        }
        if (i == needle_len) {
            return 1;
        }
    }

    return 0;
}

int health_os_validate_profile(const health_os_profile_t *profile, char *error, size_t error_size) {
    if (!profile) {
        snprintf(error, error_size, "profile is required");
        return 0;
    }
    if (profile->id[0] == '\0') {
        snprintf(error, error_size, "profile id is required");
        return 0;
    }
    if (profile->display_name[0] == '\0') {
        snprintf(error, error_size, "display name is required");
        return 0;
    }
    if (profile->birth_year != 0 && (profile->birth_year < 1900 || profile->birth_year > 2026)) {
        snprintf(error, error_size, "birth year is outside supported range");
        return 0;
    }
    if (profile->height_cm < 0.0 || profile->weight_kg < 0.0) {
        snprintf(error, error_size, "height and weight cannot be negative");
        return 0;
    }

    if (error && error_size > 0) {
        error[0] = '\0';
    }
    return 1;
}

double health_os_goal_progress(const health_os_goal_t *goal) {
    if (!goal || goal->target_value <= 0.0) {
        return 0.0;
    }

    double progress = goal->current_value / goal->target_value;
    if (progress < 0.0) {
        return 0.0;
    }
    if (progress > 1.0) {
        return 1.0;
    }
    return progress;
}

health_os_score_t health_os_calculate_score(double nutrition_quality,
                                            double sleep_hours,
                                            double active_minutes,
                                            int open_safety_flags) {
    health_os_score_t score;

    score.nutrition_score = clamp_score(nutrition_quality);
    score.sleep_score = clamp_score((sleep_hours / 8.0) * 100.0);
    score.fitness_score = clamp_score((active_minutes / 30.0) * 100.0);
    score.safety_score = clamp_score(100.0 - (open_safety_flags * 20.0));
    score.score = clamp_score((score.nutrition_score * 0.25) +
                              (score.sleep_score * 0.25) +
                              (score.fitness_score * 0.25) +
                              (score.safety_score * 0.25));

    return score;
}

health_os_safety_level_t health_os_check_medical_safety(const char *input,
                                                        char *message,
                                                        size_t message_size) {
    static const char *blocked_terms[] = {
        "chest pain", "suicidal", "overdose", "can't breathe", "cannot breathe", "stroke"
    };
    static const char *caution_terms[] = {
        "diagnose", "prescribe", "stop medication", "dosage", "pregnant"
    };

    for (size_t i = 0; i < sizeof(blocked_terms) / sizeof(blocked_terms[0]); i++) {
        if (contains_case_insensitive(input, blocked_terms[i])) {
            snprintf(message, message_size,
                     "Potential urgent medical issue detected. Seek emergency or licensed medical help now.");
            return HEALTH_OS_SAFETY_BLOCKED;
        }
    }

    for (size_t i = 0; i < sizeof(caution_terms) / sizeof(caution_terms[0]); i++) {
        if (contains_case_insensitive(input, caution_terms[i])) {
            snprintf(message, message_size,
                     "Medical advice needs clinician oversight. Provide general education and recommend professional care.");
            return HEALTH_OS_SAFETY_CAUTION;
        }
    }

    snprintf(message, message_size, "No safety escalation detected.");
    return HEALTH_OS_SAFETY_OK;
}

health_os_agent_response_t health_os_run_agent(health_os_agent_type_t agent,
                                               const health_os_profile_t *profile,
                                               const health_os_goal_t *goals,
                                               size_t goal_count,
                                               const health_os_rag_result_t *context) {
    health_os_agent_response_t response;
    const char *name = profile && profile->display_name[0] ? profile->display_name : "User";
    const char *context_title = context && context->count > 0 ? context->documents[0].title : "baseline guidance";
    size_t active_goals = 0;

    memset(&response, 0, sizeof(response));
    response.safety_level = HEALTH_OS_SAFETY_OK;

    for (size_t i = 0; goals && i < goal_count; i++) {
        if (goals[i].status == HEALTH_OS_GOAL_ACTIVE) {
            active_goals++;
        }
    }

    switch (agent) {
        case HEALTH_OS_AGENT_NUTRITION:
            snprintf(response.summary, sizeof(response.summary),
                     "%s has %zu active goal(s). Nutrition context: %s.", name, active_goals, context_title);
            snprintf(response.action, sizeof(response.action),
                     "Prioritize protein, fiber, hydration, and a logged meal rhythm for the next seven days.");
            break;
        case HEALTH_OS_AGENT_SLEEP:
            snprintf(response.summary, sizeof(response.summary),
                     "%s has %zu active goal(s). Sleep context: %s.", name, active_goals, context_title);
            snprintf(response.action, sizeof(response.action),
                     "Stabilize wake time, reduce late caffeine, and track sleep duration and quality nightly.");
            break;
        case HEALTH_OS_AGENT_FITNESS:
            snprintf(response.summary, sizeof(response.summary),
                     "%s has %zu active goal(s). Fitness context: %s.", name, active_goals, context_title);
            snprintf(response.action, sizeof(response.action),
                     "Build a progressive plan around daily movement, two strength sessions, and recovery signals.");
            break;
    }

    return response;
}

health_os_rag_result_t health_os_retrieve(const char *query,
                                          const health_os_knowledge_doc_t *documents,
                                          size_t document_count) {
    health_os_rag_result_t result;
    memset(&result, 0, sizeof(result));

    if (!query || !documents) {
        return result;
    }

    for (size_t i = 0; i < document_count && result.count < HEALTH_OS_MAX_RESULTS; i++) {
        if (contains_case_insensitive(documents[i].title, query) ||
            contains_case_insensitive(documents[i].content, query)) {
            result.documents[result.count] = documents[i];
            result.documents[result.count].score = 1.0;
            result.count++;
        }
    }

    return result;
}

int health_os_reminder_due(const health_os_reminder_t *reminder, time_t now) {
    if (!reminder || reminder->delivered) {
        return 0;
    }
    return reminder->due_at <= now;
}
