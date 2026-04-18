#!/usr/bin/env bash
# role_access.sh
# OS concept: Discretionary Access Control (DAC) — user/group/other rwx bits;
# group membership controls workspace access.

: "${RED:=}" "${GREEN:=}" "${YELLOW:=}" "${NC:=}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source role -> directory mapping
if [[ -f "$SCRIPT_DIR/config/roles.conf" ]]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/config/roles.conf"
fi

VALID_ROLES=(admin developer intern)

setup_roles() {
    declare -A PERMS=( [admin]=770 [developer]=770 [intern]=750 )

    for role in "${VALID_ROLES[@]}"; do
        # Create group if missing: groupadd updates /etc/group
        if ! getent group "$role" &>/dev/null; then
            groupadd "$role" && echo -e "${GREEN}[OK]${NC} Group $role created"
        else
            echo -e "${YELLOW}[SKIP]${NC} Group $role exists"
        fi

        local dir="${ROLE_DIRS[$role]:-/var/workspace/$role}"
        mkdir -p "$dir"

        # chown root:<role> — group ownership governs access through DAC
        chown root:"$role" "$dir"
        # chmod sets the file mode bits (stored in inode)
        chmod "${PERMS[$role]}" "$dir"

        echo -e "${GREEN}[OK]${NC} $dir -> mode ${PERMS[$role]} owner root:$role"
    done
}

assign_role() {
    local user="$1" role="$2"
    if [[ -z "$user" || -z "$role" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: assign_role <user> <role>"
        return 1
    fi
    if ! id "$user" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} User $user does not exist."
        return 1
    fi
    local valid=0
    for r in "${VALID_ROLES[@]}"; do [[ "$r" == "$role" ]] && valid=1; done
    if (( ! valid )); then
        echo -e "${RED}[ERROR]${NC} Invalid role. Use: ${VALID_ROLES[*]}"
        return 1
    fi

    # usermod -aG: append to supplementary groups (does not drop existing groups)
    if usermod -aG "$role" "$user"; then
        echo -e "${GREEN}[OK]${NC} $user added to $role"
    else
        echo -e "${RED}[ERROR]${NC} Failed to assign role."
        return 1
    fi
}

show_permissions() {
    echo -e "${GREEN}Workspace permissions:${NC}"
    printf "%-30s %-10s %-20s\n" "PATH" "MODE" "OWNER:GROUP"
    echo "-----------------------------------------------------------------"
    for role in "${VALID_ROLES[@]}"; do
        local dir="${ROLE_DIRS[$role]:-/var/workspace/$role}"
        if [[ -d "$dir" ]]; then
            local mode owner
            mode=$(stat -c '%a' "$dir" 2>/dev/null || stat -f '%Lp' "$dir")
            owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || stat -f '%Su:%Sg' "$dir")
            printf "%-30s %-10s %-20s\n" "$dir" "$mode" "$owner"
        else
            printf "%-30s %-10s %-20s\n" "$dir" "MISSING" "-"
        fi
    done
}
