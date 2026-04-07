#!/usr/bin/env bats

# Tests for scripts/lib/common.sh

setup() {
    # Source common.sh in a subshell-safe way
    export LOG_LEVEL="debug"
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
}

# --- log() tests ---

@test "log info prints message to stdout" {
    run log info "hello world"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"INFO"* ]]
    [[ "$output" == *"hello world"* ]]
}

@test "log debug prints message when LOG_LEVEL=debug" {
    export LOG_LEVEL="debug"
    run log debug "debug message"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"DEBUG"* ]]
    [[ "$output" == *"debug message"* ]]
}

@test "log debug is suppressed when LOG_LEVEL=info" {
    export LOG_LEVEL="info"
    run log debug "should not appear"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}

@test "log warn prints message" {
    run log warn "warning message"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"warning message"* ]]
}

@test "log error exits with code 1" {
    run log error "fatal error"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"fatal error"* ]]
}

@test "log info with key=value data" {
    run log info "test message" "key=value"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"test message"* ]]
    [[ "$output" == *"key="* ]]
    [[ "$output" == *"value"* ]]
}

@test "log respects level priority ordering" {
    export LOG_LEVEL="warn"
    run log info "should be hidden"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]

    run log warn "should be visible"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"WARN"* ]]
}

# --- check_env() tests ---

@test "check_env passes when env vars are set" {
    export TEST_VAR_A="hello"
    export TEST_VAR_B="world"
    run check_env TEST_VAR_A TEST_VAR_B
    [[ "$status" -eq 0 ]]
}

@test "check_env fails when env var is missing" {
    unset MISSING_VAR 2>/dev/null || true
    run check_env MISSING_VAR
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Missing required env variables"* ]]
}

@test "check_env fails when one of multiple vars is missing" {
    export PRESENT_VAR="exists"
    unset ABSENT_VAR 2>/dev/null || true
    run check_env PRESENT_VAR ABSENT_VAR
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ABSENT_VAR"* ]]
}

# --- check_cli() tests ---

@test "check_cli passes for installed tools" {
    run check_cli bash
    [[ "$status" -eq 0 ]]
}

@test "check_cli fails for missing tools" {
    run check_cli nonexistent_tool_xyz
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Missing required deps"* ]]
}

@test "check_cli checks multiple tools" {
    run check_cli bash sh
    [[ "$status" -eq 0 ]]
}

@test "check_cli fails if any tool is missing" {
    run check_cli bash nonexistent_tool_xyz
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"nonexistent_tool_xyz"* ]]
}
