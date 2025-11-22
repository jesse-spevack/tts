# Misc items to brainstorm plans / implementation for

- [x] Logging audit - we should have just enough logging to make debugging simple.
    - Log inspection commands must be documented in a runbook
- [x] We need to completely re-design the layout and UX of the hub
- [x] We need realtime updates of the status, not just on page reload
- [ ] Harden magic link system, we should require re-login once a month. 
- [ ] Lint JS controllers
- [ ] env for development in hub
- [x] terms of service
- [ ] Auto-retry failed episodes when quota resets (wait 24hrs, retry automatically)
- [ ] File length validation before processing (prevent timeout on very long files)
- [ ] Unique error IDs for support tickets (e.g., ERR-2024-ABC123 for easier debugging)
- [ ] Add TTL to MP3s in GCS (retention policy for cost management)


