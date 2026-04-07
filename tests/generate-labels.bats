#!/usr/bin/env bats

# Tests for scripts/generate-labels.sh

setup() {
    export BATS_TMPDIR="${BATS_TEST_TMPDIR}"
    # Create a mock kubernetes/apps directory structure
    mkdir -p "${BATS_TMPDIR}/kubernetes/apps/default/echo/app"
    mkdir -p "${BATS_TMPDIR}/kubernetes/apps/media/plex/app"
    mkdir -p "${BATS_TMPDIR}/kubernetes/apps/media/sonarr/app"
    mkdir -p "${BATS_TMPDIR}/.github"

    # Create a minimal generate-labels script that uses our mock dirs
    export MOCK_APPS_DIR="${BATS_TMPDIR}/kubernetes/apps"
    export MOCK_LABELS_FILE="${BATS_TMPDIR}/.github/labels.yaml"
    export MOCK_LABELER_FILE="${BATS_TMPDIR}/.github/labeler.yaml"
}

run_generate_labels() {
    # Source the script functions by overriding variables
    (
        cd "${BATS_TMPDIR}"
        # Override the variables used by the script
        ROOT_DIR="${BATS_TMPDIR}"
        APPS_DIR="${MOCK_APPS_DIR}"
        LABELS_FILE="${MOCK_LABELS_FILE}"
        LABELER_FILE="${MOCK_LABELER_FILE}"

        # Source just the functions from the script (skip the execution at the bottom)
        source <(sed -n '/^generate_labels/,/^}/p; /^generate_labeler/,/^}/p' \
            "${BATS_TEST_DIRNAME}/../scripts/generate-labels.sh" 2>/dev/null || true)

        # If sourcing failed, fall back to running with overrides
        if ! declare -f generate_labels &>/dev/null; then
            # Run the actual script with overridden paths
            APPS_DIR="${MOCK_APPS_DIR}" \
            LABELS_FILE="${MOCK_LABELS_FILE}" \
            LABELER_FILE="${MOCK_LABELER_FILE}" \
            ROOT_DIR="${BATS_TMPDIR}" \
                bash -c "
                    $(grep -v 'git rev-parse' "${BATS_TEST_DIRNAME}/../scripts/generate-labels.sh" | \
                      sed 's|APPS_DIR=.*|APPS_DIR=\"${APPS_DIR}\"|' | \
                      sed 's|LABELS_FILE=.*|LABELS_FILE=\"${LABELS_FILE}\"|' | \
                      sed 's|LABELER_FILE=.*|LABELER_FILE=\"${LABELER_FILE}\"|' | \
                      sed 's|ROOT_DIR=.*|ROOT_DIR=\"${ROOT_DIR}\"|')
                "
            return $?
        fi

        generate_labels > "$LABELS_FILE"
        generate_labeler > "$LABELER_FILE"
    )
}

@test "generate-labels creates labels.yaml" {
    run run_generate_labels
    [[ "$status" -eq 0 ]]
    [[ -f "${MOCK_LABELS_FILE}" ]]
}

@test "generate-labels creates labeler.yaml" {
    run run_generate_labels
    [[ "$status" -eq 0 ]]
    [[ -f "${MOCK_LABELER_FILE}" ]]
}

@test "labels.yaml contains namespace labels" {
    run_generate_labels
    grep -q "area/default" "${MOCK_LABELS_FILE}"
    grep -q "area/media" "${MOCK_LABELS_FILE}"
}

@test "labels.yaml contains app labels" {
    run_generate_labels
    grep -q "app/echo" "${MOCK_LABELS_FILE}"
    grep -q "app/plex" "${MOCK_LABELS_FILE}"
    grep -q "app/sonarr" "${MOCK_LABELS_FILE}"
}

@test "labels.yaml contains static labels" {
    run_generate_labels
    grep -q "type/bug" "${MOCK_LABELS_FILE}"
    grep -q "priority/critical" "${MOCK_LABELS_FILE}"
    grep -q "size/xs" "${MOCK_LABELS_FILE}"
    grep -q "area/bootstrap" "${MOCK_LABELS_FILE}"
}

@test "labeler.yaml contains namespace glob rules" {
    run_generate_labels
    grep -q "area/default" "${MOCK_LABELER_FILE}"
    grep -q "kubernetes/apps/default/" "${MOCK_LABELER_FILE}"
    grep -q "area/media" "${MOCK_LABELER_FILE}"
    grep -q "kubernetes/apps/media/" "${MOCK_LABELER_FILE}"
}

@test "labeler.yaml contains app glob rules" {
    run_generate_labels
    grep -q "app/echo" "${MOCK_LABELER_FILE}"
    grep -q "kubernetes/apps/default/echo/" "${MOCK_LABELER_FILE}"
}

@test "labeler.yaml contains static component rules" {
    run_generate_labels
    grep -q "component/cilium" "${MOCK_LABELER_FILE}"
    grep -q "component/flux" "${MOCK_LABELER_FILE}"
}

@test "labels.yaml is valid YAML" {
    run_generate_labels
    # Basic YAML validation - starts with ---
    head -1 "${MOCK_LABELS_FILE}" | grep -q "^---"
}
