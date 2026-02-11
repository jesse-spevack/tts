namespace :feeds do
  desc "Regenerate and upload RSS feed XML for all podcasts with complete episodes"
  task regenerate_all: :environment do
    podcasts = Podcast.joins(:episodes)
                      .where(episodes: { status: :complete, deleted_at: nil })
                      .distinct
    total = podcasts.count
    succeeded = 0
    failed = 0

    puts "Regenerating feeds for #{total} podcasts..."

    podcasts.find_each.with_index do |podcast, index|
      feed_xml = GeneratesRssFeed.call(podcast: podcast)
      CloudStorage.new(podcast_id: podcast.podcast_id)
                  .upload_content(content: feed_xml, remote_path: "feed.xml")

      succeeded += 1
      puts "[#{index + 1}/#{total}] #{podcast.podcast_id}: OK"
    rescue StandardError => e
      failed += 1
      puts "[#{index + 1}/#{total}] #{podcast.podcast_id}: FAILED - #{e.message}"
    end

    puts "\nDone! #{succeeded} succeeded, #{failed} failed (#{total} total)"
  end
end
