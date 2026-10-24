#!/bin/bash
# planning-with-files: User prompt submit hook for Cursor
# Injects plan context on every user message.
# Critical for session recovery after /clear — dumps actual content, not just advice.

# Issue #195 opt-out. The disabled branch reproduces this hook's own
# no-plan-file behaviour, so the Cursor protocol shape never changes.
[ "${PLANNING_DISABLED:-}" = "1" ] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
RESOLVER="${HOOK_DIR}/resolve-plan-dir.sh"

# --- PWF_PLAN_ROOT: absolute plan-root binding (issue #212). ---
# A thread whose cwd is a shared PARENT of the real project can be pinned to
# the nested project root; every planning-state read below goes through the
# prefix, and the shared resolver honors the same variable. An explicit but
# broken pin fails CLOSED: one notice, nothing injected, never a silent fall
# back to the ambiguous cwd plan the caller was escaping. With the var unset
# the prefix is EMPTY so every path string stays byte-identical to the legacy
# shape. Wording matches scripts/inject-plan.sh.
PLAN_PREFIX=""
LEGACY_ROOT="$(pwd)"
if [ -n "${PWF_PLAN_ROOT:-}" ]; then
    case "${PWF_PLAN_ROOT}" in
        /*|[A-Za-z]:[\\/]*) ;;
        *)
            echo "[planning-with-files] PWF_PLAN_ROOT must be an absolute local path; nothing injected."
            exit 0
            ;;
    esac
    if [ -d "${PWF_PLAN_ROOT}" ]; then
        LEGACY_ROOT="${PWF_PLAN_ROOT}"
        PLAN_PREFIX="${PWF_PLAN_ROOT}/"
        export PWF_PLAN_ROOT
    else
        echo "[planning-with-files] PWF_PLAN_ROOT is not a directory: ${PWF_PLAN_ROOT} — nothing injected."
        exit 0
    fi
fi

# Resolve the selected named plan through the shared skill resolver (#336).
PLAN_DIR=""
PLAN_AMBIGUOUS=0
if [ -f "$RESOLVER" ]; then
    PLAN_DIR="$(sh "$RESOLVER" 2>/dev/null)" || PLAN_DIR=""
    if [ -z "$PLAN_DIR" ] && [ "$(sh "$RESOLVER" --check-ambiguity 2>/dev/null)" = "PWF_PLAN_AMBIGUOUS_V1" ]; then
        PLAN_AMBIGUOUS=1
    fi
fi

if [ -n "$PLAN_DIR" ]; then
    PLAN_FILE="${PLAN_DIR}/task_plan.md"
    PROGRESS_FILE="${PLAN_DIR}/progress.md"
elif [ -n "${PLAN_ID:-}" ]; then
    # Explicit PLAN_ID is a binding (issue #237): fail closed, no legacy fallback.
    echo "[planning-with-files] PLAN_ID does not name a plan directory under .planning: ${PLAN_ID} — nothing injected. Fix or unset the pin; a broken pin fails closed rather than selecting another plan."
    exit 0
elif [ "$PLAN_AMBIGUOUS" = "1" ]; then
    echo "[planning-with-files] Multiple plans are available. Set PLAN_ID=<slug> for this session; nothing injected."
    exit 0
else
    PLAN_FILE="${PLAN_PREFIX}task_plan.md"
    PROGRESS_FILE="${PLAN_PREFIX}progress.md"
fi

if [ ! -f "$PLAN_FILE" ]; then
    exit 0
fi

# --- Nested-root conflict detection (issue #212): fail CLOSED on ambiguity.
# A shared pointer or newest-plan / legacy-root fallback is still a cwd GUESS
# unless an explicit PWF_PLAN_ROOT or PLAN_ID selected it. If a direct child
# carries its own competing .planning, inject NOTHING and say why.
if [ -z "${PWF_PLAN_ROOT:-}" ] && [ -z "${PLAN_ID:-}" ]; then
    NESTED_LIST=""
    NESTED_N=0
    for nd in */.planning; do
        [ -d "$nd" ] || continue
        COMPETING=0
        [ -f "${nd}/.active_plan" ] && COMPETING=1
        if [ "$COMPETING" = "0" ]; then
            for np in "${nd}"/*/task_plan.md; do
                [ -f "$np" ] && { COMPETING=1; break; }
            done
        fi
        [ "$COMPETING" = "1" ] || continue
        NR="${nd%/.planning}"
        NESTED_N=$((NESTED_N + 1))
        if [ "$NESTED_N" -le 3 ]; then
            if [ -z "$NESTED_LIST" ]; then NESTED_LIST="$NR"; else NESTED_LIST="${NESTED_LIST}, ${NR}"; fi
        fi
    done
    if [ "$NESTED_N" -gt 0 ]; then
        echo "[planning-with-files] Ambiguous plan: this cwd has an active plan and a nested project below it has its own (${NESTED_LIST}). Nothing injected. Pin the thread with PWF_PLAN_ROOT=<absolute path> or PLAN_ID=<slug>."
        exit 0
    fi
fi

echo "[planning-with-files] ACTIVE PLAN — current state:"
head -50 "$PLAN_FILE"
echo ""
echo "=== recent progress ==="
# Timestamp normalization matches scripts/inject-plan.sh (KV-cache stability, v2.40).
tail -20 "$PROGRESS_FILE" 2>/dev/null | sed -E 's/T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z/T00:00:00Z/g; s/T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2})/T00:00:00\2/g'
echo ""
echo "[planning-with-files] Read findings.md for research context. Continue from the current phase."
exit 0
