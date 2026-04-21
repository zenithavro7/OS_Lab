#!/usr/bin/env bash
# password_policy.sh
# OS concept: Password aging metadata lives in /etc/shadow; chage edits those fields.

: "${RED:=}" "${GREEN:=}" "${YELLOW:=}" "${NC:=}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaults (overridden by policy.conf)
MIN_LEN=8
MAX_DAYS=90
MIN_DAYS=1
WARN_DAYS=7

if [[ -f "$SCRIPT_DIR/config/policy.conf" ]]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/config/policy.conf"
fi

show_policy() {
    local BOLD=$'\033[1m' DIM=$'\033[2m' RST=$'\033[0m' CY=$'\033[38;5;87m' GN=$'\033[38;5;114m'
    printf '  %s┌───────────────────────────┬─────────────┐%s\n' "$DIM" "$RST"
    printf '  %s│%s %-25s %s│%s %-11s %s│%s\n' \
        "$DIM" "$BOLD$CY" "SETTING" "$RST$DIM" "$BOLD$CY" "VALUE" "$RST$DIM" "$RST"
    printf '  %s├───────────────────────────┼─────────────┤%s\n' "$DIM" "$RST"
    printf '  %s│%s %-25s %s│%s %s%-11s%s %s│%s\n' "$DIM" "$RST" "Minimum length"      "$DIM" "$RST" "$GN" "$MIN_LEN"   "$RST" "$DIM" "$RST"
    printf '  %s│%s %-25s %s│%s %s%-11s%s %s│%s\n' "$DIM" "$RST" "Maximum age (days)"  "$DIM" "$RST" "$GN" "$MAX_DAYS"  "$RST" "$DIM" "$RST"
    printf '  %s│%s %-25s %s│%s %s%-11s%s %s│%s\n' "$DIM" "$RST" "Minimum age (days)"  "$DIM" "$RST" "$GN" "$MIN_DAYS"  "$RST" "$DIM" "$RST"
    printf '  %s│%s %-25s %s│%s %s%-11s%s %s│%s\n' "$DIM" "$RST" "Warn before expiry"  "$DIM" "$RST" "$GN" "$WARN_DAYS" "$RST" "$DIM" "$RST"
    printf '  %s└───────────────────────────┴─────────────┘%s\n' "$DIM" "$RST"
}

enforce_policy() {
    local user="$1"
    if [[ -z "$user" ]]; then
        echo -e "${RED}[ERROR]${NC} Username required."
        return 1
    fi
    if ! id "$user" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} User $user does not exist."
        return 1
    fi

    # chage updates the aging fields of /etc/shadow
    if chage -M "$MAX_DAYS" -m "$MIN_DAYS" -W "$WARN_DAYS" "$user"; then
        echo -e "${GREEN}[OK]${NC} Password policy applied to $user"
        chage -l "$user"
    else
        echo -e "${RED}[ERROR]${NC} chage failed for $user"
        return 1
    fi
}

check_password_strength() {
    local pw="$1"
    local reasons=()

    if (( ${#pw} < MIN_LEN )); then
        reasons+=("length < $MIN_LEN")
    fi
    if ! [[ "$pw" =~ [A-Z] ]]; then
        reasons+=("missing uppercase letter")
    fi
    if ! [[ "$pw" =~ [0-9] ]]; then
        reasons+=("missing digit")
    fi
    if ! [[ "$pw" =~ [^A-Za-z0-9] ]]; then
        reasons+=("missing special character")
    fi

    if (( ${#reasons[@]} == 0 )); then
        echo -e "${GREEN}[PASS]${NC} Password is STRONG."
        return 0
    else
        echo -e "${RED}[FAIL]${NC} Password is WEAK:"
        for r in "${reasons[@]}"; do echo "  - $r"; done
        return 1
    fi
}
