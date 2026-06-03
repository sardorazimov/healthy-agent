#!/usr/bin/env sh
set -eu

cc -Wall -Wextra -Iinclude tests/test_agent_core.c src/process.c -o /tmp/agent_core_tests
/tmp/agent_core_tests
printf '%s\n' '[Pulse-Tests] all tests passed'
