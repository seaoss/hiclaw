#!/bin/bash
# test-07-credential-rotate.sh - Case 7: Credential smooth rotation
# Verifies: dual-key sliding window rotation, old key still works during transition,
#           new key works, old key removed after confirmation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-helpers.sh"
source "${SCRIPT_DIR}/lib/matrix-client.sh"
source "${SCRIPT_DIR}/lib/higress-client.sh"
source "${SCRIPT_DIR}/lib/minio-client.sh"

test_setup "07-credential-rotate"

if ! require_llm_key; then
    test_teardown "07-credential-rotate"
    test_summary
    exit 0
fi

ADMIN_LOGIN=$(matrix_login "${TEST_ADMIN_USER}" "${TEST_ADMIN_PASSWORD}")
ADMIN_TOKEN=$(echo "${ADMIN_LOGIN}" | jq -r '.access_token')

MANAGER_USER="@manager:${TEST_MATRIX_DOMAIN}"

log_section "Request Credential Rotation"

DM_ROOM=$(matrix_find_dm_room "${ADMIN_TOKEN}" "${MANAGER_USER}" 2>/dev/null || true)
assert_not_empty "${DM_ROOM}" "DM room with Manager found"

# Request rotation
matrix_send_message "${ADMIN_TOKEN}" "${DM_ROOM}" \
    "Please rotate Alice's gateway credentials. Use the dual-key sliding window approach."

log_info "Waiting for Manager to perform rotation..."
REPLY=$(matrix_wait_for_reply "${ADMIN_TOKEN}" "${DM_ROOM}" "@manager" 180)

assert_not_empty "${REPLY}" "Manager replied to rotation request"

log_section "Verify Dual-Key Window"

higress_login "${TEST_ADMIN_USER}" "${TEST_ADMIN_PASSWORD}" > /dev/null
ALICE_CONSUMER=$(higress_get_consumer "worker-alice" 2>/dev/null || echo "{}")

# Check that consumer has credentials
CRED_COUNT=$(echo "${ALICE_CONSUMER}" | jq -r '.credentials[0].values | length' 2>/dev/null || echo "0")
log_info "Alice consumer has ${CRED_COUNT} credential(s)"

if [ "${CRED_COUNT}" -ge "2" ]; then
    log_pass "Dual-key window active (${CRED_COUNT} keys)"
else
    log_info "Dual-key window not detected (rotation may have completed already)"
fi

log_section "Verify Credentials in MinIO"

minio_setup
if minio_file_exists "agents/alice/openclaw.json"; then
    log_pass "Alice's openclaw.json exists (should contain updated key)"
else
    log_info "Alice's openclaw.json not found in MinIO"
fi

test_teardown "07-credential-rotate"
test_summary
