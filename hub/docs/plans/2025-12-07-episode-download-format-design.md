# Episode Downloads via Format Extension

## Summary

Replace the verb-style `/episodes/:id/download` route with a RESTful format extension: `/episodes/:id.mp3`. This treats the download as a different representation of the same resource rather than a separate action.

## Design

### Route Change

Remove the custom `download` member route:

```ruby
# Before
resources :episodes, only: [:index, :new, :create, :show] do
  member do
    get :download
  end
end

# After
resources :episodes, only: [:index, :new, :create, :show]
```

### Register MP3 MIME Type

Rails doesn't know `.mp3` by default. Register it:

```ruby
# config/initializers/mime_types.rb
Mime::Type.register "audio/mpeg", :mp3
```

### Controller Update

Modify `EpisodesController#show` to respond to both HTML and MP3 formats:

```ruby
def show
  @episode = Episode.find_by_prefix_id!(params[:id])
  raise ActiveRecord::RecordNotFound unless @episode.complete?

  respond_to do |format|
    format.html { @podcast = @episode.podcast }
    format.mp3 { redirect_to @episode.download_url, allow_other_host: true }
  end
end
```

### View Update

Change the download link in `app/views/episodes/show.html.erb`:

```erb
# Before
<%= link_to download_episode_path(@episode.prefix_id), ... %>

# After
<%= link_to episode_path(@episode.prefix_id, format: :mp3), ... %>
```

### Cleanup

- Remove the `download` action from `EpisodesController`
- Update tests that reference `download_episode_path` to use `episode_path(episode, format: :mp3)`

## Behavior

- `GET /episodes/ep_abc123` → HTML page with player
- `GET /episodes/ep_abc123.mp3` → Redirect to signed GCS URL with `Content-Disposition: attachment`
- Both remain public (no authentication required), consistent with current behavior

## Files to Modify

1. `config/initializers/mime_types.rb` (create)
2. `config/routes.rb`
3. `app/controllers/episodes_controller.rb`
4. `app/views/episodes/show.html.erb`
5. `test/controllers/episodes_controller_test.rb`
