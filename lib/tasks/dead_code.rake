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
  # Count includes both unused methods and unused constants.
  debride_baseline = 85

  desc "Run debride (ratchet: fails if findings > baseline #{debride_baseline})"
  task :debride do
    cmd = %w[bundle exec debride --rails --whitelist .debride_whitelist app/ lib/]
    output = IO.popen(cmd, err: [ :child, :out ], &:read)

    # Findings are lines of the form "  method_name    path/to/file.rb:N (K)".
    # Group headers are flush-left; method lines have leading whitespace plus
    # a lowercase identifier or operator.
    count = output.lines.count { |l| l =~ /^  [A-Za-z_]/ }

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
