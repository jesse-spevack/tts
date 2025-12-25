# Unified Callback Secret

**Date:** 2025-12-24
**Status:** Ready for implementation

## Problem

The Hub and Generator services use separate secrets that must have identical values:
- `generator-callback-secret` (Hub reads to verify incoming callbacks)
- `hub-callback-secret` (Generator reads to send callbacks)

On 2025-12-20, `generator-callback-secret` was created with a corrupted value (`\{\``), causing all callbacks to fail with 401 Unauthorized. Episodes got stuck in "processing" state.

## Solution

Consolidate to a single secret that both services read.

### Current State
```
GCP Secret Manager:
├── generator-callback-secret  → Hub reads
└── hub-callback-secret        → Generator reads

1Password (keys/tts):
└── GENERATOR_CALLBACK_SECRET  → Hub reads (local deploys)
```

### Target State
```
GCP Secret Manager:
└── callback-secret  → Both services read

1Password (keys/tts):
└── CALLBACK_SECRET  → Hub reads (local deploys, must match GCP)
```

## Changes Required

### GCP Secret Manager
1. Create `callback-secret` with the correct 64-character value
2. Delete `generator-callback-secret` (after verification)
3. Delete `hub-callback-secret` (after verification)

### GitHub Actions (.github/workflows/deploy.yml)

Hub deploy (line 70):
```yaml
# From:
GENERATOR_CALLBACK_SECRET=$(gcloud secrets versions access latest --secret=generator-callback-secret)
# To:
GENERATOR_CALLBACK_SECRET=$(gcloud secrets versions access latest --secret=callback-secret)
```

Generator deploy (line 145):
```yaml
# From:
HUB_CALLBACK_SECRET=$(gcloud secrets versions access latest --secret=hub-callback-secret)
# To:
HUB_CALLBACK_SECRET=$(gcloud secrets versions access latest --secret=callback-secret)
```

### 1Password (keys/tts)
- Rename `GENERATOR_CALLBACK_SECRET` → `CALLBACK_SECRET`
- Update `.kamal/secrets` line 6 to fetch `CALLBACK_SECRET`

## Rollout Order

1. **Create new secret**
   ```bash
   echo "THE_64_CHAR_SECRET_VALUE" | gcloud secrets create callback-secret --data-file=-
   ```

2. **Update deploy workflow**
   - Change both lines to read from `callback-secret`
   - Commit and push

3. **Deploy both services**
   - Let CI run or trigger manually
   - Verify callbacks work (create a test episode)

4. **Cleanup (after verification)**
   - Delete `generator-callback-secret` from GCP
   - Delete `hub-callback-secret` from GCP
   - Update 1Password entry name

## Verification

1. Create a test episode to trigger the full flow
2. Check episode status transitions from `processing` → `complete`
3. Check Hub logs for absence of `event=unauthorized_callback_attempt`

## Rollback

If verification fails:
- Old secrets still exist (not deleted until Step 4)
- Revert workflow change and redeploy
