#include "health_os/health_os.h"

#include <assert.h>
#include <string.h>
#include <time.h>

static void test_profile_validation(void) {
    health_os_profile_t profile = {0};
    char error[128];

    strcpy(profile.id, "user_1");
    strcpy(profile.display_name, "Sardor");
    profile.birth_year = 1995;
    profile.height_cm = 178.0;
    profile.weight_kg = 76.0;

    assert(health_os_validate_profile(&profile, error, sizeof(error)) == 1);

    profile.birth_year = 1800;
    assert(health_os_validate_profile(&profile, error, sizeof(error)) == 0);
}

static void test_goal_progress_and_score(void) {
    health_os_goal_t goal = {0};
    goal.target_value = 10.0;
    goal.current_value = 4.0;

    assert(health_os_goal_progress(&goal) > 0.39);
    assert(health_os_goal_progress(&goal) < 0.41);

    health_os_score_t score = health_os_calculate_score(80.0, 7.0, 20.0, 1);
    assert(score.nutrition_score == 80);
    assert(score.sleep_score == 88);
    assert(score.fitness_score == 67);
    assert(score.safety_score == 80);
    assert(score.score == 79);
}

static void test_guardrails(void) {
    char message[256];
    health_os_safety_level_t level;

    level = health_os_check_medical_safety("I have chest pain", message, sizeof(message));
    assert(level == HEALTH_OS_SAFETY_BLOCKED);

    level = health_os_check_medical_safety("Can you change my dosage?", message, sizeof(message));
    assert(level == HEALTH_OS_SAFETY_CAUTION);

    level = health_os_check_medical_safety("How can I build a walking habit?", message, sizeof(message));
    assert(level == HEALTH_OS_SAFETY_OK);
}

static void test_rag_agent_and_reminders(void) {
    health_os_knowledge_doc_t docs[2] = {0};
    health_os_profile_t profile = {0};
    health_os_goal_t goal = {0};
    health_os_rag_result_t result;
    health_os_agent_response_t response;
    health_os_reminder_t reminder = {0};
    time_t now = time(NULL);

    strcpy(docs[0].id, "doc_sleep");
    strcpy(docs[0].title, "Sleep consistency");
    strcpy(docs[0].content, "Wake time consistency improves sleep rhythm.");
    strcpy(docs[1].id, "doc_fitness");
    strcpy(docs[1].title, "Strength training");
    strcpy(docs[1].content, "Progressive overload should be gradual.");

    result = health_os_retrieve("sleep", docs, 2);
    assert(result.count == 1);

    strcpy(profile.display_name, "Sardor");
    goal.status = HEALTH_OS_GOAL_ACTIVE;
    response = health_os_run_agent(HEALTH_OS_AGENT_SLEEP, &profile, &goal, 1, &result);
    assert(strstr(response.summary, "Sardor") != NULL);
    assert(strstr(response.action, "wake time") != NULL);

    reminder.due_at = now - 60;
    assert(health_os_reminder_due(&reminder, now) == 1);
    reminder.delivered = 1;
    assert(health_os_reminder_due(&reminder, now) == 0);
}

int main(void) {
    test_profile_validation();
    test_goal_progress_and_score();
    test_guardrails();
    test_rag_agent_and_reminders();
    return 0;
}
