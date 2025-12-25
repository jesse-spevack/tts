# Braindump

Ideas and future improvements to consider.

---

## Consolidate Secrets to Single Source of Truth

**Context:** Currently secrets come from three sources:
1. GCP Secret Manager (used by GitHub Actions deploys)
2. 1Password (used by local Kamal deploys)
3. Hardcoded values in `.kamal/secrets`

**Idea:** Move everything to GCP Secret Manager. Change `.kamal/secrets` to use `gcloud secrets versions access` instead of 1Password.

**Pros:**
- Single source of truth
- No drift between sources
- No 1Password dependency for deploys

**Cons:**
- Local deploys require `gcloud` auth (already needed anyway)
- More `gcloud` calls during local deploy

**Prerequisites:**
- Complete the unified callback secret work first
- Test that local deploys work with gcloud-based secrets
