# Misc items to brainstorm plans / implementation for

- [ ] Harden magic link system, we should require re-login once a month. 
- [ ] Lint JS controllers
- [ ] env for development in hub
- [ ] Unique error IDs for support tickets (e.g., ERR-2024-ABC123 for easier debugging)
- [ ] Add TTL to MP3s in GCS (retention policy for cost management)
- [ ] Audit codebase for unused method arguments (RuboCop doesn't catch args stored but never read)
- [ ] De-duplicate shared code between hub/ and lib/ (EpisodeManifest, RSSGenerator, GCSUploader). Options: move lib/ into hub, extract to shared private gem, or use symlinks
- [ ] Consider splitting GcsUploader into staging vs podcast content responsibilities during de-duplication



