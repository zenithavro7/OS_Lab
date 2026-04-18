# User Account & Permission Management System

A Bash-based admin tool for Linux that provides bulk user creation,
role-based workspace access, password-policy enforcement, and login
monitoring. A small C utility (`passwd_checker`) demonstrates
integrating a compiled program with shell scripts.

> **College OS project.** Intended to run on a Linux VM (Ubuntu or
> CentOS). Do **not** run on your personal machine — it creates real
> users and modifies `/etc/passwd`, `/etc/shadow`, `/etc/group`.

---

## 1. Requirements

- Linux (Ubuntu 20.04+ or CentOS/RHEL 7+)
- `bash` >= 4 (associative arrays)
- `gcc` + `make` (for the C tool)
- Root privileges (`sudo`)
- Standard utilities: `useradd`, `userdel`, `usermod`, `chpasswd`,
  `chage`, `last`, `who`, `w`, `getent`, `stat`, `awk`

## 2. How to run

```bash
cd user-mgmt-system
chmod +x main.sh modules/*.sh
sudo ./main.sh
```

An interactive menu appears with 14 options covering users, roles,
password policy, and login monitoring. Every admin action is appended
to `logs/activity.log` with a timestamp.

## 3. Testing with sample_users.csv

`sample_users.csv` ships with five users (1 admin, 2 developers,
2 interns). From the main menu:

1. Select **4 — Setup Roles / Workspaces** (creates groups + `/var/workspace/*`).
2. Select **1 — Bulk Create Users** and accept the default CSV path.
3. Select **3 — List Users** to verify they were created with correct UIDs.
4. Select **6 — Show Workspace Permissions** to verify `chmod`/`chown`.
5. Select **8 — Enforce Password Policy** on any created user (e.g. `alice`).
6. Select **10 / 11 / 12** to check login reports and active sessions.
7. Select **14 — Export Full Report** and inspect `logs/activity.log`.

Cleanup:

```bash
sudo ./main.sh   # option 2 (Delete User) for each test user
```

## 4. Compile the C tool

```bash
cd tools
make
./passwd_checker 'Weakpw'          # prints WEAK: ...
./passwd_checker 'Str0ng@Pass'     # prints STRONG
echo -n 'Via@Stdin1' | ./passwd_checker
```

Exit code is `0` for STRONG, `1` for WEAK — useful for scripting.

## 5. OS concepts demonstrated

| Concept | Where it appears |
| --- | --- |
| **Process privilege / EUID** | `main.sh` checks `$EUID` before running — only UID 0 may modify `/etc/passwd` and `/etc/shadow`. |
| **User/Group namespace (UID/GID)** | `list_users` filters UID ≥ 1000 to separate regular from system users. `useradd` allocates the next free UID. |
| **Password store (`/etc/shadow`)** | `chpasswd` writes hashed passwords; `chage` edits aging fields (MAX_DAYS, MIN_DAYS, WARN_DAYS) stored there. |
| **Discretionary Access Control (DAC)** | `role_access.sh` applies `chown root:<role>` + `chmod 770/750` so only group members can enter a workspace. |
| **Supplementary groups** | `usermod -aG` assigns a user to a role without dropping existing groups. |
| **File mode bits in the inode** | `chmod` sets the 9 permission bits persisted in the inode — visible via `stat`. |
| **System accounting files** | `last` reads `wtmp`; `who`/`w` read `utmp`; both are binary kernel-maintained logs of sessions. |
| **PAM / auth logging** | Failed SSH/login attempts logged to `/var/log/auth.log` (Debian) or `/var/log/secure` (RHEL) by PAM modules. |
| **Inter-process via exec** | Bash scripts invoke external binaries (`useradd`, `chage`, the C `passwd_checker`) as child processes. |
| **Config sourcing** | `policy.conf` and `roles.conf` are sourced into the shell environment — simple configuration pattern. |
| **Portable log paths** | `detect_auth_log` handles distro differences between Debian/RHEL families. |

## 6. Project layout

```
user-mgmt-system/
├── main.sh
├── modules/
│   ├── user_management.sh
│   ├── role_access.sh
│   ├── password_policy.sh
│   └── login_monitor.sh
├── config/
│   ├── roles.conf
│   └── policy.conf
├── logs/
│   └── activity.log        # created at first run
├── sample_users.csv
├── tools/
│   ├── passwd_checker.c
│   └── Makefile
└── README.md
```

## 7. Notes

- All scripts use `set -u` or defensive checks; every external command's
  exit status is inspected and surfaced with color-coded messages
  (`green` success, `yellow` warn/skip, `red` error).
- Workspace path defaults (`/var/workspace/*`) are configurable via
  `config/roles.conf`.
- Password policy defaults are configurable via `config/policy.conf`
  and applied through `chage`.
