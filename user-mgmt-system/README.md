# User Account & Permission Management System

A Bash-based admin tool for Linux that provides bulk user creation,
interactive single-user add, role-based workspace access, password-policy
enforcement, and login monitoring — all fronted by a colorful,
grouped-menu TUI. A small C utility (`passwd_checker`) demonstrates
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
- A terminal that supports 256-color ANSI and Unicode box-drawing + emojis
  (GNOME Terminal, Konsole, macOS Terminal, Windows Terminal — all fine)
- Standard utilities: `useradd`, `userdel`, `usermod`, `chpasswd`,
  `chage`, `last`, `lastlog`, `who`, `w`, `getent`, `stat`, `awk`, `tput`

## 2. How to run

```bash
cd user-mgmt-system
chmod +x main.sh modules/*.sh
sudo ./main.sh
```

An interactive, grouped menu appears with **15 options** covering user
management, roles, password policy, and login monitoring. Every admin
action is appended to `logs/activity.log` with a timestamp.

If you run it without `sudo`, the tool refuses to start with a red
`✘ ACCESS DENIED` banner — demonstrating the process-privilege (EUID)
check.

## 3. The interface

The TUI uses 256-color ANSI, Unicode box-drawing, and emoji icons. The
top of the screen is a **live status bar** showing hostname, kernel,
regular-user count, and the current timestamp:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              ╭─╮  USER ACCOUNT & PERMISSION MANAGEMENT  ╭─╮
                    A Linux administration toolkit · v1.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ● host ubuntu-vm   ● kernel Linux 6.8   ● users 5   ● time 2026-04-22 22:41
──────────────────────────────────────────────────────────────
```

The user count is **cached** and refreshed only after operations that
actually change users (Bulk Create, Add New User, Delete User), so the
banner doesn't re-scan `/etc/passwd` on every menu render.

### Menu layout

```
 👥  USER MANAGEMENT
  [ 1]  📥  Bulk Create Users              import users from CSV (on demand)
  [ 2]  ➕  Add New User                   interactive single-user create
  [ 3]  🗑  Delete User                    remove user + home dir (confirm)
  [ 4]  📋  List Users                     bordered table of all users

 🔐  ROLES & ACCESS
  [ 5]  🏗  Setup Roles / Workspaces       create groups + /var/workspace
  [ 6]  🎭  Assign Role to User            add user to role group
  [ 7]  🔍  Show Workspace Perms           bordered table of chmod/chown

 🛡   PASSWORD POLICY
  [ 8]  📄  Show Current Policy            view MIN_LEN / MAX_DAYS etc.
  [ 9]  ⚙   Enforce Policy on User         apply aging via chage
  [10]  🔑  Check Password Strength        length / upper / digit / special

 📡  LOGIN MONITORING
  [11]  📜  Login Report                   last 20 logins (with fallbacks)
  [12]  🚫  Failed Attempts                grep auth log
  [13]  👁  Active Users                   who + w + all login-capable accounts
  [14]  🚨  Flag Suspicious                threshold-based alerts
  [15]  💾  Export Full Report             snapshot → terminal + log

 ⚡  SYSTEM
  [ 0]  🚪  Exit                           log out and quit
```

### UX details

- **Destructive actions ask for confirmation** — e.g. *"Permanently delete user 'bob' and their home directory? [y/N]"*
- **Status banners**: `✔ success`, `✘ error`, `! warning`, `› info`
- **Defaults shown in brackets** on prompts: `? Path to CSV [./sample_users.csv]:`
- **Passwords are visible while typing** (intentional, so the admin sees what is being tested/set)
- **Empty input** at the menu just re-renders instead of throwing an error

## 4. Feature reference

| # | Option | What it does |
|---|--------|--------------|
| 1 | **Bulk Create Users** | Reads `sample_users.csv` (or any CSV you point to), skips users that already exist, creates role groups if missing, creates users with `useradd -m`, sets passwords via `chpasswd`. |
| 2 | **Add New User** *(new)* | Interactive flow: prompts for username, full name, role, and a **visible** password. Runs a strength check first and warns if weak. |
| 3 | **Delete User** | Confirms first, then `userdel -r` (removes entry + home dir). |
| 4 | **List Users** | Bordered table of all regular users (UID ≥ 1000) with their supplementary groups. |
| 5 | **Setup Roles / Workspaces** | Creates `admin` / `developer` / `intern` groups and `/var/workspace/<role>` directories with `chown root:<role>` + `chmod 770/770/750`. |
| 6 | **Assign Role to User** | `usermod -aG <role> <user>`. |
| 7 | **Show Workspace Perms** | Bordered table of each workspace's path, mode, and owner:group. |
| 8 | **Show Current Policy** | Bordered table of `MIN_LEN`, `MAX_DAYS`, `MIN_DAYS`, `WARN_DAYS` sourced from `config/policy.conf`. |
| 9 | **Enforce Policy on User** | `chage -M -m -W` applied, then `chage -l` prints the result. |
| 10 | **Check Password Strength** | Visible input; reports PASS or lists every failed rule (length, uppercase, digit, special). |
| 11 | **Login Report** | `last -n 20 -a` first; **falls back** to `lastlog` and auth-log greps for `Accepted password / publickey / session opened` if `wtmp` is empty. |
| 12 | **Failed Attempts** | `grep -Ei "failed password\|authentication failure"` from `/var/log/auth.log` (Debian) or `/var/log/secure` (RHEL). |
| 13 | **Active Users** | Three panels: `who`, `w`, and a bordered table of **every login-capable account** with `ONLINE/offline` status — so newly-added users appear here even before they log in. |
| 14 | **Flag Suspicious** | Aggregates failed logins by user+IP and alerts on any exceeding a configurable threshold. |
| 15 | **Export Full Report** | Builds a timestamped report of last-logins / active users / accounts / failed attempts, then both **appends to `logs/activity.log` and prints it to the terminal**. |
| 0 | **Exit** | Logs the session end and prints a goodbye banner. |

## 5. Testing with `sample_users.csv`

`sample_users.csv` ships with five users (1 admin, 2 developers,
2 interns). Recommended first-run test flow:

1. **5 — Setup Roles / Workspaces** → creates groups and `/var/workspace/*`.
2. **7 — Show Workspace Perms** → confirms `770` / `770` / `750`.
3. **1 — Bulk Create Users** → press Enter to accept the default CSV path.
4. **4 — List Users** → verifies alice, bob, carol, dave, eve appear with UID ≥ 1000.
5. **2 — Add New User** → add a sixth user interactively (password visible).
6. **13 — Active Users** → the new user appears in the "All accounts" table with status `offline`.
7. **9 — Enforce Policy on User** on `alice` → `chage -l alice` confirms MAX 90 / MIN 1 / WARN 7.
8. **10 — Check Password Strength** → try `weak` (fails with 3 reasons) and `Str0ng@Pass` (PASS).
9. **11 — Login Report** → should show data (falls back automatically on fresh VMs).
10. **15 — Export Full Report** → the report prints on screen **and** is appended to `logs/activity.log`.
11. **0 — Exit**.

Inspect the audit trail:
```bash
cat logs/activity.log
```

Cleanup after testing:
```bash
sudo ./main.sh        # option 3 (Delete User) for each test user
# or quickly:
for u in alice bob carol dave eve; do sudo userdel -r "$u"; done
sudo rm -rf /var/workspace
```

## 6. Compile the C tool

```bash
cd tools
make
./passwd_checker 'Weakpw'          # WEAK: no digit; no special;
./passwd_checker 'Str0ng@Pass'     # STRONG
echo -n 'Via@Stdin1' | ./passwd_checker
```

Exit code: `0` for STRONG, `1` for WEAK — useful for scripting and pipelines.

## 7. OS concepts demonstrated

| Concept | Where it appears |
| --- | --- |
| **Process privilege / EUID** | `main.sh` checks `$EUID` before running — only UID 0 may modify `/etc/passwd` and `/etc/shadow`. |
| **User/Group namespace (UID/GID)** | `list_users` filters UID ≥ 1000 to separate regular from system users. `useradd` allocates the next free UID. |
| **Password store (`/etc/shadow`)** | `chpasswd` writes hashed passwords; `chage` edits aging fields (MAX_DAYS, MIN_DAYS, WARN_DAYS) stored there. |
| **Discretionary Access Control (DAC)** | `role_access.sh` applies `chown root:<role>` + `chmod 770/750` so only group members can enter a workspace. |
| **Supplementary groups** | `usermod -aG` assigns a user to a role without dropping existing groups. |
| **File mode bits in the inode** | `chmod` sets the 9 permission bits persisted in the inode — visible via `stat`. |
| **System accounting files** | `last` reads `wtmp`; `who`/`w` read `utmp`; `lastlog` reads `/var/log/lastlog` — binary, kernel-maintained records of sessions. |
| **PAM / auth logging** | SSH/login attempts logged to `/var/log/auth.log` (Debian) or `/var/log/secure` (RHEL) by PAM modules. |
| **Inter-process via exec** | Bash scripts invoke external binaries (`useradd`, `chage`, the C `passwd_checker`) as child processes. |
| **Config sourcing** | `policy.conf` and `roles.conf` are sourced into the shell environment — simple configuration pattern. |
| **Portable log paths** | `detect_auth_log` abstracts the Debian/RHEL log-path difference; used by failed-login, suspicious-flagging, and export-report features. |
| **Idempotent operations** | `bulk_create_users` re-runs safely — existing users are skipped; groups are `getent`-checked before creation. |
| **Caching for efficiency** | The status bar caches `USER_COUNT` and only refreshes it after user-modifying operations, avoiding repeat `/etc/passwd` scans. |

## 8. Project layout

```
user-mgmt-system/
├── main.sh                     # controller: banner, menu, dispatch, audit log
├── modules/
│   ├── user_management.sh      # bulk_create_users, add_user, delete_user, list_users
│   ├── role_access.sh          # setup_roles, assign_role, show_permissions
│   ├── password_policy.sh      # show_policy, enforce_policy, check_password_strength
│   └── login_monitor.sh        # show_login_report, show_failed_attempts,
│                               #   show_active_users, flag_suspicious, export_report
├── config/
│   ├── roles.conf              # associative array: role -> workspace path
│   └── policy.conf              # MIN_LEN, MAX_DAYS, MIN_DAYS, WARN_DAYS
├── logs/
│   └── activity.log            # created at first run; append-only audit log
├── sample_users.csv            # 5 test users (1 admin, 2 devs, 2 interns)
├── tools/
│   ├── passwd_checker.c        # standalone C strength checker
│   └── Makefile                # `make` builds passwd_checker
├── REPORT.md                   # full project report (for submission)
└── README.md                   # this file
```

## 9. Configuration

### `config/policy.conf`
```ini
MIN_LEN=8
MAX_DAYS=90
MIN_DAYS=1
WARN_DAYS=7
```
Edit these values and re-run options 8/9/10 to see new rules applied.

### `config/roles.conf`
```bash
declare -A ROLE_DIRS=(
    [admin]="/var/workspace/admin"
    [developer]="/var/workspace/developer"
    [intern]="/var/workspace/intern"
)
```
Change the target paths here to relocate the workspaces.

## 10. Notes & design choices

- All scripts use `set -u` or defensive checks; every external command's
  exit status is inspected and surfaced with color-coded status banners
  (`✔` green, `!` yellow, `✘` red).
- The UI is plain Bash + ANSI — no `dialog` / `whiptail` / ncurses
  dependencies, so it works on any freshly-installed Linux.
- **Password input is intentionally visible** on the strength checker and
  Add-New-User flows. If you want hidden input instead, change `read -r`
  back to `read -rs` in `main.sh` (functions `do_check_strength` and
  `do_add_user`).
- `logs/activity.log` is append-only; consider pairing it with
  `logrotate` for long-running deployments.
- Cross-distro portability is handled by `detect_auth_log` in
  `modules/login_monitor.sh` (`/var/log/auth.log` vs `/var/log/secure`).

## 11. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `✘ ACCESS DENIED` on launch | Run with `sudo`. |
| `chmod: cannot access 'module/*.sh'` | You typed **`module/`** (singular). The folder is **`modules/`** (plural). |
| `Missing module: user_management.sh` | You're not in the project directory — `cd user-mgmt-system` first. |
| Emoji icons show as `?` or boxes | Terminal font lacks emoji support — still functional, just less pretty. Use a modern terminal or install an emoji font. |
| Login Report (option 11) shows nothing | Expected on fresh VMs with empty `wtmp` — the `lastlog` and auth-log fallbacks will kick in automatically. |
| `/var/log/auth.log` not found | You're on CentOS/RHEL — the tool auto-detects `/var/log/secure` instead; no action needed. |
| Status bar user count looks stale | It refreshes after Bulk Create / Add User / Delete User. If you change users outside the tool, exit and restart. |
