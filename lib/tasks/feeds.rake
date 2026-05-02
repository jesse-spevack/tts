namespace :feeds do
  desc "Regenerate and upload RSS feed XML for all podcasts with complete episodes"
  task regenerate_all: :environment do
    podcasts = Podcast.joins(:episodes)
                      .where(episodes: { status: :complete, deleted_at: nil })
                      .distinct
    total = podcasts.count
    succeeded = 0
    failed = 0

    log "Regenerating feeds for #{total} podcasts..."

    podcasts.find_each.with_index do |podcast, index|
      feed_xml = GeneratesRssFeed.call(podcast: podcast)
      CloudStorage.new(podcast_id: podcast.podcast_id)
                  .upload_content(content: feed_xml, remote_path: "feed.xml")

      succeeded += 1
      log "[#{index + 1}/#{total}] #{podcast.podcast_id}: OK"
    rescue StandardError => e
      failed += 1
      log "[#{index + 1}/#{total}] #{podcast.podcast_id}: FAILED - #{e.message}", level: :error
    end

    log "Done! #{succeeded} succeeded, #{failed} failed (#{total} total)"
  end

  desc "Send feed URL migration email to all users with active podcast feeds"
  task send_migration_emails: :environment do
    users = User.joins(podcasts: :episodes)
                .where(episodes: { status: :complete, deleted_at: nil })
                .distinct
    total = users.count
    succeeded = 0
    failed = 0

    log "Sending migration emails to #{total} users..."

    users.find_each.with_index do |user, index|
      unless user.podcasts.any?
        log "[#{index + 1}/#{total}] #{user.email_address}: SKIPPED - no podcast"
        next
      end

      UserMailer.feed_url_migration(user: user).deliver_now

      succeeded += 1
      log "[#{index + 1}/#{total}] #{user.email_address}: OK"
      sleep 0.1  # Rate limit outbound email
    rescue StandardError => e
      failed += 1
      log "[#{index + 1}/#{total}] #{user.email_address}: FAILED - #{e.message}", level: :error
    end

    log "Done! #{succeeded} succeeded, #{failed} failed (#{total} total)"
  end

  desc "Rewrite legacy verynormal-branded podcast titles and descriptions to PodRead defaults"
  task rebrand_verynormal_defaults: :environment do
    # Old defaults seeded by db/migrate/20251111064218_backfill_podcasts_for_existing_users.rb:
    #   title:       "<email>'s Very Normal Podcast"
    #   description: "My podcast created with tts.verynormal.dev"
    # Only rewrite rows whose fields still match those exact patterns; never
    # clobber a row a user has customized.
    #
    # Title format mirrors CreatesDefaultPodcast for new users:
    #   "PodRead Podcast: <email>"
    stale_title_pattern = "% Very Normal Podcast"
    stale_description = "My podcast created with tts.verynormal.dev"
    new_description = "My podcast created with #{AppConfig::Domain::HOST}"

    # Title rewrite is per-row because it interpolates the owning user's email.
    # N is small (handful of backfilled rows), so a find_each loop is fine.
    stale_title_scope = Podcast.where("title LIKE ?", stale_title_pattern)
    orphans = stale_title_scope.left_joins(:users).where(users: { id: nil })
    if orphans.exists?
      orphan_ids = orphans.pluck(:podcast_id)
      abort "ERROR: #{orphan_ids.length} podcast(s) match the stale title pattern but have no associated user; refusing to rewrite to a generic title. Orphan podcast_ids: #{orphan_ids.join(", ")}"
    end

    title_updates = 0
    stale_title_scope.includes(:users).find_each do |podcast|
      email = podcast.users.first&.email_address
      podcast.update!(title: "PodRead Podcast: #{email}")
      title_updates += 1
    end

    description_updates = Podcast.where(description: stale_description)
                                 .update_all(description: new_description)

    log "Rewrote #{title_updates} stale title(s) to \"PodRead Podcast: <email>\""
    log "Rewrote #{description_updates} stale description(s) to #{new_description.inspect}"
  end

  def log(message, level: :info)
    puts message
    Rails.logger.public_send(level, "[feeds] #{message}")
  end
end
