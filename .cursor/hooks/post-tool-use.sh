#!/bin/bash
# planning-with-files: Post-tool-use hook for Cursor
# Injects a reminder after file modifications using postToolUse's context field.

# Issue #195 opt-out. The disabled branch reproduces this hook's own
# no-plan-file behaviour, so the Cursor protocol shape never changes.
[ "${PLANNING_DISABLED:-}" = "1" ] && { echo '{}'; exit 0; }

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || { echo '{}'; exit 0; }
RESOLVER="${HOOK_DIR}/resolve-plan-dir.sh"

PLAN_FILE=""
if [ -f "$RESOLVER" ]; then
    PLAN_DIR="$(sh "$RESOLVER" 2>/dev/null)" || PLAN_DIR=""
    if [ -n "$PLAN_DIR" ]; then
        PLAN_FILE="${PLAN_DIR}/task_plan.md"
    elif [ -n "${PLAN_ID:-}" ]; then
        # Explicit PLAN_ID failed closed — no legacy fallback (#237 / #336).
        echo '{}'
        exit 0
    fi
fi
if [ -z "$PLAN_FILE" ]; then
    if [ -n "${PWF_PLAN_ROOT:-}" ] && [ -d "${PWF_PLAN_ROOT}" ]; then
        PLAN_FILE="${PWF_PLAN_ROOT}/task_plan.md"
    else
        PLAN_FILE="task_plan.md"
    fi
fi

if [ -f "$PLAN_FILE" ]; then
    echo '{"additional_context":"[planning-with-files] Update progress.md with what you just did. If a phase is now complete, update task_plan.md status."}'
else
    echo '{}'
fi
exit 0
