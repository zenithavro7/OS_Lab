#!/usr/bin/env bash
# user_management.sh
# OS concept: /etc/passwd, /etc/shadow, /etc/group, UID namespace

: "${RED:=}" "${GREEN:=}" "${YELLOW:=}" "${NC:=}"

bulk_create_users() {
    local csv="$1"
    if [[ ! -f "$csv" ]]; then
        echo -e "${RED}[ERROR]${NC} CSV not found: $csv"
        return 1
    fi

    local line_no=0
    while IFS=',' read -r username fullname role password || [[ -n "$username" ]]; do
        line_no=$((line_no+1))
        # Skip header/empty/comments
        [[ -z "$username" || "$username" =~ ^# ]] && continue
        [[ "$username" == "username" ]] && continue

        # Trim whitespace
        username="$(echo "$username" | xargs)"
        fullname="$(echo "$fullname" | xargs)"
        role="$(echo "$role" | xargs)"
        password="$(echo "$password" | xargs)"

        if id "$username" &>/dev/null; then
            echo -e "${YELLOW}[SKIP]${NC} User $username already exists."
            continue
        fi

        # Ensure role group exists
        if ! getent group "$role" &>/dev/null; then
            groupadd "$role" && echo -e "${GREEN}[OK]${NC} Created group $role"
        fi

        # useradd: writes to /etc/passwd and creates home via -m (skeleton from /etc/skel)
        if useradd -m -c "$fullname" -g "$role" -s /bin/bash "$username"; then
            echo -e "${GREEN}[OK]${NC} Created user $username"
        else
            echo -e "${RED}[ERROR]${NC} Failed creating $username"
            continue
        fi

        # chpasswd: updates hashed password in /etc/shadow
        if echo "${username}:${password}" | chpasswd; then
            echo -e "${GREEN}[OK]${NC} Password set for $username"
        else
            echo -e "${RED}[ERROR]${NC} chpasswd failed for $username"
        fi
    done < "$csv"

    echo -e "${GREEN}Processed $line_no lines.${NC}"
}

delete_user() {
    local username="$1"
    if [[ -z "$username" ]]; then
        echo -e "${RED}[ERROR]${NC} Username required."
        return 1
    fi
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} User $username does not exist."
        return 1
    fi

    # userdel -r: removes entry from /etc/passwd AND home directory (inode cleanup)
    if userdel -r "$username" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Deleted $username and home directory."
    else
        echo -e "${YELLOW}[WARN]${NC} userdel -r reported issues; user entry removed."
    fi
}

list_users() {
    # OS concept: UID >= 1000 is conventionally a regular (non-system) user on Linux
    local BOLD=$'\033[1m' DIM=$'\033[2m' RST=$'\033[0m' CY=$'\033[38;5;87m'
    printf '  %s┌──────────────────────┬────────┬──────────────────────────────┐%s\n' "$DIM" "$RST"
    printf '  %s│%s %-20s %s│%s %-6s %s│%s %-28s %s│%s\n' \
        "$DIM" "$BOLD$CY" "USERNAME" "$RST$DIM" "$BOLD$CY" "UID" \
        "$RST$DIM" "$BOLD$CY" "GROUPS" "$RST$DIM" "$RST"
    printf '  %s├──────────────────────┼────────┼──────────────────────────────┤%s\n' "$DIM" "$RST"
    local count=0
    while IFS=: read -r uname _ uid _ _ _ _; do
        if (( uid >= 1000 && uid < 65534 )); then
            local groups
            groups=$(id -nG "$uname" 2>/dev/null | tr ' ' ',')
            printf '  %s│%s %-20s %s│%s %-6s %s│%s %-28.28s %s│%s\n' \
                "$DIM" "$RST" "$uname" "$DIM" "$RST" "$uid" "$DIM" "$RST" "$groups" "$DIM" "$RST"
            count=$((count+1))
        fi
    done < /etc/passwd
    printf '  %s└──────────────────────┴────────┴──────────────────────────────┘%s\n' "$DIM" "$RST"
    printf '  %s%d user(s) found.%s\n' "$DIM" "$count" "$RST"
}
