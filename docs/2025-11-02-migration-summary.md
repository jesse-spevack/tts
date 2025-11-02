# us-west3 Migration Summary

**Date:** 2025-11-02

## Changes Made

1. **Cloud Tasks Queue:** Migrated from us-central1 to us-west3
2. **Cloud Run Service:** Redeployed to us-west3
3. **Configuration:** Updated .env, .env.example, deployment docs
4. **Cleanup:** Deleted old us-central1 resources

## Infrastructure Locations

All services now in **us-west3 (Salt Lake City)**:
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
