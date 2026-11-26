# NAS

The NAS runs in a container on the [Proxmox node](../hosts/proxmox.md).

## Scripts

| Script                    | Runs on               | Purpose                                   |
| data-backup.sh            | NAS container         | Backs up NAS data                         |
| poweroff-backup-hdds.sh   | NAS container         | Powers off the backup drives              |            
| reconnect-nas.bat         | Windows laptop or PC  | Connects or reconnects mapped NAS drives  |
