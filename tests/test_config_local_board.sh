#!/bin/bash
#
# Test that config.local can override BASE_BOARD before generate_board_config.py runs.
# This mimics the pre-seed flow in src/build.
#

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOMPIOS_ROOT="$(cd "${DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_count=0
tests_passed=0
failed_tests=()

print_test_header() {
    local test_name="$1"
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════"
    echo "TEST: $test_name"
    echo -e "════════════════════════════════════════════════════════════════════════════════${NC}"
}

print_test_result() {
    local test_name="$1"
    local is_passed="$2"
    local detail="$3"

    if $is_passed; then
        echo -e "${GREEN}✓ PASSED:${NC} $test_name"
    else
        echo -e "${RED}✗ FAILED:${NC} $test_name"
        echo -e "${BLUE}Detail:${NC} $detail"
    fi
}

# Helper: mimic src/build pre-seed flow then run generate_board_config.py
# Arguments:
#   $1 - path to dist config file
#   $2 - path to dist config.local file (or empty)
#   $3 - path to output script
#   $4 - path to variant config file (or empty)
run_build_preseed_flow() {
    local config_file="$1"
    local config_local_file="$2"
    local output_script="$3"
    local variant_config_file="$4"

    # Run in a subshell to avoid polluting the test environment
    (
        # Unset BASE_BOARD to start clean
        unset BASE_BOARD

        # Mimic src/build pre-seed: config, then variant, then config.local
        if [ -f "${config_file}" ]; then
            source "${config_file}"
        fi
        if [ -n "${variant_config_file}" ] && [ -f "${variant_config_file}" ]; then
            source "${variant_config_file}"
        fi
        if [ -n "${config_local_file}" ] && [ -f "${config_local_file}" ]; then
            source "${config_local_file}"
        fi

        # Mimic the heredoc bash -c check (config < variant < config.local)
        BASE_BOARD_FROM_CONFIG=$(bash -c "source \"${config_file}\" >/dev/null 2>&1; \
            [ -n \"${variant_config_file}\" ] && [ -f \"${variant_config_file}\" ] && source \"${variant_config_file}\" >/dev/null 2>&1; \
            [ -n \"${config_local_file}\" ] && [ -f \"${config_local_file}\" ] && source \"${config_local_file}\" >/dev/null 2>&1; \
            echo \$BASE_BOARD")
        if [ -n "$BASE_BOARD_FROM_CONFIG" ]; then
            export BASE_BOARD="$BASE_BOARD_FROM_CONFIG"
        fi

        # Set CUSTOM_PI_OS_PATH so common.py can find images.yml
        export CUSTOM_PI_OS_PATH="${CUSTOMPIOS_ROOT}/src"

        # Run generate_board_config.py
        python3 "${CUSTOMPIOS_ROOT}/src/custompios_core/generate_board_config.py" "${output_script}"
    )
}

# Test 1: No config.local → defaults to armhf
test_no_config_local_defaults_to_armhf() {
    local test_name="No config.local defaults to BASE_ARCH=armhf"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local output_script="${tmpdir}/board_config.sh"

    # Create a dist config that does NOT set BASE_BOARD
    cat > "${config_file}" <<'CONF'
# Dist config without BASE_BOARD
export SOME_OTHER_VAR="hello"
CONF

    run_build_preseed_flow "${config_file}" "" "${output_script}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="armhf"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"armhf\" in output"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Test 2: config.local sets BASE_BOARD=raspberrypiarm64 → BASE_ARCH=arm64
test_config_local_sets_arm64() {
    local test_name="config.local with BASE_BOARD=raspberrypiarm64 produces BASE_ARCH=arm64"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local config_local_file="${tmpdir}/config.local"
    local output_script="${tmpdir}/board_config.sh"

    # Create a dist config that does NOT set BASE_BOARD
    cat > "${config_file}" <<'CONF'
# Dist config without BASE_BOARD
export SOME_OTHER_VAR="hello"
CONF

    # Create config.local that sets BASE_BOARD
    cat > "${config_local_file}" <<'CONF'
export BASE_BOARD=raspberrypiarm64
CONF

    run_build_preseed_flow "${config_file}" "${config_local_file}" "${output_script}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="arm64"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"arm64\" in output"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Test 3: config.local overrides config's BASE_BOARD
test_config_local_overrides_config() {
    local test_name="config.local BASE_BOARD overrides config BASE_BOARD"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local config_local_file="${tmpdir}/config.local"
    local output_script="${tmpdir}/board_config.sh"

    # Config sets armhf board
    cat > "${config_file}" <<'CONF'
export BASE_BOARD=raspberrypiarmhf
CONF

    # config.local overrides to arm64
    cat > "${config_local_file}" <<'CONF'
export BASE_BOARD=raspberrypiarm64
CONF

    run_build_preseed_flow "${config_file}" "${config_local_file}" "${output_script}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="arm64"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"arm64\" (config.local should win)"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Test 4: Config sets BASE_BOARD, no config.local → uses config's value
test_config_sets_board_no_local() {
    local test_name="Config sets BASE_BOARD=raspberrypiarm64, no config.local"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local output_script="${tmpdir}/board_config.sh"

    # Config sets arm64 board
    cat > "${config_file}" <<'CONF'
export BASE_BOARD=raspberrypiarm64
CONF

    run_build_preseed_flow "${config_file}" "" "${output_script}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="arm64"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"arm64\" from config"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Test 5: Variant sets BASE_BOARD=raspberrypiarm64, no config.local → BASE_ARCH=arm64
test_variant_sets_arm64() {
    local test_name="Variant sets BASE_BOARD=raspberrypiarm64, no config.local"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local variant_config_file="${tmpdir}/variant_config"
    local output_script="${tmpdir}/board_config.sh"

    # Dist config does NOT set BASE_BOARD
    cat > "${config_file}" <<'CONF'
export SOME_OTHER_VAR="hello"
CONF

    # Variant config sets arm64 board
    cat > "${variant_config_file}" <<'CONF'
export BASE_BOARD=raspberrypiarm64
CONF

    run_build_preseed_flow "${config_file}" "" "${output_script}" "${variant_config_file}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="arm64"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"arm64\" from variant"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Test 6: config.local overrides variant's BASE_BOARD
test_config_local_overrides_variant() {
    local test_name="config.local BASE_BOARD overrides variant BASE_BOARD"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local config_local_file="${tmpdir}/config.local"
    local variant_config_file="${tmpdir}/variant_config"
    local output_script="${tmpdir}/board_config.sh"

    # Dist config does NOT set BASE_BOARD
    cat > "${config_file}" <<'CONF'
export SOME_OTHER_VAR="hello"
CONF

    # Variant sets armhf
    cat > "${variant_config_file}" <<'CONF'
export BASE_BOARD=raspberrypiarmhf
CONF

    # config.local overrides to arm64
    cat > "${config_local_file}" <<'CONF'
export BASE_BOARD=raspberrypiarm64
CONF

    run_build_preseed_flow "${config_file}" "${config_local_file}" "${output_script}" "${variant_config_file}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="arm64"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"arm64\" (config.local should win over variant)"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Test 7: Variant overrides dist config's BASE_BOARD
test_variant_overrides_config() {
    local test_name="Variant BASE_BOARD overrides dist config BASE_BOARD"
    print_test_header "$test_name"
    ((test_count++))

    local tmpdir=$(mktemp -d)
    local config_file="${tmpdir}/config"
    local variant_config_file="${tmpdir}/variant_config"
    local output_script="${tmpdir}/board_config.sh"

    # Dist config sets armhf
    cat > "${config_file}" <<'CONF'
export BASE_BOARD=raspberrypiarmhf
CONF

    # Variant overrides to arm64
    cat > "${variant_config_file}" <<'CONF'
export BASE_BOARD=raspberrypiarm64
CONF

    run_build_preseed_flow "${config_file}" "" "${output_script}" "${variant_config_file}"

    local is_passed=false
    if [ -f "${output_script}" ] && grep -q 'BASE_ARCH="arm64"' "${output_script}"; then
        is_passed=true
        ((tests_passed++))
    fi

    echo "Generated board config:"
    [ -f "${output_script}" ] && cat "${output_script}" || echo "(file not created)"
    print_test_result "$test_name" "$is_passed" "Expected BASE_ARCH=\"arm64\" (variant should win over dist config)"
    $is_passed || failed_tests+=("$test_name")

    rm -rf "${tmpdir}"
}

# Run all tests
run_tests() {
    echo -e "${BLUE}Running config.local and Variant BASE_BOARD Tests${NC}"
    echo "═══════════════════════════════════════════════════"

    test_no_config_local_defaults_to_armhf
    test_config_local_sets_arm64
    test_config_local_overrides_config
    test_config_sets_board_no_local
    test_variant_sets_arm64
    test_config_local_overrides_variant
    test_variant_overrides_config

    # Print summary
    echo
    echo -e "${BLUE}Test Summary${NC}"
    echo "═══════════"
    echo "Total tests: $test_count"
    echo "Tests passed: $tests_passed"
    echo "Tests failed: $((test_count - tests_passed))"

    if ((${#failed_tests[@]} > 0)); then
        echo
        echo -e "${RED}Failed Tests:${NC}"
        printf '  %s\n' "${failed_tests[@]}"
        return 1
    fi
    return 0
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi
