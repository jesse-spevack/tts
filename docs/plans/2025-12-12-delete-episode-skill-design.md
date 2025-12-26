# Delete Episode Skill Design

## Overview

A Claude Code skill that enables deleting podcast episodes from the TTS system. Claude invokes this skill when the user asks to delete, remove, or clean up an episode.

## Location

`.claude/skills/delete-episode/SKILL.md`

## What the Skill Provides

Domain knowledge Claude doesn't have:

1. **Episodes exist in three places** - Hub database, GCS storage (MP3 + manifest), RSS feed
2. **Hub is source of truth** - Find episode there first via Kamal console
3. **Key relationships** - `episode.podcast.podcast_id` gives GCS folder, `episode.gcs_episode_id` gives MP3 filename
4. **GCS structure** - `gs://verynormal-tts-podcast/podcasts/{podcast_id}/` contains episodes/, manifest.json, feed.xml
5. **RSS regeneration** - Uses RSSGenerator class with podcast config, reads from manifest

## Constraints

- Confirm before deleting (show episode details)
- If multiple matches, list all and ask which one
- Stop on failure, report what succeeded

## Trigger Phrases

"delete the episode...", "remove episode...", "clean up the episode about..."

## Design Decisions

- **No helper scripts** - Claude can handle gsutil, Kamal, Ruby inline. Add scripts only if we find Claude struggles.
- **Lean instructions** - Don't explain what Claude already knows (gsutil syntax, JSON manipulation)
- **Relative paths** - Reference project structure relatively, not absolute paths
