#!/usr/bin/env sh
set -eu

cc -Wall -Wextra -Iinclude tests/test_health_os.c src/health_os/core.c -o /tmp/health_os_tests
/tmp/health_os_tests
cc -Wall -Wextra -Iinclude tests/test_agent_core.c src/process.c -o /tmp/agent_core_tests
/tmp/agent_core_tests
printf '%s\n' '[HealthOS-Tests] all tests passed'
