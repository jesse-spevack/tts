# Agent Prompt 2: Media & Header Components

## Objective
Extract audio player and page header components, plus extract inline SVG icons to match the existing icon partial pattern.

## Context
Audio players are duplicated 4 times with similar markup. Page headers follow a pattern that can be standardized. Two SVG icons are inline when they should be in the icons directory.

## Tasks

### Task 1: Create Audio Player Partial

**Create:** `app/views/shared/_audio_player.html.erb`

**Current duplicates in:**
- `app/views/episodes/show.html.erb:30-34`
- `app/views/sessions/new.html.erb:14-16` and `20-22`
- `app/views/pages/how_it_sounds.html.erb:7-10`

**Requirements:**
- Accept parameters: `source` (audio URL), `label` (optional), `preload` (optional, default: "metadata")
- Include optional label above player
- Full width styling
- Proper fallback message

**Signature:**
```erb
<%# locals: (source:, label: nil, preload: "metadata") %>
```

**Example usage:**
```erb
<%= render "shared/audio_player",
  source: @episode.audio_url,
  label: "Premium voice",
  preload: "metadata"
%>
```

**After creating the partial, update these files:**
1. `app/views/episodes/show.html.erb` (lines 29-34)
2. `app/views/sessions/new.html.erb` (lines 12-17 and 18-23)
3. `app/views/pages/how_it_sounds.html.erb` (lines 5-11)

**Note for sessions/new.html.erb:** Include wrapper with label:
```erb
<div>
  <%= render "shared/audio_player",
    source: "/sample-chirp3-hd-enceladus.mp3",
    label: "Premium voice"
  %>
</div>
```

---

### Task 2: Create Page Header Partial

**Create:** `app/views/shared/_page_header.html.erb`

**Current pattern in:**
- `app/views/episodes/index.html.erb:6`
- `app/views/episodes/new.html.erb:2`
- `app/views/settings/show.html.erb:5`
- `app/views/billing/show.html.erb:5`
- `app/views/pages/how_it_sounds.html.erb:2`

**Requirements:**
- Accept parameters: `title`, `subtitle` (optional), `size` (default: "2xl")
- Support multiple heading sizes: "2xl", "3xl"
- Optional subtitle with subtext styling
- Consistent bottom margin (mb-8)

**Signature:**
```erb
<%# locals: (title:, subtitle: nil, size: "2xl") %>
```

**Example usage:**
```erb
<%= render "shared/page_header",
  title: "Episodes",
  subtitle: "Manage your podcast episodes"
%>
```

**After creating the partial, update these files:**
1. `app/views/episodes/new.html.erb` (line 2)
2. `app/views/settings/show.html.erb` (line 5)
3. `app/views/billing/show.html.erb` (line 5)
4. `app/views/pages/how_it_sounds.html.erb` (line 2)

**Note:** Do NOT update episodes/index.html.erb as it has a custom header with RSS feed display

---

### Task 3: Extract Inline SVG Icons

**Create:** `app/views/shared/icons/_upload.html.erb`

**Source:** `app/views/pages/home.html.erb:49-51`

**Content:**
```erb
<%# locals: (css_class: "size-8") %>
<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="<%= css_class %>">
  <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5" />
</svg>
```

**Update:** `app/views/pages/home.html.erb` line 48-52 to use:
```erb
<%= render "shared/icons/upload", css_class: "size-8" %>
```

---

**Create:** `app/views/shared/icons/_waveform.html.erb`

**Source:** `app/views/pages/home.html.erb:60-62`

**Content:**
```erb
<%# locals: (css_class: "size-8") %>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="<%= css_class %>">
  <path fill-rule="evenodd" d="M8.5 2a.5.5 0 0 1 .5.5v11a.5.5 0 0 1-1 0v-11a.5.5 0 0 1 .5-.5m-2 2a.5.5 0 0 1 .5.5v7a.5.5 0 0 1-1 0v-7a.5.5 0 0 1 .5-.5m4 0a.5.5 0 0 1 .5.5v7a.5.5 0 0 1-1 0v-7a.5.5 0 0 1 .5-.5m-6 1.5A.5.5 0 0 1 5 6v4a.5.5 0 0 1-1 0V6a.5.5 0 0 1 .5-.5m8 0a.5.5 0 0 1 .5.5v4a.5.5 0 0 1-1 0V6a.5.5 0 0 1 .5-.5m-10 1A.5.5 0 0 1 3 7v2a.5.5 0 0 1-1 0V7a.5.5 0 0 1 .5-.5m12 0a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0V7a.5.5 0 0 1 .5-.5"/>
</svg>
```

**Update:** `app/views/pages/home.html.erb` line 59-63 to use:
```erb
<%= render "shared/icons/waveform", css_class: "size-8" %>
```

---

## Testing Checklist

After implementation, verify:
- [ ] Audio players work on all pages (play/pause/seek)
- [ ] Page headers display with correct sizing
- [ ] Subtitle appears when provided
- [ ] Upload and waveform icons render correctly
- [ ] Icons match previous inline versions exactly
- [ ] No visual regressions on home page
- [ ] Run Rails tests: `rails test`

## Success Criteria
- 4 new partials created (1 audio player, 1 page header, 2 icons)
- 8 view files updated
- All audio player functionality preserved
- Icons follow existing pattern (accept css_class parameter)
- Tests passing
