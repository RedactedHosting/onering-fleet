### Created by [Redacted Hosting](https://www.redactedhosting.com/reading-room/)

# OneRing Fleet

One script to rule them all.

OneRing Fleet helps system administrators generate per-host SSH helper scripts and run fleet-wide maintenance or diagnostic commands quickly.

It is designed for environments where SSH hardening is already in place (key-based auth, non-root access, firewall controls), and you want a faster operational workflow for repetitive tasks.

OneRing Fleet has been used with Linux servers managed from a Linux admin workstation / dev desktop.

Important: backend environment setup is the responsibility of the system administrator (or end user). That includes items such as SSH hardening, port forwarding, firewall rules, VPN/Zero Trust access, and the host update script (for example `/root/u.sh`).

## What OneRing Fleet Does

- Generates standardized per-host helper scripts (for example `123_web_ssh.sh`)
- Supports interactive SSH login, `--update`, and ad hoc command execution
- Runs fleet-wide commands across generated helpers with logging
- Provides quick operational checks (disk, memory, CPU summary, uptime)

## Components of the Ring

- `generate_ssh_script.sh`  
  Interactive generator that prompts for host/IP, VM ID, SSH username, and script name. It outputs an executable `*_ssh.sh` helper script.

- `fleet_runner.sh`  
  Batch runner that discovers generated host helpers (for example `123_web_ssh.sh`) and executes either `--update` or diagnostic/custom commands.

- `logs/` (created automatically)  
  Timestamped run logs for auditing and troubleshooting.

## Quick Start

1. Generate host helper scripts:

```bash
./generate_ssh_script.sh
```

2. Run updates across the fleet:

```bash
./fleet_runner.sh
```

3. Run diagnostics:

```bash
./fleet_runner.sh -d              # disk usage (df -h)
./fleet_runner.sh -m              # memory snapshot (free -h)
./fleet_runner.sh -c              # CPU summary (top -bn1 | head -n5)
./fleet_runner.sh -u              # uptime
./fleet_runner.sh -k "uname -a"   # custom command
./fleet_runner.sh -k "uptime" -s  # stop on first failure
```

## Example Session (Linux Dev Desk -> Linux Servers)

Generate two host helpers:

```bash
$ ./generate_ssh_script.sh
Enter target host/IP: 192.168.1.10
Enter VM ID (1-1000): 101
Enter SSH username: opsadmin
Enter script name (e.g., web_ssh.sh): web
[INFO] Generated ./101_web_ssh.sh

$ ./generate_ssh_script.sh
Enter target host/IP: 192.168.1.11
Enter VM ID (1-1000): 102
Enter SSH username [opsadmin]:
Enter script name (e.g., web_ssh.sh): db
[INFO] Generated ./102_db_ssh.sh
```

Run a fleet check and an update:

```bash
$ ./fleet_runner.sh -u
[INFO] Running ./101_web_ssh.sh uptime
 10:05:12 up 12 days,  2:45,  1 user,  load average: 0.09, 0.05, 0.01
[OK] ./101_web_ssh.sh succeeded.
---
[INFO] Running ./102_db_ssh.sh uptime
 10:05:13 up 4 days,  8:17,  1 user,  load average: 0.22, 0.14, 0.06
[OK] ./102_db_ssh.sh succeeded.

$ ./fleet_runner.sh
[INFO] Running ./101_web_ssh.sh --update
[OK] /root/u.sh completed on 192.168.1.10
...
```

## Prerequisites (Recommended)

- Harden SSH on target hosts (key-based auth, disable root login, restrict inbound access)
- Use a dedicated admin workstation / dev desk
- Restrict `sudoers` to the minimum commands required
- Centralize logs if using this in production

## Security Notes / Limitations

- OneRing Fleet is an operations convenience tool. It is not a complete security control or zero-trust implementation.
- The generated `--update` path calls `sudo -n /root/u.sh`; review and restrict this for your environment.
- Port forwarding, firewall policy, VPN/Zero Trust controls, and remote update script design are intentionally left to the system administrator operating the environment.
- The generator stores the last used SSH username in `.last_ssh_user` for convenience.
- Generated helper scripts and fleet logs may contain internal hostnames, usernames, and IPs.
- A `.gitignore` is included to help prevent accidentally committing generated scripts, logs, and cache files.
- Prefer passphrase-protected keys and modern key types (for example `ed25519`).
- Consider short-lived SSH certificates (OpenSSH CA, Vault, Teleport, etc.) as a future upgrade.

## `sudoers` (Least Privilege) for `--update`

The generated `--update` mode runs:

```bash
sudo -n /root/u.sh
```

Do not grant broad passwordless sudo for all commands. Instead, allow only the update script for the SSH user.

Example `/etc/sudoers.d/ops-update` entry (edit with `visudo -f /etc/sudoers.d/ops-update`):

```sudoers
# Allow opsadmin to run only the approved update script without a password
opsadmin ALL=(root) NOPASSWD: /root/u.sh
```

Recommended hardening for `/root/u.sh`:

- Owned by `root:root`
- Not writable by non-root users (`chmod 700 /root/u.sh`)
- Uses absolute paths for commands where practical (for example `/usr/bin/apt`, `/usr/bin/systemctl`)
- Returns `exit 0` only on success, non-zero on failure
- Writes to a root-owned log file if you need audit detail

If you need multiple allowed maintenance scripts, list each script explicitly in `sudoers` rather than granting `ALL`.

## Customization Ideas

- Add more `fleet_runner.sh` flags for common checks
- Add host grouping (prod/stage/dev) via prefixes or a manifest file
- Replace `--update` with a configurable command for your environment
- Integrate with short-lived credentials or an access broker

## Naming / Theme

- Project name: `OneRing Fleet`
- Tagline: `One script to rule them all.`
- Theme note: this is LOTR-inspired branding only and has no affiliation with Tolkien/Middle-earth rights holders.

## License

MIT (see `LICENSE`).
