require "open3"

namespace :code_quality do
  # Dead code detection via debride.
  #
  # This uses a RATCHET approach: we capture the current number of findings
  # as a baseline, and fail only if the count increases above that baseline.
  # This blocks new dead code from landing without forcing us to triage the
  # entire backlog of pre-existing findings in one commit.
  #
  # Adjustments to the baseline:
  #   - If you delete dead code (or rename a method so debride sees it used),
  #     the count may drop. When that happens, lower debride_baseline to the
  #     new count so the ratchet stays tight. The CI step below prints the
  #     current count on every run to make this easy.
  #   - If you legitimately add a new method that debride can't prove is
  #     reached (e.g. a controller action, a callback, a dynamically-included
  #     concern method), add it to `.debride_whitelist` with a comment
  #     explaining why — don't raise the baseline.
  #
  # Baseline captured 2026-04-14 after initial install (`--rails` + whitelist).
  # Updated 2026-04-14 after removing Tts::Config attr_accessor writers and
  # CloudStorage#upload_staging_file (both confirmed dead by grep).
  # Updated 2026-04-17 after installing debride-erb, which makes ERB helper
  # calls visible to debride (EpisodesHelper, UiHelper, etc. no longer false
  # positives).
  # Updated 2026-04-17 after removing Result#flash_type, LlmUsage#cost_dollars,
  # and ValidatesPrice.subscription? (all only referenced by their own tests).
  # Updated 2026-04-18 (+3) for MPP additions: Api::V1::NarrationsController#show,
  # CleanupStaleMppPaymentsJob#perform, ProcessesNarrationJob#perform. All three
  # are Rails-invoked (routing + Active Job) — same category as existing entries
  # already counted in the baseline (e.g. ProcessesUrlEpisodeJob#perform).
  # Updated 2026-04-18 (+1) for DocsController#mpp. Rails-invoked via routing.
  # Updated 2026-04-18 (+2) for Settings::ApiTokensController#index and
  # Settings::ApiTokensController#reveal. Both Rails-invoked via routing —
  # same category as existing controller actions already in the baseline
  # (Settings::ExtensionsController#show, SettingsController#show, etc.).
  # Updated 2026-04-19 after whitelisting `perform` (ActiveJob convention —
  # the queue executor calls perform after perform_later, invisible to debride).
  # Retiring the individual ActiveJob#perform ratchet entries above, since
  # all of them are now covered categorically by the whitelist.
  # Count includes both unused methods and unused constants.
  debride_baseline = 53

  desc "Run debride (ratchet: fails if findings > baseline #{debride_baseline})"
  task :debride do
    cmd = %w[bundle exec debride --rails --whitelist .debride_whitelist app/ lib/]
    output, status = Open3.capture2e(*cmd)

    # If debride itself crashed (non-zero exit), fail loudly rather than
    # computing a "0 findings" false pass from an error dump.
    unless status.success?
      puts output
      puts "---"
      puts "FAIL: debride exited with status #{status.exitstatus}."
      puts "Fix the debride invocation or report upstream — do not edit the ratchet."
      exit 1
    end

    # Findings have the form "  method_name    path/to/file.rb:LINE (LOC)"
    # — two leading spaces, identifier start, and a trailing "(N)" LOC count.
    # Anchoring on the trailing `(N)` rejects stray stack-trace / banner
    # lines that happen to start with two spaces.
    count = output.lines.count { |l| l =~ /^  [A-Za-z_][\w?!=]*\s+\S+:\d+.*\(\d+\)\s*$/ }

    # Sanity guard: debride prints a banner and a "Total suspect LOC: N"
    # footer even when there are zero findings. If the output is substantial
    # but our regex matched zero lines, the format probably changed — treat
    # that as a parser regression, not a clean run.
    if count.zero? && output.lines.count > 5
      puts output
      puts "---"
      puts "FAIL: debride produced output but no finding lines matched the parser."
      puts "The output format may have changed. Update the regex in"
      puts "lib/tasks/dead_code.rake and re-run."
      exit 1
    end

    puts output
    puts "---"
    puts "Debride findings: #{count} (baseline: #{debride_baseline})"

    if count > debride_baseline
      puts "FAIL: debride findings (#{count}) exceed baseline (#{debride_baseline})."
      puts "Either remove the new dead code, wire it up, or add a whitelist"
      puts "entry in .debride_whitelist with a comment explaining why."
      exit 1
    elsif count < debride_baseline
      puts "NOTE: debride findings (#{count}) are below baseline (#{debride_baseline})."
      puts "Consider lowering debride_baseline in lib/tasks/dead_code.rake to #{count}"
      puts "to keep the ratchet tight."
    else
      puts "OK: debride findings at baseline."
    end
  end

  # Unused Rails view partial detection via CodeQuality::UnusedPartials.
  #
  # Same RATCHET approach as :debride above — capture current unused count as
  # a baseline, fail only if the count grows. Prevents agents/humans from
  # accreting new orphan partials while the existing ones get cleaned up over
  # time.
  #
  # Adjustments to the baseline:
  #   - If you delete an unused partial, the count drops. Lower
  #     partial_baseline to the new count so the ratchet stays tight.
  #   - If a partial is genuinely used but the detector can't see it (e.g.
  #     rendered via a gem's generator, pulled in by a JS component, or
  #     named dynamically beyond a simple `"prefix/#{var}"` pattern), add its
  #     render-form name to `.partial_whitelist` with a comment explaining
  #     why — don't raise the baseline.
  #
  # Baseline captured 2026-04-17 after initial detector implementation and
  # cleanup of 36 truly-unused partials (ported marketing-kit UI components
  # with zero call sites in templates, Ruby, routes, or docs).
  partial_baseline = 0

  desc "Detect unused view partials (ratchet: fails if count > baseline #{partial_baseline})"
  # Depends on :environment (unlike :debride above) because this task calls
  # CodeQuality::UnusedPartials directly in-process. The class lives under
  # `lib/code_quality/` and is picked up by `config.autoload_lib`, which
  # requires Rails to be booted. The :debride task shells out to the debride
  # binary via Open3 and so needs no Rails env.
  task unused_partials: :environment do
    views_root = Rails.root.join("app/views").to_s
    source_roots = [
      views_root,
      Rails.root.join("app/models").to_s,
      Rails.root.join("app/controllers").to_s,
      Rails.root.join("app/helpers").to_s,
      Rails.root.join("app/jobs").to_s,
      Rails.root.join("app/mailers").to_s,
      Rails.root.join("app/channels").to_s,
      Rails.root.join("app/services").to_s,
      Rails.root.join("lib").to_s
    ]

    # Crash guard: the detector is pure Ruby (no subprocess), so "crash"
    # means an exception. Rescue at the top level so a regex bug or
    # file-system hiccup fails loudly rather than computing a bogus 0.
    begin
      result = CodeQuality::UnusedPartials.new(
        views_root: views_root,
        source_roots: source_roots
      ).call
    rescue => e
      puts "---"
      puts "FAIL: CodeQuality::UnusedPartials raised #{e.class}: #{e.message}"
      puts e.backtrace.first(10).join("\n")
      puts "Fix the detector or report upstream — do not edit the ratchet."
      exit 1
    end

    whitelist_path = Rails.root.join(".partial_whitelist")
    whitelist = if File.exist?(whitelist_path)
      File.readlines(whitelist_path).map { |l| l.sub(/#.*/, "").strip }.reject(&:empty?).to_set
    else
      Set.new
    end

    unused = result[:unused].reject { |name| whitelist.include?(name) }
    count = unused.length

    # Parser-regression guard: if the views tree has partials but the detector
    # reports a total of 0, enumeration is broken — fail loudly.
    if result[:total].zero? && Dir.glob(File.join(views_root, "**", "_*.html.erb")).any?
      puts "---"
      puts "FAIL: detector reported 0 partials but app/views has _*.html.erb files."
      puts "The enumeration logic may be broken. Inspect lib/code_quality/unused_partials.rb."
      exit 1
    end

    puts "Total partials:    #{result[:total]}"
    puts "Referenced:        #{result[:referenced]}"
    puts "Unused:            #{count}"
    unless unused.empty?
      puts
      puts "Unused partials:"
      unused.each { |p| puts "  #{p}" }
    end

    puts "---"
    puts "Unused partials: #{count} (baseline: #{partial_baseline})"

    if count > partial_baseline
      puts "FAIL: unused partial count (#{count}) exceeds baseline (#{partial_baseline})."
      puts "Either delete the new orphan partial, wire it up, or add an entry to"
      puts ".partial_whitelist with a comment explaining why the detector can't see it."
      exit 1
    elsif count < partial_baseline
      puts "NOTE: unused partial count (#{count}) is below baseline (#{partial_baseline})."
      puts "Consider lowering partial_baseline in lib/tasks/dead_code.rake to #{count}"
      puts "to keep the ratchet tight."
    else
      puts "OK: unused partial count at baseline."
    end
  end
end
