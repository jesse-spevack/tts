namespace :code_quality do
  # Purity guard for app/models/concerns/synthesizable_content.rb.
  # The concern must not grow HTTP, auth, mailer, or routing concerns —
  # those are caller-specific and don't belong in a content-model mixin.
  # See epic agent-team-sird for the no-go rationale.
  #
  # Usage:
  #   bin/rails code_quality:synthesizable_content_purity
  #   bin/rails code_quality:synthesizable_content_purity PATH_OVERRIDE=/tmp/foo.rb
  desc "Fail if synthesizable_content.rb references banned HTTP/auth/mailer symbols"
  task :synthesizable_content_purity do
    banned = [
      [ "Rails.application.routes", /\bRails\.application\.routes\b/ ],
      [ "ActionMailer", /\bActionMailer\b/ ],
      [ ".deliver_later", /\.deliver_later\b/ ],
      [ "deliver_", /\bdeliver_\w+/ ],
      [ "current_user", /\bcurrent_user\b/ ],
      [ "request", /\brequest\b/ ],
      [ "params", /\bparams\b/ ],
      # User / auth / ownership — Episode-specific, not content-specific
      # (per epic agent-team-sird no-go list). Widened after
      # agent-team-bzo6 review found `user&.voice` fallback slipped past
      # the original list. More-specific patterns listed first so the
      # violation name reported is the most informative one.
      [ "belongs_to :user", /\bbelongs_to\s+:user\b/ ],
      [ "user_id", /\buser_id\b/ ],
      [ "user", /\buser\b/ ]
    ]

    path = ENV["PATH_OVERRIDE"].presence || "app/models/concerns/synthesizable_content.rb"

    unless File.exist?(path)
      puts "FAIL: concern file not found at #{path}"
      exit 1
    end

    contents = File.read(path)
    # Strip comments so we only match against executable code — discussion
    # of banned concepts in doc comments is fine (and necessary to explain
    # why the ban exists). Removes whole-line `# ...` comments and trailing
    # `... # ...` comments; good enough for the concern file's structure.
    code = contents.lines.map { |line| line.sub(/(?<!\\)#.*$/, "") }.join
    violations = banned.filter_map { |name, pattern| name if code.match?(pattern) }

    if violations.any?
      puts "FAIL: #{path} references banned symbols: #{violations.join(', ')}"
      exit 1
    end

    puts "OK: #{path} is pure — no banned symbols."
  end
end
