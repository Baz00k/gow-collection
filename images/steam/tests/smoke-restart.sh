#!/bin/bash
set -euo pipefail

# =============================================================================
# Smoke Test: gow-launcher.sh Restart Behavior
# =============================================================================
# Tests the restart logic of gow-launcher.sh without requiring Docker.
# Verifies exit code handling, restart limits, and environment configuration.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_SCRIPT="${SCRIPT_DIR}/../build/overlay/opt/gow/gow-launcher.sh"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/restart.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

mkdir -p "${EVIDENCE_DIR}"

{
    echo "=== Smoke Test: gow-launcher Restart Behavior ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Launcher: ${LAUNCHER_SCRIPT}"
    echo ""
} > "${EVIDENCE_FILE}"

cleanup() {
    # Kill any lingering test processes
    pkill -f "test-mock-exit" 2>/dev/null || true
}
trap cleanup EXIT

# =============================================================================
# Verify launcher script exists
# =============================================================================
if [[ ! -f "${LAUNCHER_SCRIPT}" ]]; then
    log_error "Launcher script not found at ${LAUNCHER_SCRIPT}"
    echo "ERROR: Launcher script not found" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ ! -x "${LAUNCHER_SCRIPT}" ]]; then
    log_error "Launcher script is not executable"
    echo "ERROR: Launcher script not executable" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Launcher script found and executable"

# =============================================================================
# Test helper: Create mock command that exits with specific code
# =============================================================================
create_mock_exit_script() {
    local exit_code="$1"
    local call_count_file="$2"
    local tmp_script
    tmp_script=$(mktemp)
    
    cat > "${tmp_script}" << EOF
#!/bin/bash
# Increment call counter
if [[ -f "${call_count_file}" ]]; then
    COUNT=\$(( \$(cat "${call_count_file}") + 1 ))
else
    COUNT=1
fi
echo "\${COUNT}" > "${call_count_file}"
# Exit with requested code
exit ${exit_code}
EOF
    chmod +x "${tmp_script}"
    echo "${tmp_script}"
}

# =============================================================================
# Test 1: Exit code 7 triggers shutdown (no restart)
# =============================================================================
test_exit7_shutdown() {
    log_info "Test 1: Exit code 7 should trigger shutdown without restart"
    
    local call_count_file
    call_count_file=$(mktemp)
    
    local mock_script
    mock_script=$(create_mock_exit_script 7 "${call_count_file}")
    
    # Run launcher with mock
    set +e
    GOW_MAX_RESTARTS=5 "${LAUNCHER_SCRIPT}" "${mock_script}"
    local exit_code=$?
    set -e
    
    local call_count
    call_count=$(cat "${call_count_file}" 2>/dev/null || echo "0")
    
    # Cleanup
    rm -f "${mock_script}" "${call_count_file}"
    
    {
        echo "=== Test 1: Exit 7 Shutdown ==="
        echo "Expected: 1 call, exit code 0"
        echo "Actual: ${call_count} call(s), exit code ${exit_code}"
        echo ""
    } >> "${EVIDENCE_FILE}"
    
    if [[ "${call_count}" != "1" ]]; then
        log_error "Exit 7 should not restart, but got ${call_count} calls"
        echo "RESULT: FAILED (unexpected restarts)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    if [[ "${exit_code}" != "0" ]]; then
        log_error "Exit 7 should return 0, got ${exit_code}"
        echo "RESULT: FAILED (wrong exit code)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    log_info "Test 1 PASSED: Exit 7 triggers shutdown correctly"
    return 0
}

# =============================================================================
# Test 2: Exit code 0 with GOW_RESTART_ON_EXIT0=true triggers restart
# =============================================================================
test_exit0_restart() {
    log_info "Test 2: Exit code 0 with RESTART_ON_EXIT0=true should restart"
    
    local call_count_file
    call_count_file=$(mktemp)
    echo "0" > "${call_count_file}"
    
    local mock_script
    mock_script=$(create_mock_exit_script 0 "${call_count_file}")
    
    # Run launcher with restart enabled, limited to 2 restarts
    set +e
    GOW_RESTART_ON_EXIT0=true GOW_MAX_RESTARTS=2 GOW_RESTART_DELAY=0 "${LAUNCHER_SCRIPT}" "${mock_script}"
    local exit_code=$?
    set -e
    
    local call_count
    call_count=$(cat "${call_count_file}" 2>/dev/null || echo "0")
    
    # Cleanup
    rm -f "${mock_script}" "${call_count_file}"
    
    {
        echo "=== Test 2: Exit 0 Restart ==="
        echo "Expected: 3 calls (1 initial + 2 restarts), exit code 0"
        echo "Actual: ${call_count} call(s), exit code ${exit_code}"
        echo ""
    } >> "${EVIDENCE_FILE}"
    
    # Initial run + 2 restarts = 3 calls
    if [[ "${call_count}" != "3" ]]; then
        log_error "Expected 3 calls (1 + 2 restarts), got ${call_count}"
        echo "RESULT: FAILED (wrong restart count)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    # Should exit with 0 (last process exit code)
    if [[ "${exit_code}" != "0" ]]; then
        log_error "Exit 0 restart should return 0, got ${exit_code}"
        echo "RESULT: FAILED (wrong exit code)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    log_info "Test 2 PASSED: Exit 0 with RESTART_ON_EXIT0=true restarts correctly"
    return 0
}

# =============================================================================
# Test 3: Exit code 0 without GOW_RESTART_ON_EXIT0 exits immediately
# =============================================================================
test_exit0_no_restart() {
    log_info "Test 3: Exit code 0 without RESTART_ON_EXIT0 should exit immediately"
    
    local call_count_file
    call_count_file=$(mktemp)
    echo "0" > "${call_count_file}"
    
    local mock_script
    mock_script=$(create_mock_exit_script 0 "${call_count_file}")
    
    # Run launcher WITHOUT restart on exit 0
    set +e
    GOW_RESTART_ON_EXIT0=false GOW_MAX_RESTARTS=5 GOW_RESTART_DELAY=0 "${LAUNCHER_SCRIPT}" "${mock_script}"
    local exit_code=$?
    set -e
    
    local call_count
    call_count=$(cat "${call_count_file}" 2>/dev/null || echo "0")
    
    # Cleanup
    rm -f "${mock_script}" "${call_count_file}"
    
    {
        echo "=== Test 3: Exit 0 No Restart ==="
        echo "Expected: 1 call, exit code 0"
        echo "Actual: ${call_count} call(s), exit code ${exit_code}"
        echo ""
    } >> "${EVIDENCE_FILE}"
    
    if [[ "${call_count}" != "1" ]]; then
        log_error "Exit 0 without RESTART_ON_EXIT0 should not restart, got ${call_count} calls"
        echo "RESULT: FAILED (unexpected restarts)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    if [[ "${exit_code}" != "0" ]]; then
        log_error "Exit 0 should return 0, got ${exit_code}"
        echo "RESULT: FAILED (wrong exit code)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    log_info "Test 3 PASSED: Exit 0 without RESTART_ON_EXIT0 exits immediately"
    return 0
}

# =============================================================================
# Test 4: Error exit with GOW_MAX_RESTARTS limit
# =============================================================================
test_error_max_restarts() {
    log_info "Test 4: Error exit with MAX_RESTARTS limit"
    
    local call_count_file
    call_count_file=$(mktemp)
    echo "0" > "${call_count_file}"
    
    local mock_script
    mock_script=$(create_mock_exit_script 1 "${call_count_file}")
    
    # Run launcher with error restart enabled, limited to 2 restarts
    set +e
    GOW_RESTART_ON_ERROR=true GOW_MAX_RESTARTS=2 GOW_RESTART_DELAY=0 "${LAUNCHER_SCRIPT}" "${mock_script}"
    local exit_code=$?
    set -e
    
    local call_count
    call_count=$(cat "${call_count_file}" 2>/dev/null || echo "0")
    
    # Cleanup
    rm -f "${mock_script}" "${call_count_file}"
    
    {
        echo "=== Test 4: Error Max Restarts ==="
        echo "Expected: 3 calls (1 initial + 2 restarts), exit code 1"
        echo "Actual: ${call_count} call(s), exit code ${exit_code}"
        echo ""
    } >> "${EVIDENCE_FILE}"
    
    # Initial run + 2 restarts = 3 calls
    if [[ "${call_count}" != "3" ]]; then
        log_error "Expected 3 calls (1 + 2 restarts), got ${call_count}"
        echo "RESULT: FAILED (wrong restart count)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    # Should exit with 1 (last process exit code)
    if [[ "${exit_code}" != "1" ]]; then
        log_error "Error exit should return 1, got ${exit_code}"
        echo "RESULT: FAILED (wrong exit code)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    log_info "Test 4 PASSED: Error exit respects MAX_RESTARTS limit"
    return 0
}

# =============================================================================
# Test 5: GOW_RESTART_ON_ERROR=false exits immediately on error
# =============================================================================
test_error_no_restart() {
    log_info "Test 5: Error exit with RESTART_ON_ERROR=false should exit immediately"
    
    local call_count_file
    call_count_file=$(mktemp)
    echo "0" > "${call_count_file}"
    
    local mock_script
    mock_script=$(create_mock_exit_script 42 "${call_count_file}")
    
    # Run launcher WITHOUT restart on error
    set +e
    GOW_RESTART_ON_ERROR=false GOW_MAX_RESTARTS=5 GOW_RESTART_DELAY=0 "${LAUNCHER_SCRIPT}" "${mock_script}"
    local exit_code=$?
    set -e
    
    local call_count
    call_count=$(cat "${call_count_file}" 2>/dev/null || echo "0")
    
    # Cleanup
    rm -f "${mock_script}" "${call_count_file}"
    
    {
        echo "=== Test 5: Error No Restart ==="
        echo "Expected: 1 call, exit code 42"
        echo "Actual: ${call_count} call(s), exit code ${exit_code}"
        echo ""
    } >> "${EVIDENCE_FILE}"
    
    if [[ "${call_count}" != "1" ]]; then
        log_error "Error without RESTART_ON_ERROR should not restart, got ${call_count} calls"
        echo "RESULT: FAILED (unexpected restarts)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    # Should exit with the original error code
    if [[ "${exit_code}" != "42" ]]; then
        log_error "Should exit with code 42, got ${exit_code}"
        echo "RESULT: FAILED (wrong exit code)" >> "${EVIDENCE_FILE}"
        return 1
    fi
    
    log_info "Test 5 PASSED: Error exit without RESTART_ON_ERROR exits immediately"
    return 0
}

# =============================================================================
# Run all tests
# =============================================================================
TESTS_PASSED=0
TESTS_FAILED=0

{
    echo "=== Running Tests ==="
    echo ""
} >> "${EVIDENCE_FILE}"

if test_exit7_shutdown; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Test 1: PASSED" >> "${EVIDENCE_FILE}"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "Test 1: FAILED" >> "${EVIDENCE_FILE}"
fi

if test_exit0_restart; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Test 2: PASSED" >> "${EVIDENCE_FILE}"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "Test 2: FAILED" >> "${EVIDENCE_FILE}"
fi

if test_exit0_no_restart; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Test 3: PASSED" >> "${EVIDENCE_FILE}"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "Test 3: FAILED" >> "${EVIDENCE_FILE}"
fi

if test_error_max_restarts; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Test 4: PASSED" >> "${EVIDENCE_FILE}"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "Test 4: FAILED" >> "${EVIDENCE_FILE}"
fi

if test_error_no_restart; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Test 5: PASSED" >> "${EVIDENCE_FILE}"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "Test 5: FAILED" >> "${EVIDENCE_FILE}"
fi

{
    echo ""
    echo "=== Summary ==="
    echo "Passed: ${TESTS_PASSED}"
    echo "Failed: ${TESTS_FAILED}"
} >> "${EVIDENCE_FILE}"

echo ""
echo "=== Test Results ==="
echo "Passed: ${TESTS_PASSED}"
echo "Failed: ${TESTS_FAILED}"
echo ""

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    log_error "Some tests failed"
    echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "All restart tests passed"
echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
echo "=== TEST PASSED ==="
exit 0
