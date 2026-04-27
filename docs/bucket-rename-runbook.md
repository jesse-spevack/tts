# GCS Bucket Rename Runbook

How to rename the GCS bucket backing PodRead.app from one name to another with zero subscriber-visible regression. Captured from the `verynormal-tts-podcast` → `podread` migration (epic agent-team-a6u, executed 2026-04-19 → 2026-04-27).

This is a runbook, not a one-time write-up — if you ever need to rename the bucket again (or audit how the current one is wired), start here.

## When to use this

You're renaming the GCS bucket that stores podcast feed.xml files and episode MP3s. New bucket name = `<NEW>`, old bucket name = `<OLD>`. Both buckets stay live; old one becomes a permanent read-only archive (cost: pennies/year).

**Do NOT use this for**: deleting the old bucket entirely (we never do that — podcast apps have unpredictable re-poll cadences and may break for paused-subscriber backlogs), or for migrating between projects/regions (this runbook assumes same project + same region).

## Architecture you must know before touching anything

These are the facts that, if you forget them, will silently break production.

### 1. Production bucket name comes from GCP Secret Manager, NOT `.kamal/secrets`

The GitHub Actions Deploy workflow (`.github/workflows/deploy.yml`) fetches every secret from GCP Secret Manager and **overwrites** `.kamal/secrets` in CI before running `bin/kamal deploy`. The repo's `.kamal/secrets` value of `GOOGLE_CLOUD_BUCKET` is ignored at deploy time.

To actually change the production bucket env var, update Secret Manager:

```bash
printf '<NEW>' | gcloud secrets versions add google-cloud-bucket --data-file=-
```

Then trigger a redeploy. Editing `.kamal/secrets` in a PR is still required (it's the source of truth for local dev + the deploy.yml secrets list), but on its own does nothing in production.

### 2. The cached feed.xml is the cutover blast radius, not the MP3 files

`feeds_controller#show` does this:

```ruby
feed_content = CloudStorage.new(podcast_id:).download_file(remote_path: "feed.xml")
```

`CloudStorage` reads from `gs://{AppConfig::Storage::BUCKET}/podcasts/{id}/feed.xml`. After the env flip, `BUCKET == <NEW>`. If `<NEW>` doesn't have feed.xml files for existing podcasts, **every `/feeds/X.xml` request returns 404** (silently — `feeds_controller#show` has a bare `rescue StandardError` that returns `head :not_found` and only logs a warning).

**Implication**: you must pre-backfill `<NEW>/podcasts/*` from `<OLD>/podcasts/*` BEFORE the env flip. Skipping this triggers a regression for every existing podcast feed.

The MP3 enclosure URLs cached in subscribers' apps are a different story — they reference `<OLD>` directly (since cached XML predates the env flip), and `<OLD>` stays live forever, so subscribers' MP3 downloads keep working through the cutover regardless.

### 3. TTS happens in-process inside Rails (no separate service env to flip)

`SubmitsEpisodeForProcessing` → `GeneratesEpisodeAudioJob` (Solid Queue, in Puma) → `GeneratesEpisodeAudio` → `SynthesizesAudio`, then `CloudStorage.upload_content` writes the MP3 to `gs://{BUCKET}/podcasts/{id}/episodes/`. There is no out-of-process TTS service that needs its own bucket env updated.

A dormant `podcast-api` Cloud Run service exists but is dead code as of this writing — verify with `gcloud logging read 'resource.labels.service_name="podcast-api"' --freshness=30d` before assuming so.

### 4. Bucket uses object-level ACLs, not uniform bucket-level access

`CloudStorage#upload_content` calls `file.acl.public!` on every uploaded file. This requires `uniform_bucket_level_access: false` on the bucket. Confirm the new bucket matches the old:

```bash
gcloud storage buckets describe gs://<OLD> --format=json
```

Required fields to mirror exactly: `location`, `default_storage_class`, `uniform_bucket_level_access`, `public_access_prevention`, soft-delete retention.

### 5. The app service account has objectAdmin at the PROJECT level, not bucket level

`tts-service-account@very-normal.iam.gserviceaccount.com` has `roles/storage.objectAdmin` granted at the project level. New buckets in the project automatically inherit it. **You do not need to grant bucket-level IAM** when provisioning the new bucket. (This also means revoking write access on the old bucket via `gcloud storage buckets remove-iam-policy-binding` is a no-op — there's no bucket-level grant to remove.)

### 6. The "ACL-clobber-on-rewrite" footgun

This bit us twice. Read it carefully.

**`gcloud storage cp` and `gcloud storage objects update --storage-class=...` both rewrite objects.** The rewritten object inherits the **destination bucket's default object ACL**, NOT the source object's ACL. On a non-uniform-ACL bucket where every object has `AllUsers:READER` set at write-time by the app, this silently strips public-read and the file becomes 403.

**Always re-apply public-read after any object rewrite operation:**

```bash
gcloud storage objects update "gs://<bucket>/<prefix>/**" \
  --add-acl-grant=entity=AllUsers,role=READER
```

Then curl-verify a sample file returns HTTP 200.

This applies to:
- `gcloud storage cp` (any direction)
- `gcloud storage rsync`
- `gcloud storage objects update --storage-class=...` (storage-class change rewrites the object)

Detection: if subscribers' MP3 fetches start returning 403 after any bucket-side operation, this is almost certainly the cause. Time to fix is seconds (re-apply the ACL grant).

## Phase 1 — provision new bucket + cutover

The plan: create `<NEW>` mirroring `<OLD>`, copy voices/, pre-backfill all podcast data, flip Secret Manager, trigger redeploy. No subscriber-visible regression because backfill happens before the read path activates.

### Step 1.1 — Recon (read-only)

Capture old bucket config and confirm preconditions:

```bash
gcloud storage buckets describe gs://<OLD> --format=json
gcloud projects get-iam-policy <project> --format=json | grep -A1 -i tts-service-account
gcloud storage du gs://<OLD>/voices --summarize
gcloud storage ls gs://<OLD>/podcasts/ | wc -l
```

Note: `location`, `default_storage_class`, `uniform_bucket_level_access`, `public_access_prevention`, soft-delete retention duration. New bucket must mirror these exactly.

Verify there's no existing `gs://<NEW>` bucket:

```bash
gcloud storage buckets describe gs://<NEW> 2>&1
# Expected: 404 not found
```

Find every code reference to the old bucket name. Don't trust the issue description; verify yourself:

```bash
grep -rln "<OLD>" ~/code/tts
```

Note that `.env` is gitignored and won't show up in repo grep unless you grep it directly.

### Step 1.2 — Create new bucket (reversible)

```bash
gcloud storage buckets create gs://<NEW> \
  --location=<same-region-as-old> \
  --default-storage-class=STANDARD \
  --soft-delete-duration=7d \
  --no-uniform-bucket-level-access
```

Verify config matches old by diffing the describe output.

If wrong: `gcloud storage buckets delete gs://<NEW>` (only works on empty bucket).

### Step 1.3 — Copy voices/

```bash
gcloud storage cp "gs://<OLD>/voices/*" "gs://<NEW>/voices/"
gcloud storage objects update "gs://<NEW>/voices/*" \
  --add-acl-grant=entity=AllUsers,role=READER
curl -sI "https://storage.googleapis.com/<NEW>/voices/<sample>.mp3"
# Expect: HTTP/2 200, content-type: audio/mpeg
```

The ACL re-apply is required (see footgun #6).

### Step 1.4 — Code refs PR

In a worktree:

```bash
git worktree add -b feat/bucket-rename ~/code/tts-bucket-rename main
```

Edit every code ref found in step 1.1. Typically 4 tracked files + 1 gitignored:

- `app/models/app_config.rb` — `BUCKET` fallback default
- `.kamal/secrets` — local-dev value AND deploy.yml env list (production override happens via Secret Manager but this still needs to be consistent)
- `config/environments/development.local.rb` — dev env default
- `.claude/skills/delete-episode/SKILL.md` — doc reference
- `.env` (gitignored) — local dev env, edit on each developer's machine

Commit, run `bin/rails test` + `bin/rubocop`, push, open PR.

**Do not merge yet.** This PR alone does not change production behavior (env value comes from Secret Manager — see architecture fact #1).

### Step 1.5 — Pre-backfill podcasts/ (the regression-prevention step)

```bash
# Copy is server-side, fast (seconds for ~1.5 GiB in 2026)
gcloud storage cp -r gs://<OLD>/podcasts gs://<NEW>/

# Re-apply public-read (footgun #6)
gcloud storage objects update "gs://<NEW>/podcasts/**" \
  --add-acl-grant=entity=AllUsers,role=READER

# Verify byte-parity
gcloud storage du gs://<OLD>/podcasts --summarize
gcloud storage du gs://<NEW>/podcasts --summarize
# Expect: identical byte counts
```

Spot-check a sample file is publicly readable via HTTPS.

### Step 1.6 — Flip Secret Manager

```bash
printf '<NEW>' | gcloud secrets versions add google-cloud-bucket --data-file=-
gcloud secrets versions access latest --secret=google-cloud-bucket
# Expect: <NEW>
```

This adds a new version. Old version stays accessible — easy rollback via another `versions add` with the old value.

### Step 1.7 — Final incremental re-cp + cutover

Race-window mitigation: anything written to `<OLD>` between step 1.5 and now needs to land in `<NEW>` before the env flip takes effect. Re-cp catches it. The re-cp will clobber ACLs again — re-apply.

```bash
gcloud storage cp -r gs://<OLD>/podcasts gs://<NEW>/
gcloud storage objects update "gs://<NEW>/podcasts/**" \
  --add-acl-grant=entity=AllUsers,role=READER
```

Merge the code-refs PR (step 1.4). This triggers CI → Deploy. Deploy fetches the now-updated Secret Manager value. Watch via `gh run watch`. Total wall time: CI ~50s + Deploy ~3 min.

### Step 1.8 — Post-deploy verification

```bash
# Container env
cd ~/code/tts-bucket-rename
kamal app exec 'printenv GOOGLE_CLOUD_BUCKET'
# Expect: <NEW>

# Real podcast feed via Rails (cache-bust)
curl -s "https://podread.app/feeds/<real-podcast-id>.xml?bust=$(date +%s%N)" | wc -c
# Expect: non-zero body size

# Sample MP3 via direct GCS
curl -sI "https://storage.googleapis.com/<NEW>/podcasts/<id>/episodes/<filename>.mp3"
# Expect: HTTP/2 200, audio/mpeg

# Log check for silent 404s
gcloud logging read 'resource.type="gce_instance" AND "Feed fetch failed"' --freshness=1h
# Expect: no entries
```

End-to-end smoke test that exercises the actual write path (skips TTS cost):

```bash
cat > /tmp/seed_test.rb <<'RUBY'
require "securerandom"
test_id = "smoke-#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}"
mp3 = ("ID3\x04\x00\x00\x00\x00\x00\x00".b + ("\x00".b * 1024))
storage = CloudStorage.new(podcast_id: test_id)
storage.upload_content(content: mp3, remote_path: "episodes/test.mp3")
puts "BUCKET=#{AppConfig::Storage::BUCKET}"
puts "URL=https://storage.googleapis.com/#{AppConfig::Storage::BUCKET}/podcasts/#{test_id}/episodes/test.mp3"
RUBY

kamal app exec --interactive 'bin/rails runner -' < /tmp/seed_test.rb
# Confirm RESULT_BUCKET=<NEW>, then curl the URL — expect HTTP 200, audio/mpeg
# Clean up: gcloud storage rm "gs://<NEW>/podcasts/<test_id>/episodes/test.mp3"
```

## Phase 2 — regenerate cached feed XMLs

After Phase 1, `<NEW>/podcasts/*/feed.xml` files are byte-identical to the old bucket's. Their `<enclosure>` tags still reference `<OLD>` URLs. Subscribers continue working (old bucket is live), but the migration isn't truly complete until feeds reference `<NEW>` URLs.

```bash
cd ~/code/tts
kamal app exec --interactive 'bin/rails feeds:regenerate_all'
```

The `feeds:regenerate_all` rake task iterates podcasts with complete episodes, calls `GeneratesRssFeed`, uploads the result via `CloudStorage` (which writes to `<NEW>` post-cutover). Each upload calls `file.acl.public!` so no ACL re-apply needed. Per-podcast failures are logged but don't crash the task.

Verify:

```bash
gcloud storage cat "gs://<NEW>/podcasts/<id>/feed.xml" | grep enclosure | head -3
# Expect: enclosure URLs now point at storage.googleapis.com/<NEW>/...
```

Smoke-test 5 real podcast feeds:

```bash
for p in <id1> <id2> <id3> <id4> <id5>; do
  http=$(curl -s -o /tmp/f.xml -w "%{http_code}" "https://podread.app/feeds/$p.xml?b=$(date +%s%N)")
  bucket=$(grep -oE 'enclosure url="https://storage.googleapis.com/[^/]+' /tmp/f.xml | head -1 | sed 's|.*/||')
  echo "$p http=$http enc-bucket=$bucket"
done
# Expect all: http=200, enc-bucket=<NEW>
```

### Legacy root files (optional)

If the bucket has root-level files (e.g., a legacy single-podcast feed at `gs://<OLD>/feed.xml` with `episodes/` at the bucket root), copy them for parity. Not strictly required if Phase 3 keeps the old bucket live forever — subscribers fetch direct from old.

```bash
gcloud storage cp gs://<OLD>/feed.xml gs://<NEW>/
gcloud storage cp gs://<OLD>/manifest.json gs://<NEW>/
gcloud storage cp -r gs://<OLD>/episodes gs://<NEW>/
gcloud storage objects update gs://<NEW>/feed.xml gs://<NEW>/manifest.json \
  --add-acl-grant=entity=AllUsers,role=READER
gcloud storage objects update "gs://<NEW>/episodes/**" \
  --add-acl-grant=entity=AllUsers,role=READER
```

Don't URL-rewrite the legacy feed.xml in `<NEW>` — its enclosures still point at `<OLD>`. Since `<OLD>` stays live forever, subscribers fetching the new bucket's copy would still get working URLs. But subscribers don't fetch from `<NEW>` for the legacy feed — their cached URL is `<OLD>`. The new-bucket copy is archival completeness, not active use.

## Phase 3 — archive old bucket

Goal: cheap storage + cheap reads on old bucket, since legacy subscribers will keep pulling MP3s from it indefinitely.

### Storage class choice

Don't use ARCHIVE — its $0.05/GB retrieval cost dwarfs storage savings if there's any read traffic. NEARLINE ($0.010/GB-month + $0.01/GB retrieval) is the right balance for a "mostly-read-rarely" bucket like this. COLDLINE is also reasonable for truly-rare reads.

```bash
gcloud storage buckets update gs://<OLD> --default-storage-class=NEARLINE
gcloud storage objects update "gs://<OLD>/**" --storage-class=NEARLINE
```

**Then immediately re-apply public ACLs.** The storage-class change rewrites every object → triggers footgun #6 → all subscriber fetches start returning 403:

```bash
gcloud storage objects update "gs://<OLD>/**" \
  --add-acl-grant=entity=AllUsers,role=READER

# Verify
curl -sI "https://storage.googleapis.com/<OLD>/episodes/<sample>.mp3"
# Expect: HTTP/2 200, audio/mpeg
```

### IAM revocation (skipped in our migration)

Original plan was to revoke write permissions on the old bucket. We skipped because:
- The app service account has `roles/storage.objectAdmin` at PROJECT level, not bucket level → no bucket-level binding to remove
- The Rails env is flipped → no code path writes to old bucket anyway
- Demoting project-level grant to scope per-bucket is invasive (affects every other bucket in the project)
- GCS Bucket Lock + Retention Policy is the canonical "freeze" mechanism but is irreversible once locked

Trust the code change. Monitor logs if you want enforcement evidence:

```bash
gcloud logging read 'protoPayload.resourceName=~"gs://<OLD>"
  AND protoPayload.methodName=~"storage.objects.(create|update|delete)"' \
  --freshness=7d
```

If you see writes by your service account, something missed the cutover.

## Rollback procedures

### Roll back the env flip (Phase 1)

```bash
# Re-add the old version to Secret Manager
printf '<OLD>' | gcloud secrets versions add google-cloud-bucket --data-file=-
# Trigger another empty-commit redeploy
```

Cached feeds revert to reading from `<OLD>` (still live, still complete). Subscribers see no change.

### Roll back the storage-class change (Phase 3)

```bash
gcloud storage buckets update gs://<OLD> --default-storage-class=STANDARD
gcloud storage objects update "gs://<OLD>/**" --storage-class=STANDARD
gcloud storage objects update "gs://<OLD>/**" \
  --add-acl-grant=entity=AllUsers,role=READER  # rewrite clobbers ACL again
```

NEARLINE has 30-day minimum storage duration — files moved out of NEARLINE before 30 days incur an early-deletion fee equal to remaining storage cost. Trivial dollar amounts on this dataset.

## Anti-patterns to avoid

- **Don't trust deploy.yml env values** as the production source of truth — Secret Manager wins.
- **Don't `feeds:regenerate_all` before the env flip** — it would regenerate feeds with the OLD bucket's URLs (since BUCKET still points at OLD), achieving nothing.
- **Don't skip the pre-backfill** — the read path uses BUCKET, and missing files in `<NEW>` mean silent 404s.
- **Don't assume `gcloud storage cp` preserves ACLs** — it doesn't (footgun #6).
- **Don't use ARCHIVE storage class** for a bucket that still gets reads.
- **Don't try to delete the old bucket** — keep it forever as read-only fallback. Disk is cheap; broken podcast subscribers are not.
