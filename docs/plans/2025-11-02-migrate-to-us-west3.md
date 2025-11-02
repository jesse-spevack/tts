# Migrate Infrastructure to us-west3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate all Google Cloud infrastructure from us-central1 to us-west3 (Denver region) for regional consistency and reduced latency.

**Architecture:** This is a zero-downtime migration that creates new infrastructure in us-west3, migrates data, updates configuration, redeploys services, and cleans up old resources. We'll use Cloud Storage Transfer Service for large data migration and maintain the existing bucket temporarily for rollback capability.

**Tech Stack:** Google Cloud Run, Cloud Tasks, Cloud Storage, gcloud CLI, bash scripting

**Current State:**
- GCS Bucket: `verynormal-tts-podcast` in us-west3 (✓ already in target region)
- Cloud Run: `podcast-api` in us-central1 (needs migration)
- Cloud Tasks: `episode-processing` queue in us-central1 (needs migration)
- Data: ~42MB in episodes/ directory

**Risk Mitigation:**
- No data migration needed (bucket already in us-west3)
- Old infrastructure kept until verification complete
- Can rollback by redeploying to us-central1

---

## Task 1: Create Cloud Tasks Queue in us-west3

**Files:**
- Modify: `.env`
- Reference: `bin/setup-infrastructure`

**Step 1: Update environment configuration**

Update `.env` to target us-west3:

```bash
# Change this line:
CLOUD_TASKS_LOCATION=us-central1

# To:
CLOUD_TASKS_LOCATION=us-west3
```

**Step 2: Verify current queue configuration**

Run:
```bash
gcloud tasks queues describe episode-processing \
  --location=us-central1 \
  --project=very-normal \
  --format='value(rateLimits,retryConfig)'
```

Expected: Shows current rate limits and retry config
Note: Save this output to replicate exact settings

**Step 3: Create new queue in us-west3**

Run:
```bash
source .env && \
gcloud tasks queues create episode-processing \
  --location=us-west3 \
  --project=very-normal \
  --max-attempts=3 \
  --max-retry-duration=3600s
```

Expected: Queue created successfully or "already exists" message

**Step 4: Verify new queue exists**

Run:
```bash
gcloud tasks queues describe episode-processing \
  --location=us-west3 \
  --project=very-normal
```

Expected: Shows queue details with state: RUNNING

**Step 5: Commit configuration change**

```bash
git add .env
git commit -m "config: migrate Cloud Tasks location to us-west3"
```

---

## Task 2: Deploy Cloud Run Service to us-west3

**Files:**
- Modify: `bin/deploy` (line 23)

**Step 1: Update deploy script to support explicit region**

The script currently uses `REGION=${CLOUD_TASKS_LOCATION:-us-central1}`.
This is correct - it will now use us-west3 from .env.

Verify line 23:
```bash
cat bin/deploy | grep -n "REGION="
```

Expected: Line 23 shows `REGION=${CLOUD_TASKS_LOCATION:-us-central1}`

**Step 2: Build and deploy to us-west3**

Run:
```bash
./bin/deploy
```

Expected output:
- Build completes (~3-5 minutes)
- Deployment to us-west3 succeeds
- New service URL printed (will be different domain)

Note: This creates a NEW service in us-west3. The us-central1 service continues running.

**Step 3: Capture new service URL**

Run:
```bash
gcloud run services describe podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --format='value(status.url)'
```

Expected: `https://podcast-api-672738093593.us-west3.run.app`
Save this URL for testing.

**Step 4: Verify service is healthy**

Run:
```bash
SERVICE_URL=$(gcloud run services describe podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --format='value(status.url)')

curl $SERVICE_URL/health
```

Expected: `{"status":"healthy"}`

**Step 5: Commit deployment documentation**

Create a temporary note about the migration:

```bash
echo "Service deployed to us-west3: $(date)" >> docs/migration-log.txt
git add docs/migration-log.txt
git commit -m "deploy: Cloud Run service to us-west3"
```

---

## Task 3: Test End-to-End Episode Creation

**Files:**
- Reference: `input/2025-11-01-searls-of-wisdom-for-september-2025.md`

**Step 1: Get service URL and auth token**

Run:
```bash
source .env
SERVICE_URL=$(gcloud run services describe podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --format='value(status.url)')

echo "Service URL: $SERVICE_URL"
echo "Token set: ${API_SECRET_TOKEN:0:10}..."
```

Expected: Shows URL and token prefix

**Step 2: Submit test episode**

Run:
```bash
curl -X POST $SERVICE_URL/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=Migration Test Episode" \
  -F "author=Test Author" \
  -F "description=Testing us-west3 deployment" \
  -F "content=@input/2025-11-01-searls-of-wisdom-for-september-2025.md"
```

Expected: `{"status":"success","message":"Episode submitted for processing"}`

**Step 3: Monitor Cloud Run logs for processing**

Run:
```bash
sleep 10 && \
gcloud run services logs read podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --limit=50 | grep "event="
```

Expected output showing event progression:
- `event=file_uploaded`
- `event=task_enqueued`
- `event=processing_started`
- `event=file_downloaded`
- `event=episode_processed`
- `event=processing_completed`

**Step 4: Check for errors**

Run:
```bash
gcloud run services logs read podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --limit=100 | grep -i "error\|failed"
```

Expected: No errors (or only errors from earlier testing)

**Step 5: Verify episode in bucket**

Run:
```bash
gsutil ls gs://verynormal-tts-podcast/episodes/ | tail -5
```

Expected: New MP3 file for "Migration Test Episode"

**Step 6: Document successful test**

```bash
echo "End-to-end test passed: $(date)" >> docs/migration-log.txt
git add docs/migration-log.txt
git commit -m "test: verify us-west3 deployment works end-to-end"
```

---

## Task 4: Update DNS/External References (if applicable)

**Files:**
- None (documentation only)

**Step 1: Check if any external systems reference the old URL**

Questions to answer:
- Do you have webhook integrations pointing to the Cloud Run URL?
- Do you have documentation with hardcoded URLs?
- Do you have monitoring/alerting configured for the old URL?

Run:
```bash
grep -r "us-central1.run.app" . --include="*.md" --include="*.sh" 2>/dev/null
```

Expected: Shows any references to old URL in docs/scripts

**Step 2: Update any found references**

For each file found, update:
- `us-central1.run.app` → `us-west3.run.app`

**Step 3: Check README for URL references**

Run:
```bash
grep -n "podcast-api.*run.app" README.md
```

Expected: May show example URLs that should be updated

**Step 4: Update README if needed**

If README has hardcoded URLs, update them to use us-west3.

**Step 5: Commit documentation updates**

```bash
git add README.md docs/
git commit -m "docs: update service URLs to us-west3"
```

---

## Task 5: Delete Old us-central1 Infrastructure

**Files:**
- None (gcloud operations only)

**Step 1: Verify new infrastructure is working**

Manual verification checklist:
- [ ] Health endpoint returns healthy
- [ ] At least one test episode created successfully
- [ ] No errors in Cloud Run logs
- [ ] Cloud Tasks queue is processing tasks

**Step 2: Pause old Cloud Tasks queue**

Run:
```bash
gcloud tasks queues pause episode-processing \
  --location=us-central1 \
  --project=very-normal
```

Expected: Queue paused successfully

**Step 3: Wait for in-flight tasks to complete**

Run:
```bash
gcloud tasks list \
  --queue=episode-processing \
  --location=us-central1 \
  --project=very-normal
```

Expected: Empty list (no tasks remaining)
If tasks remain, wait 10 minutes and check again.

**Step 4: Delete old Cloud Run service**

Run:
```bash
gcloud run services delete podcast-api \
  --region=us-central1 \
  --project=very-normal \
  --quiet
```

Expected: Service deleted successfully

**Step 5: Delete old Cloud Tasks queue**

Run:
```bash
gcloud tasks queues delete episode-processing \
  --location=us-central1 \
  --project=very-normal \
  --quiet
```

Expected: Queue deleted successfully

**Step 6: Verify cleanup**

Run:
```bash
echo "=== Cloud Run Services ==="
gcloud run services list --project=very-normal

echo -e "\n=== Cloud Tasks Queues ==="
gcloud tasks queues list --project=very-normal
```

Expected:
- One Cloud Run service in us-west3
- One Cloud Tasks queue in us-west3

**Step 7: Document completion**

```bash
cat >> docs/migration-log.txt <<EOF

Migration completed: $(date)
- Old us-central1 infrastructure deleted
- Running on us-west3:
  - Cloud Run: podcast-api
  - Cloud Tasks: episode-processing
  - GCS Bucket: verynormal-tts-podcast
EOF

git add docs/migration-log.txt
git commit -m "cleanup: remove us-central1 infrastructure"
```

---

## Task 6: Update Deployment Documentation

**Files:**
- Modify: `docs/deployment.md`
- Modify: `bin/setup-infrastructure` (comments only)

**Step 1: Read current deployment docs**

Run:
```bash
cat docs/deployment.md | head -50
```

Expected: Shows current documentation with us-central1 references

**Step 2: Update deployment.md region references**

Find and replace in `docs/deployment.md`:
- `us-central1` → `us-west3`
- Update example URLs to show us-west3 domain
- Update location description: "Iowa" → "Oregon (us-west3, closest to Denver)"

**Step 3: Add migration note to deployment.md**

Add section at the top:

```markdown
## Region

**Current Region:** us-west3 (Oregon)

All infrastructure runs in us-west3 for proximity to Denver:
- Cloud Run service
- Cloud Tasks queue
- GCS bucket (verynormal-tts-podcast)

*Migrated from us-central1 on 2025-11-02*
```

**Step 4: Update setup-infrastructure comments**

In `bin/setup-infrastructure` line 31, update comment:

```bash
# Before:
LOCATION=${CLOUD_TASKS_LOCATION:-us-central1}

# After (with updated comment):
LOCATION=${CLOUD_TASKS_LOCATION:-us-west3}  # Default to us-west3 for Denver proximity
```

**Step 5: Verify .env.example is correct**

Run:
```bash
grep CLOUD_TASKS_LOCATION .env.example
```

Expected: Shows `CLOUD_TASKS_LOCATION=us-central1`

Update to:
```bash
CLOUD_TASKS_LOCATION=us-west3
```

**Step 6: Run tests to ensure nothing broke**

Run:
```bash
rake test
```

Expected: All 130 tests pass

**Step 7: Commit documentation updates**

```bash
git add docs/deployment.md bin/setup-infrastructure .env.example
git commit -m "docs: update region to us-west3 throughout documentation"
```

---

## Task 7: Push All Changes and Clean Up

**Files:**
- All committed changes

**Step 1: Review all commits**

Run:
```bash
git log --oneline -10
```

Expected: Shows all migration-related commits

**Step 2: Push to main**

Run:
```bash
git push origin main
```

Expected: All commits pushed successfully

**Step 3: Remove temporary migration log**

Run:
```bash
rm docs/migration-log.txt
```

**Step 4: Verify production service**

Run final health check:
```bash
source .env
SERVICE_URL=$(gcloud run services describe podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --format='value(status.url)')

curl $SERVICE_URL/health
```

Expected: `{"status":"healthy"}`

**Step 5: Create summary of changes**

Document the migration results:
```bash
cat > docs/2025-11-02-migration-summary.md <<'EOF'
# us-west3 Migration Summary

**Date:** 2025-11-02

## Changes Made

1. **Cloud Tasks Queue:** Migrated from us-central1 to us-west3
2. **Cloud Run Service:** Redeployed to us-west3
3. **Configuration:** Updated .env, .env.example, deployment docs
4. **Cleanup:** Deleted old us-central1 resources

## Infrastructure Locations

All services now in **us-west3 (Oregon)**:
- Cloud Run: `podcast-api`
- Cloud Tasks: `episode-processing` queue
- GCS Bucket: `verynormal-tts-podcast` (was already in us-west3)

## Benefits

- Regional consistency across all services
- Reduced latency (closer to Denver)
- Simplified operations (single region)

## Testing

- ✅ Health endpoint verified
- ✅ End-to-end episode creation tested
- ✅ All 130 unit tests passing
- ✅ No errors in Cloud Run logs

## Rollback Plan

If issues arise:
1. Update `.env`: `CLOUD_TASKS_LOCATION=us-central1`
2. Run `./bin/deploy` (redeploys to us-central1)
3. Recreate Cloud Tasks queue in us-central1

Note: GCS bucket remains in us-west3 (no rollback needed).
EOF

git add docs/2025-11-02-migration-summary.md
git commit -m "docs: add migration summary"
git push origin main
```

**Step 6: Final verification**

Submit one more test episode to production:
```bash
source .env
SERVICE_URL=$(gcloud run services describe podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --format='value(status.url)')

curl -X POST $SERVICE_URL/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=Post-Migration Verification" \
  -F "author=System Test" \
  -F "description=Final verification after migration" \
  -F "content=@input/2025-11-01-searls-of-wisdom-for-september-2025.md"
```

Expected: `{"status":"success","message":"Episode submitted for processing"}`

**Step 7: Monitor final episode processing**

Wait 2-3 minutes, then:
```bash
gcloud run services logs read podcast-api \
  --region=us-west3 \
  --project=very-normal \
  --limit=20 | grep "event=processing_completed"
```

Expected: See completion event for "Post-Migration Verification"

---

## Rollback Plan

If something goes wrong during migration:

### Before Old Infrastructure Deleted (Tasks 1-4)

Simply redeploy to us-central1:

```bash
# 1. Revert .env
sed -i '' 's/us-west3/us-central1/g' .env

# 2. Redeploy
./bin/deploy

# 3. Delete new us-west3 resources
gcloud run services delete podcast-api --region=us-west3 --project=very-normal --quiet
gcloud tasks queues delete episode-processing --location=us-west3 --project=very-normal --quiet
```

### After Old Infrastructure Deleted (Tasks 5+)

Recreate infrastructure in us-central1:

```bash
# 1. Update .env
echo "CLOUD_TASKS_LOCATION=us-central1" >> .env

# 2. Recreate queue
gcloud tasks queues create episode-processing \
  --location=us-central1 \
  --project=very-normal \
  --max-attempts=3 \
  --max-retry-duration=3600s

# 3. Deploy service
./bin/deploy
```

## Verification Checklist

Before considering migration complete:

- [ ] `.env` has `CLOUD_TASKS_LOCATION=us-west3`
- [ ] Cloud Tasks queue exists in us-west3 with state RUNNING
- [ ] Cloud Run service deployed to us-west3
- [ ] Health endpoint returns `{"status":"healthy"}`
- [ ] Test episode submitted successfully
- [ ] Logs show complete event progression (file_uploaded → processing_completed)
- [ ] New MP3 file appears in GCS bucket
- [ ] No errors in recent Cloud Run logs
- [ ] Documentation updated with us-west3 references
- [ ] Old us-central1 resources deleted
- [ ] All tests passing (rake test)
- [ ] Changes committed and pushed to main

## Estimated Time

- Task 1: 5 minutes (create queue)
- Task 2: 8 minutes (build + deploy)
- Task 3: 15 minutes (end-to-end test + monitoring)
- Task 4: 5 minutes (update references)
- Task 5: 5 minutes (cleanup)
- Task 6: 10 minutes (documentation)
- Task 7: 5 minutes (push + verify)

**Total: ~50 minutes** (mostly waiting for builds/deploys)

## Notes

- **Zero downtime:** New infrastructure created before old deleted
- **No data migration:** GCS bucket already in us-west3
- **Easy rollback:** Can redeploy to us-central1 anytime
- **Cost neutral:** Same resources, different location
