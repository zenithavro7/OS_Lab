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
    echo -e "${GREEN}Last 20 logins:${NC}"
    if command -v last &>/dev/null; then
        last -n 20 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} last command returned no data."
    else
        echo -e "${RED}[ERROR]${NC} 'last' not available."
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
    echo -e "${GREEN}Currently logged in (who):${NC}"
    who
    echo
    echo -e "${GREEN}Session detail (w):${NC}"
    w
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
    {
        echo "================ REPORT $stamp ================"
        echo "--- last 20 logins ---"
        last -n 20 2>/dev/null
        echo "--- active users ---"
        who
        echo "--- failed attempts (tail 30) ---"
        local log
        if log=$(detect_auth_log); then
            grep -Ei "failed password|authentication failure" "$log" 2>/dev/null | tail -n 30
        else
            echo "no auth log available"
        fi
        echo "================ END ================"
    } >> "$REPORT_LOG"
    echo -e "${GREEN}[OK]${NC} Report appended to $REPORT_LOG"
}
