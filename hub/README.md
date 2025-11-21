# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Troubleshooting

### Kamal deploy fails with "no space left on device"

If `kamal deploy` fails with an error like:

```
ERROR: failed to copy files: copy file range failed: no space left on device
```

The remote server is out of disk space. Common cause: orphaned buildkit volumes from old IP addresses.

**Diagnose:**

```bash
# Check disk space
ssh jesse@<SERVER_IP> 'df -h /'

# Check Docker volume sizes
ssh jesse@<SERVER_IP> 'sudo bash -c "du -sh /var/lib/docker/volumes/*"'
```

**Fix:** Remove orphaned buildkit volumes (keep `hub_storage` and the current IP's buildkit volume):

```bash
# Find and remove old buildkit containers/volumes
ssh jesse@<SERVER_IP> 'docker ps -a'  # find old buildkit container IDs
ssh jesse@<SERVER_IP> 'docker rm -f <container_id>'
ssh jesse@<SERVER_IP> 'docker volume rm <old_buildkit_volume_name>'
```

**Why this happens:** When the VM's IP address changes (e.g., after a GCP restart), Kamal creates a new buildkit builder with a volume named after the new IP. The old volume remains orphaned. `kamal prune all` doesn't clean these up.

**Prevention:** Reserve a static IP in GCP Console → VPC Network → IP addresses to prevent IP changes on VM restart.
