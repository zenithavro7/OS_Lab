#!/usr/bin/env bash
# main.sh - User Account & Permission Management System
# OS concept: process privilege (EUID), system calls via userland utilities

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/activity.log"

# ─── Color palette (256-color + bold) ─────────────────────────────────────
RED=$'\033[38;5;203m'       # soft red
GREEN=$'\033[38;5;114m'     # mint
YELLOW=$'\033[38;5;221m'    # amber
BLUE=$'\033[38;5;111m'      # sky blue
CYAN=$'\033[38;5;87m'       # aqua
MAGENTA=$'\033[38;5;177m'   # lavender
GREY=$'\033[38;5;244m'      # muted grey
WHITE=$'\033[38;5;255m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Background accent for section headers
BG_ACCENT=$'\033[48;5;24m\033[38;5;231m'  # deep blue bg, white fg

# ─── Root check ───────────────────────────────────────────────────────────
# Only UID 0 may modify /etc/passwd, /etc/shadow
if [[ $EUID -ne 0 ]]; then
    printf '\n  %s✘ ACCESS DENIED%s  This tool must be run as %sroot%s.\n' \
        "$RED$BOLD" "$RESET" "$BOLD" "$RESET"
    printf '  %sTry:%s sudo ./main.sh\n\n' "$GREY" "$RESET"
    exit 1
fi

mkdir -p "$SCRIPT_DIR/logs"
touch "$LOG_FILE"

# Source modules
for mod in user_management role_access password_policy login_monitor; do
    if [[ -f "$SCRIPT_DIR/modules/${mod}.sh" ]]; then
        # shellcheck disable=SC1090
        source "$SCRIPT_DIR/modules/${mod}.sh"
    else
        printf '%s✘ Missing module:%s %s\n' "$RED" "$RESET" "${mod}.sh" >&2
        exit 1
    fi
done

log_action() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [admin=$(logname 2>/dev/null || echo root)] $msg" >> "$LOG_FILE"
}

# ─── UI helpers ───────────────────────────────────────────────────────────
term_width() { tput cols 2>/dev/null || echo 80; }

hr() {
    local w; w=$(term_width)
    local ch="${1:-─}"
    local color="${2:-$GREY}"
    printf '%s' "$color"
    printf -- "${ch}%.0s" $(seq 1 "$w")
    printf '%s\n' "$RESET"
}

center() {
    local text="$1"
    local w; w=$(term_width)
    local len=${#text}
    local pad=$(( (w - len) / 2 ))
    (( pad < 0 )) && pad=0
    printf "%*s%s\n" "$pad" "" "$text"
}

# Cached once per session; recomputed only after user add/delete so the
# banner doesn't hit /etc/passwd on every menu render.
USER_COUNT=""
refresh_user_count() {
    USER_COUNT=$(awk -F: '$3>=1000 && $3<65534' /etc/passwd 2>/dev/null | wc -l | tr -d ' ')
}
refresh_user_count

banner() {
    clear
    local host; host=$(hostname -s 2>/dev/null || echo localhost)
    local kernel; kernel=$(uname -sr 2>/dev/null || echo "Unknown")
    local users="$USER_COUNT"
    local now; now=$(date '+%Y-%m-%d %H:%M:%S')

    hr '━' "$BLUE"
    printf '%s' "$BOLD$CYAN"
    center "╭─╮  USER ACCOUNT & PERMISSION MANAGEMENT  ╭─╮"
    printf '%s' "$RESET"
    printf '%s' "$DIM$GREY"
    center "A Linux administration toolkit · v1.0"
    printf '%s' "$RESET"
    hr '━' "$BLUE"

    # Status bar
    printf ' %s●%s %shost%s %s%s%s   %s●%s %skernel%s %s%s%s   %s●%s %susers%s %s%s%s   %s●%s %stime%s %s%s%s\n' \
        "$GREEN" "$RESET" "$GREY" "$RESET" "$BOLD" "$host" "$RESET" \
        "$MAGENTA" "$RESET" "$GREY" "$RESET" "$BOLD" "$kernel" "$RESET" \
        "$YELLOW" "$RESET" "$GREY" "$RESET" "$BOLD" "$users" "$RESET" \
        "$CYAN" "$RESET" "$GREY" "$RESET" "$BOLD" "$now" "$RESET"
    hr '─' "$GREY"
}

section() {
    # $1 = section label
    printf '\n %s %s %s\n' "$BG_ACCENT$BOLD" "$1" "$RESET"
}

menu_item() {
    # $1 = key, $2 = icon, $3 = label, $4 = description
    printf '  %s[%s%2s%s]%s  %s %-30s %s%s%s\n' \
        "$GREY" "$BOLD$CYAN" "$1" "$RESET$GREY" "$RESET" \
        "$2" "$3" "$DIM$GREY" "$4" "$RESET"
}

ok()    { printf '\n  %s✔ %s%s\n' "$GREEN$BOLD" "$1" "$RESET"; }
fail()  { printf '\n  %s✘ %s%s\n' "$RED$BOLD"   "$1" "$RESET"; }
warn()  { printf '\n  %s! %s%s\n' "$YELLOW$BOLD" "$1" "$RESET"; }
info()  { printf '\n  %s› %s%s\n' "$BLUE$BOLD"  "$1" "$RESET"; }

prompt() {
    # $1 = label, $2 = default (optional)
    local label="$1" def="${2:-}"
    if [[ -n "$def" ]]; then
        printf '  %s?%s %s %s[%s]%s: ' "$CYAN$BOLD" "$RESET" "$label" "$DIM" "$def" "$RESET"
    else
        printf '  %s?%s %s: ' "$CYAN$BOLD" "$RESET" "$label"
    fi
}

prompt_secret() {
    printf '  %s?%s %s: ' "$CYAN$BOLD" "$RESET" "$1"
}

pause() {
    printf '\n  %s↵  Press [Enter] to return to menu…%s' "$DIM$GREY" "$RESET"
    read -r _
}

confirm() {
    # $1 = question
    local ans
    printf '  %s⚠%s %s %s[y/N]%s: ' "$YELLOW$BOLD" "$RESET" "$1" "$DIM" "$RESET"
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

action_header() {
    # $1 = title
    clear
    hr '━' "$CYAN"
    printf ' %s▸ %s%s\n' "$BOLD$CYAN" "$1" "$RESET"
    hr '━' "$CYAN"
    echo
}

# ─── Menu rendering ───────────────────────────────────────────────────────
print_menu() {
    banner

    section "👥  USER MANAGEMENT"
    menu_item " 1" "📥" "Bulk Create Users"       "import users from CSV (on demand)"
    menu_item " 2" "➕" "Add New User"            "interactive single-user create"
    menu_item " 3" "🗑 " "Delete User"             "remove user + home dir"
    menu_item " 4" "📋" "List Users"              "show all regular users"

    section "🔐  ROLES & ACCESS"
    menu_item " 5" "🏗 " "Setup Roles / Workspaces" "create groups + /var/workspace"
    menu_item " 6" "🎭" "Assign Role to User"     "add user to role group"
    menu_item " 7" "🔍" "Show Workspace Perms"    "inspect chmod/chown"

    section "🛡   PASSWORD POLICY"
    menu_item " 8" "📄" "Show Current Policy"     "view MIN_LEN / MAX_DAYS etc."
    menu_item " 9" "⚙ " "Enforce Policy on User"  "apply aging via chage"
    menu_item "10" "🔑" "Check Password Strength" "length / upper / digit / special"

    section "📡  LOGIN MONITORING"
    menu_item "11" "📜" "Login Report"            "last 20 logins (with fallbacks)"
    menu_item "12" "🚫" "Failed Attempts"         "grep auth log"
    menu_item "13" "👁 " "Active Users"            "who + w + all accounts"
    menu_item "14" "🚨" "Flag Suspicious"         "threshold-based alerts"
    menu_item "15" "💾" "Export Full Report"      "snapshot → terminal + log"

    section "⚡  SYSTEM"
    menu_item " 0" "🚪" "Exit"                    "log out and quit"

    hr '─' "$GREY"
}

# ─── Action wrappers (thin, so the loop stays readable) ───────────────────
do_bulk_create() {
    action_header "Bulk Create Users (CSV import)"
    info "CSV format: username,fullname,role,password"
    prompt "Path to CSV" "$SCRIPT_DIR/sample_users.csv"
    read -r csv
    csv="${csv:-$SCRIPT_DIR/sample_users.csv}"
    echo
    if bulk_create_users "$csv"; then
        ok "Bulk create finished."
    else
        fail "Bulk create reported errors — see output above."
    fi
    refresh_user_count
    log_action "Bulk create from $csv"
}

do_add_user() {
    action_header "Add New User (interactive)"
    prompt "Username"; read -r u
    [[ -z "$u" ]] && { warn "Empty username — cancelled."; return; }

    prompt "Full name" "$u"; read -r fn
    fn="${fn:-$u}"

    prompt "Role (admin / developer / intern)" "developer"; read -r r
    r="${r:-developer}"

    # Password VISIBLE while typing (per user request — note: shoulder-surfing risk)
    prompt "Password (visible)"; read -r p
    [[ -z "$p" ]] && { warn "Empty password — cancelled."; return; }

    echo
    info "Checking password strength…"
    check_password_strength "$p" || warn "Password is weak — creating anyway (not recommended)."

    echo
    if add_user "$u" "$fn" "$r" "$p"; then
        ok "User '$u' created as role '$r'."
        refresh_user_count
        log_action "Added user $u (role=$r)"
    else
        fail "Could not add user '$u'."
    fi
}

do_delete_user() {
    action_header "Delete User"
    prompt "Username to delete"
    read -r u
    [[ -z "$u" ]] && { warn "Empty username — cancelled."; return; }
    confirm "Permanently delete user '$u' and their home directory?" || { warn "Cancelled."; return; }
    echo
    if delete_user "$u"; then
        ok "User '$u' deleted."
        refresh_user_count
    else
        fail "Could not delete '$u'."
    fi
    log_action "Deleted user $u"
}

do_list_users() {
    action_header "Regular Users (UID ≥ 1000)"
    list_users
}

do_setup_roles() {
    action_header "Setup Roles & Workspaces"
    setup_roles
    ok "Roles and workspaces are ready."
    log_action "Setup roles/workspaces"
}

do_assign_role() {
    action_header "Assign Role to User"
    prompt "Username"; read -r u
    prompt "Role (admin / developer / intern)"; read -r r
    echo
    if assign_role "$u" "$r"; then
        ok "Assigned '$u' → role '$r'."
    else
        fail "Role assignment failed."
    fi
    log_action "Assigned $u -> $r"
}

do_show_perms()     { action_header "Workspace Permissions"; show_permissions; }
do_show_policy()    { action_header "Current Password Policy"; show_policy; }

do_enforce_policy() {
    action_header "Enforce Password Policy"
    prompt "Username"; read -r u
    echo
    if enforce_policy "$u"; then
        ok "Policy applied to '$u'."
    else
        fail "Could not enforce policy on '$u'."
    fi
    log_action "Enforced policy on $u"
}

do_check_strength() {
    action_header "Password Strength Checker"
    # Per user request: password is VISIBLE while typing so the admin
    # can see exactly what is being tested.
    prompt "Password (visible)"
    read -r p; echo
    check_password_strength "$p"
}

do_login_report()   { action_header "Last 20 Logins"; show_login_report; }
do_failed()         { action_header "Failed Login Attempts"; show_failed_attempts; }
do_active()         { action_header "Currently Active Users"; show_active_users; }

do_flag_suspicious() {
    action_header "Flag Suspicious Logins"
    prompt "Failed-attempt threshold" "5"
    read -r t
    echo
    flag_suspicious "${t:-5}"
}

do_export_report() {
    action_header "Export Full Report"
    export_report
    ok "Report appended to logs/activity.log"
    log_action "Exported full report"
}

do_exit() {
    echo
    hr '━' "$MAGENTA"
    center "${BOLD}${MAGENTA}Session ended — goodbye, admin 👋${RESET}"
    hr '━' "$MAGENTA"
    log_action "Exit"
    exit 0
}

# ─── Main loop ────────────────────────────────────────────────────────────
main_loop() {
    while true; do
        print_menu
        printf '\n  %s➜%s  Select an option: ' "$BOLD$GREEN" "$RESET"
        read -r choice
        case "$choice" in
            1)  do_bulk_create;       pause ;;
            2)  do_add_user;          pause ;;
            3)  do_delete_user;       pause ;;
            4)  do_list_users;        pause ;;
            5)  do_setup_roles;       pause ;;
            6)  do_assign_role;       pause ;;
            7)  do_show_perms;        pause ;;
            8)  do_show_policy;       pause ;;
            9)  do_enforce_policy;    pause ;;
            10) do_check_strength;    pause ;;
            11) do_login_report;      pause ;;
            12) do_failed;            pause ;;
            13) do_active;            pause ;;
            14) do_flag_suspicious;   pause ;;
            15) do_export_report;     pause ;;
            0)  do_exit ;;
            "") ;; # re-render on empty input
            *)  fail "Unknown option: '$choice' — pick a number from the menu."; pause ;;
        esac
    done
}

log_action "Session started"
main_loop
