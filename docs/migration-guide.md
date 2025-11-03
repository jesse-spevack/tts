# Migration Guide: Moving to Podcast-Scoped Storage

This guide is for existing users who need to migrate their podcast from flat storage to the new podcast-scoped structure.

## Overview

**Old structure (flat):**
```
gs://bucket/
  ├── episodes/*.mp3
  ├── feed.xml
  └── manifest.json
```

**New structure (podcast-scoped):**
```
gs://bucket/podcasts/{podcast_id}/
  ├── episodes/*.mp3
  ├── feed.xml
  └── manifest.json
```

## Migration Steps

### Step 1: Generate Your Podcast ID

Generate a unique podcast ID:
```bash
PODCAST_ID="podcast_$(openssl rand -hex 8)"
echo "Your podcast ID: $PODCAST_ID"
```

Example output: `podcast_a1b2c3d4e5f6a7b8`

**Save this ID** - you'll need it permanently.

### Step 2: Add to Your Environment

Add to your `.env` file:
```bash
echo "PODCAST_ID=$PODCAST_ID" >> .env
```

Verify it's set:
```bash
source .env
echo $PODCAST_ID
```

### Step 3: Backup Current State

List what you currently have:
```bash
BUCKET="YOUR_BUCKET_NAME"  # Replace with your actual bucket

echo "Current episodes:"
gsutil ls gs://$BUCKET/episodes/

echo -e "\nCurrent feed and manifest:"
gsutil ls gs://$BUCKET/*.xml
gsutil ls gs://$BUCKET/*.json
```

### Step 4: Migrate Files to New Structure

Run the migration commands:

```bash
# Migrate episodes directory
echo "Migrating episodes..."
gsutil -m cp -r "gs://$BUCKET/episodes/*" "gs://$BUCKET/podcasts/$PODCAST_ID/episodes/"

# Migrate feed.xml
echo "Migrating feed.xml..."
gsutil cp "gs://$BUCKET/feed.xml" "gs://$BUCKET/podcasts/$PODCAST_ID/feed.xml"

# Migrate manifest.json
echo "Migrating manifest.json..."
gsutil cp "gs://$BUCKET/manifest.json" "gs://$BUCKET/podcasts/$PODCAST_ID/manifest.json"

echo "Migration complete!"
```

**Note:** Using `cp` instead of `mv` keeps backups of the old files.

### Step 5: Verify Migration

Check the new structure:
```bash
echo "Verifying new structure..."
gsutil ls -r gs://$BUCKET/podcasts/$PODCAST_ID/
```

You should see:
```
gs://YOUR_BUCKET/podcasts/YOUR_PODCAST_ID/episodes/
gs://YOUR_BUCKET/podcasts/YOUR_PODCAST_ID/feed.xml
gs://YOUR_BUCKET/podcasts/YOUR_PODCAST_ID/manifest.json
```

Verify file counts match:
```bash
echo "Old episode count:"
gsutil ls gs://$BUCKET/episodes/*.mp3 | wc -l

echo "New episode count:"
gsutil ls gs://$BUCKET/podcasts/$PODCAST_ID/episodes/*.mp3 | wc -l
```

These numbers should match!

### Step 6: Test the New Feed

Download and inspect the new feed:
```bash
curl "https://storage.googleapis.com/$BUCKET/podcasts/$PODCAST_ID/feed.xml" | head -30
```

Verify it shows your episodes and podcast metadata.

### Step 7: Test Local Generation

Test that new episodes work with the podcast-scoped structure:
```bash
ruby generate.rb input/sample.md
```

Check that the new episode appears in the correct location:
```bash
gsutil ls -lh gs://$BUCKET/podcasts/$PODCAST_ID/episodes/ | tail -1
```

### Step 8: Update Your Podcast Subscription

**New feed URL:**
```
https://storage.googleapis.com/$BUCKET/podcasts/$PODCAST_ID/feed.xml
```

In your podcast app:
1. Add the new feed URL
2. Verify all episodes appear
3. Test playing an episode
4. Once confirmed working, remove the old feed

### Step 9: Clean Up Old Files (Optional)

**Only do this after confirming the new feed works for at least 24 hours!**

```bash
# Delete old files
gsutil -m rm -r gs://$BUCKET/episodes/
gsutil rm gs://$BUCKET/feed.xml
gsutil rm gs://$BUCKET/manifest.json

echo "Old files deleted. Migration complete!"
```

## Rollback Plan

If something goes wrong, you can rollback since we used `cp` instead of `mv`:

1. The old files still exist at the root level
2. Remove the `PODCAST_ID` from `.env`
3. Continue using the old feed URL
4. Debug the issue before trying again

To delete the failed migration attempt:
```bash
gsutil -m rm -r gs://$BUCKET/podcasts/$PODCAST_ID/
```

## Troubleshooting

### Feed shows no episodes

Check the manifest:
```bash
gsutil cat gs://$BUCKET/podcasts/$PODCAST_ID/manifest.json
```

If empty or missing episodes, check that all MP3 files migrated:
```bash
gsutil ls -r gs://$BUCKET/podcasts/$PODCAST_ID/episodes/
```

### MP3 files missing

Verify files are in the old location:
```bash
gsutil ls gs://$BUCKET/episodes/
```

If they're there, re-run the migration command from Step 4.

### "Invalid podcast_id format" error

Your podcast ID must be exactly: `podcast_` followed by 16 hex characters.

Generate a new one:
```bash
echo "podcast_$(openssl rand -hex 8)"
```

## Post-Migration

After successful migration:

1. **Document your feed URL** - Save it somewhere safe:
   ```bash
   echo "https://storage.googleapis.com/$BUCKET/podcasts/$PODCAST_ID/feed.xml" > .podcast-url
   ```

2. **Test API access** (if using the API):
   ```bash
   TOKEN=$(gcloud auth print-identity-token)

   curl -X POST https://podcast-api-ns2hvyzzra-wm.a.run.app/publish \
     -H "Authorization: Bearer $TOKEN" \
     -F "podcast_id=$PODCAST_ID" \
     -F "title=Test Episode" \
     -F "author=Test Author" \
     -F "description=Testing migration" \
     -F "content=@input/sample.md"
   ```

3. **Monitor the first few episodes** - Check that new episodes appear correctly in the feed

## Support

If you encounter issues during migration:
1. Check the troubleshooting section above
2. Verify your `PODCAST_ID` is correctly formatted
3. Ensure you have the correct bucket permissions
4. Review Cloud Run logs if using the API
