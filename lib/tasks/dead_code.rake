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
  # Count includes both unused methods and unused constants.
  debride_baseline = 60

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
end
