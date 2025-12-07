# Episode Sharing Design

## Overview

Add the ability for users to share individual episodes via a public URL. Recipients can listen in the browser, copy the link, or download the MP3.

## Features

### Public Episode Page

**Route:** `GET /episodes/:id` (using prefixed ID like `ep_7x8k2m`)

**Controller:** `EpisodesController#show`
- Finds episode by prefixed ID
- Skips authentication (public access)
- Returns 404 for non-existent or non-complete episodes

**Page Contents:**
- Podcast name
- Episode title
- Author and duration
- HTML5 audio player
- Episode description
- Copy Link button (copies URL, icon changes to checkmark on success)
- Download MP3 button (direct link to GCS file with `download` attribute)

### Episode Card Updates

For completed episodes only, add two icon buttons in the top right (next to duration):

1. **Share button** - Copies public episode URL to clipboard, icon changes to checkmark briefly
2. **Download button** - Direct download of MP3 file

Both buttons are hidden for pending/processing/failed episodes.

**Icons (Heroicons):**
- Share: three connected nodes
- Download: folder-arrow-down

## Technical Changes

### 1. Add prefixed_ids gem

```ruby
# Gemfile
gem "prefixed_ids"

# Episode model
class Episode < ApplicationRecord
  has_prefix_id :ep
end
```

### 2. Update Routes

```ruby
resources :episodes, only: [:index, :new, :create, :show]
```

### 3. Episodes Controller

```ruby
class EpisodesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]

  def show
    @episode = Episode.find_by_prefix_id!(params[:id])

    # Only show complete episodes publicly
    raise ActiveRecord::RecordNotFound unless @episode.complete?

    @podcast = @episode.podcast
  end
end
```

### 4. New View: episodes/show.html.erb

Public episode page with:
- Podcast name header
- Episode title, author, duration
- `<audio>` element with controls, pointing to `@episode.audio_url`
- Description text
- Copy Link button (Stimulus controller for clipboard)
- Download MP3 link

### 5. Update Episode Card Partial

Add share and download icons for complete episodes:
- Share icon triggers clipboard copy of `episode_url(@episode)`
- Download icon links to `@episode.audio_url` with `download` attribute

## Design Decisions

- **Prefixed IDs**: Using `ep_` prefix makes URLs unguessable and doesn't reveal episode count
- **Public access**: Consistent with RSS feed already being public
- **Complete episodes only**: No value in sharing episodes that can't be played
- **No toast notifications**: Icon changes to checkmark for feedback instead
- **No podcast app deep links**: Self-hosted podcasts aren't in app directories, so deep linking isn't possible
- **Simple clipboard copy**: Users paste wherever they want to share
