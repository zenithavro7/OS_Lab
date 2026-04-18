#!/usr/bin/env bash
# main.sh - User Account & Permission Management System
# OS concept: process privilege (EUID), system calls via userland utilities

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/activity.log"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Root check: OS concept - only UID 0 may modify /etc/passwd, /etc/shadow
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (sudo)." >&2
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
        echo -e "${RED}[ERROR]${NC} Missing module: ${mod}.sh" >&2
        exit 1
    fi
done

log_action() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [admin=$(logname 2>/dev/null || echo root)] $msg" >> "$LOG_FILE"
}

pause() { read -rp "Press [Enter] to continue..."; }

print_menu() {
    clear
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} User Account & Permission Management System${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo " 1) Bulk Create Users (from CSV)"
    echo " 2) Delete User"
    echo " 3) List Users"
    echo " 4) Setup Roles / Workspaces"
    echo " 5) Assign Role to User"
    echo " 6) Show Workspace Permissions"
    echo " 7) Show Password Policy"
    echo " 8) Enforce Password Policy on User"
    echo " 9) Check Password Strength"
    echo "10) Login Report (last 20)"
    echo "11) Failed Login Attempts"
    echo "12) Active Users"
    echo "13) Flag Suspicious Logins"
    echo "14) Export Full Report"
    echo " 0) Exit"
    echo -e "${BLUE}============================================${NC}"
}

main_loop() {
    while true; do
        print_menu
        read -rp "Select option: " choice
        case "$choice" in
            1)
                read -rp "Path to CSV [${SCRIPT_DIR}/sample_users.csv]: " csv
                csv="${csv:-$SCRIPT_DIR/sample_users.csv}"
                bulk_create_users "$csv"
                log_action "Bulk create from $csv"
                pause ;;
            2)
                read -rp "Username to delete: " u
                delete_user "$u"
                log_action "Deleted user $u"
                pause ;;
            3) list_users; pause ;;
            4) setup_roles; log_action "Setup roles/workspaces"; pause ;;
            5)
                read -rp "Username: " u
                read -rp "Role (admin/developer/intern): " r
                assign_role "$u" "$r"
                log_action "Assigned $u -> $r"
                pause ;;
            6) show_permissions; pause ;;
            7) show_policy; pause ;;
            8)
                read -rp "Username: " u
                enforce_policy "$u"
                log_action "Enforced policy on $u"
                pause ;;
            9)
                read -rsp "Password: " p; echo
                check_password_strength "$p"
                pause ;;
            10) show_login_report; pause ;;
            11) show_failed_attempts; pause ;;
            12) show_active_users; pause ;;
            13)
                read -rp "Threshold [5]: " t
                flag_suspicious "${t:-5}"
                pause ;;
            14) export_report; log_action "Exported full report"; pause ;;
            0) echo -e "${GREEN}Goodbye.${NC}"; log_action "Exit"; exit 0 ;;
            *) echo -e "${RED}Invalid choice.${NC}"; pause ;;
        esac
    done
}

log_action "Session started"
main_loop
