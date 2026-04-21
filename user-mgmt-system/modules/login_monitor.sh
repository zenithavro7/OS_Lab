#!/usr/bin/env bash
# login_monitor.sh
# OS concept: kernel/PAM/sshd write auth events to system log files
# (utmp/wtmp/btmp for last/who/w; /var/log/auth.log or /var/log/secure for PAM).

: "${RED:=}" "${GREEN:=}" "${YELLOW:=}" "${NC:=}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_LOG="$SCRIPT_DIR/logs/activity.log"

# Portable auth log: Ubuntu uses /var/log/auth.log; RHEL/CentOS uses /var/log/secure
detect_auth_log() {
    for f in /var/log/auth.log /var/log/secure; do
        [[ -r "$f" ]] && { echo "$f"; return 0; }
    done
    return 1
}

show_login_report() {
    echo -e "${GREEN}Last 20 logins (from /var/log/wtmp):${NC}"
    local out=""
    if command -v last &>/dev/null; then
        out=$(last -n 20 -a 2>/dev/null | sed '/^$/d;/^wtmp/d')
    fi

    if [[ -n "$out" ]]; then
        echo "$out"
    else
        echo -e "${YELLOW}[INFO]${NC} 'last' returned no data — /var/log/wtmp may be empty or unreadable."
        echo
        echo -e "${GREEN}Fallback: per-user last login (lastlog):${NC}"
        if command -v lastlog &>/dev/null; then
            # lastlog reads /var/log/lastlog — per-user record of last login
            lastlog 2>/dev/null | awk 'NR==1 || $2!="**Never"'
        else
            echo -e "${YELLOW}[INFO]${NC} 'lastlog' not available."
        fi

        echo
        echo -e "${GREEN}Fallback: successful logins from auth log:${NC}"
        local log
        if log=$(detect_auth_log); then
            grep -Ei "Accepted (password|publickey)|session opened" "$log" 2>/dev/null | tail -n 20 \
                || echo -e "${YELLOW}[INFO]${NC} no successful logins found in $log"
        else
            echo -e "${YELLOW}[INFO]${NC} No auth log readable."
        fi
    fi
}

show_failed_attempts() {
    local log
    if ! log=$(detect_auth_log); then
        echo -e "${RED}[ERROR]${NC} No auth log readable (/var/log/auth.log or /var/log/secure)."
        return 1
    fi
    echo -e "${GREEN}Failed login attempts (from $log):${NC}"
    grep -Ei "failed password|authentication failure" "$log" 2>/dev/null | tail -n 30 \
        || echo -e "${YELLOW}[INFO]${NC} No failures found."
}

show_active_users() {
    local BOLD=$'\033[1m' DIM=$'\033[2m' RST=$'\033[0m' CY=$'\033[38;5;87m' GN=$'\033[38;5;114m'

    echo -e "${GREEN}Currently logged-in sessions (who):${NC}"
    if who | grep -q .; then
        who
    else
        echo -e "${YELLOW}[INFO]${NC} No interactive sessions right now."
    fi

    echo
    echo -e "${GREEN}Session detail (w):${NC}"
    w 2>/dev/null || echo -e "${YELLOW}[INFO]${NC} 'w' unavailable."

    # Also list every login-capable account on the system so newly-added
    # users are visible even before they have logged in.
    echo
    echo -e "${GREEN}All accounts on this system (login-capable):${NC}"
    printf '  %s┌──────────────────────┬────────┬──────────────────────┬──────────────┐%s\n' "$DIM" "$RST"
    printf '  %s│%s %-20s %s│%s %-6s %s│%s %-20s %s│%s %-12s %s│%s\n' \
        "$DIM" "$BOLD$CY" "USERNAME" "$RST$DIM" "$BOLD$CY" "UID" \
        "$RST$DIM" "$BOLD$CY" "SHELL" "$RST$DIM" "$BOLD$CY" "STATUS" "$RST$DIM" "$RST"
    printf '  %s├──────────────────────┼────────┼──────────────────────┼──────────────┤%s\n' "$DIM" "$RST"
    while IFS=: read -r uname _ uid _ _ _ shell; do
        if (( uid >= 1000 && uid < 65534 )); then
            local status="offline"
            if who | awk '{print $1}' | grep -qx "$uname"; then
                status="${GN}ONLINE${RST}"
            fi
            printf '  %s│%s %-20s %s│%s %-6s %s│%s %-20s %s│%s %-20b %s│%s\n' \
                "$DIM" "$RST" "$uname" "$DIM" "$RST" "$uid" \
                "$DIM" "$RST" "$shell" "$DIM" "$RST" "$status" "$DIM" "$RST"
        fi
    done < /etc/passwd
    printf '  %s└──────────────────────┴────────┴──────────────────────┴──────────────┘%s\n' "$DIM" "$RST"
}

flag_suspicious() {
    local threshold="${1:-5}"
    local log
    if ! log=$(detect_auth_log); then
        echo -e "${RED}[ERROR]${NC} No auth log readable."
        return 1
    fi
    echo -e "${GREEN}Checking for users/IPs with > $threshold failed attempts:${NC}"

    # Extract attacker IPs and usernames from "Failed password for [invalid user] X from IP"
    local tmp
    tmp=$(mktemp)
    grep -Ei "failed password" "$log" 2>/dev/null | \
        awk '{
            for (i=1;i<=NF;i++) {
                if ($i=="from") ip=$(i+1);
                if ($i=="for") user=($(i+1)=="invalid" ? $(i+3) : $(i+1));
            }
            print user" "ip
        }' | sort | uniq -c | sort -rn > "$tmp"

    local flagged=0
    while read -r count user ip; do
        [[ -z "$count" ]] && continue
        if (( count > threshold )); then
            echo -e "${RED}[ALERT]${NC} user=$user ip=$ip attempts=$count"
            flagged=$((flagged+1))
        fi
    done < "$tmp"
    rm -f "$tmp"

    if (( flagged == 0 )); then
        echo -e "${GREEN}No suspicious activity above threshold.${NC}"
    fi
}

export_report() {
    local stamp
    stamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Build the report block once, then both append AND print it.
    local block
    block=$({
        echo "================ REPORT $stamp ================"
        echo "--- last 20 logins ---"
        last -n 20 2>/dev/null || echo "(no wtmp data)"
        echo
        echo "--- active users (who) ---"
        who 2>/dev/null || echo "(none)"
        echo
        echo "--- regular accounts on system ---"
        awk -F: '$3>=1000 && $3<65534 {printf "  %-20s uid=%s shell=%s\n",$1,$3,$7}' /etc/passwd
        echo
        echo "--- failed attempts (tail 30) ---"
        local log
        if log=$(detect_auth_log); then
            grep -Ei "failed password|authentication failure" "$log" 2>/dev/null | tail -n 30 \
                || echo "(no failures logged)"
        else
            echo "(no auth log available on this distro)"
        fi
        echo "================ END ================"
    })

    # Append to persistent audit log
    printf '%s\n' "$block" >> "$REPORT_LOG"

    # Also show it on the terminal so the admin sees what was saved
    printf '%s\n' "$block"
    echo
    echo -e "${GREEN}[OK]${NC} Report appended to $REPORT_LOG"
}
