# frozen_string_literal: true

require "test_helper"
require "rake"
require "tmpdir"
require "fileutils"

# Tests for the `code_quality:synthesizable_content_purity` rake task
# (agent-team-bzo6, epic agent-team-sird). The task fails if
# app/models/concerns/synthesizable_content.rb references any symbol
# from the hard no-go list defined in the epic:
#
#   request, params, current_user, Rails.application.routes,
#   ActionMailer, deliver_, .deliver_later
#
# The task accepts a PATH env var so tests can point it at a temp file
# rather than the real concern. This keeps the test hermetic and lets
# us write a small synthetic fixture per case.
#
# All tests MUST fail until the task is created. Acceptable failure:
# RuntimeError: Don't know how to build task 'code_quality:synthesizable_content_purity'
class SynthesizableContentPurityRakeTest < ActiveSupport::TestCase
  TASK_NAME = "code_quality:synthesizable_content_purity"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    @tmpdir = Dir.mktmpdir("synthesizable_purity_test")
    @concern_path = File.join(@tmpdir, "synthesizable_content.rb")
  end

  teardown do
    Rake::Task[TASK_NAME].reenable if Rake::Task.task_defined?(TASK_NAME)
    ENV.delete("PATH_OVERRIDE")
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  # Run the task against a temp concern file whose contents are given.
  def invoke_against(contents)
    File.write(@concern_path, contents)
    ENV["PATH_OVERRIDE"] = @concern_path
    capture_io { Rake::Task[TASK_NAME].invoke }
  end

  def assert_fails_with_banned(contents, banned_symbol)
    error = assert_raises(SystemExit) do
      invoke_against(contents)
    end
    assert_equal 1, error.status,
      "task must exit 1 when banned symbol `#{banned_symbol}` appears"
  end

  def assert_passes(contents)
    output, = invoke_against(contents)
    assert_match(/OK|pure|clean|no.*banned/i, output,
      "task must print a pass signal for clean concern")
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  test "passes for a clean concern with none of the banned symbols" do
    assert_passes <<~RUBY
      module SynthesizableContent
        extend ActiveSupport::Concern

        def source_text
          self[:source_text]
        end

        def status
          self[:status]
        end
      end
    RUBY
  end

  # ---------------------------------------------------------------------------
  # Each banned symbol fails the guard (one test per symbol keeps
  # diagnostic output precise when the task regresses).
  # ---------------------------------------------------------------------------

  test "fails when concern references `request`" do
    assert_fails_with_banned(<<~RUBY, "request")
      module SynthesizableContent
        def something
          request.remote_ip
        end
      end
    RUBY
  end

  test "fails when concern references `params`" do
    assert_fails_with_banned(<<~RUBY, "params")
      module SynthesizableContent
        def something
          params[:voice]
        end
      end
    RUBY
  end

  test "fails when concern references `current_user`" do
    assert_fails_with_banned(<<~RUBY, "current_user")
      module SynthesizableContent
        def owner?
          current_user == user
        end
      end
    RUBY
  end

  test "fails when concern references `Rails.application.routes`" do
    assert_fails_with_banned(<<~RUBY, "Rails.application.routes")
      module SynthesizableContent
        def url
          Rails.application.routes.url_helpers.episode_url(self)
        end
      end
    RUBY
  end

  test "fails when concern references `ActionMailer`" do
    assert_fails_with_banned(<<~RUBY, "ActionMailer")
      module SynthesizableContent
        def notify
          ActionMailer::Base.default_url_options
        end
      end
    RUBY
  end

  test "fails when concern references `deliver_` (underscore form)" do
    assert_fails_with_banned(<<~RUBY, "deliver_")
      module SynthesizableContent
        def notify
          SomeMailer.welcome(self).deliver_now
        end
      end
    RUBY
  end

  test "fails when concern references `.deliver_later`" do
    assert_fails_with_banned(<<~RUBY, ".deliver_later")
      module SynthesizableContent
        def notify_async
          SomeMailer.welcome(self).deliver_later
        end
      end
    RUBY
  end

  # The epic's no-go list includes "User / auth / ownership (Episode-specific,
  # not content-specific)". The original guard missed `user` — the review
  # caught a `user&.voice` fallback that slipped through. These tests pin the
  # widened banned list.

  test "fails when concern references bare `user` (association/method)" do
    assert_fails_with_banned(<<~RUBY, "user")
      module SynthesizableContent
        def fallback_voice
          self[:voice] || user&.voice
        end
      end
    RUBY
  end

  test "fails when concern references `belongs_to :user`" do
    assert_fails_with_banned(<<~RUBY, "belongs_to :user")
      module SynthesizableContent
        extend ActiveSupport::Concern

        included do
          belongs_to :user
        end
      end
    RUBY
  end

  test "fails when concern references `user_id`" do
    assert_fails_with_banned(<<~RUBY, "user_id")
      module SynthesizableContent
        def owner_id
          user_id
        end
      end
    RUBY
  end

  test "allows the word `user` inside comments (doc-only mention is fine)" do
    # Discussing user/auth concepts in doc comments is necessary to explain
    # why they're banned. Only executable code should trip the guard.
    assert_passes <<~RUBY
      # The concern deliberately does NOT provide a user-based fallback.
      # See epic agent-team-sird no-go list (no user/auth/ownership).
      module SynthesizableContent
        def source_text
          self[:source_text]
        end
      end
    RUBY
  end

  # ---------------------------------------------------------------------------
  # Path resolution
  # ---------------------------------------------------------------------------

  test "defaults to app/models/concerns/synthesizable_content.rb when PATH_OVERRIDE is absent" do
    # Without PATH_OVERRIDE, the task should look at the real concern path.
    # Until Implementer creates the file, that path doesn't exist and the
    # task should fail loudly (exit 1) rather than silently passing.
    ENV.delete("PATH_OVERRIDE")

    # Make sure the real concern file does NOT exist yet. If it does
    # (Implementer landed ahead of us), skip — this test is only
    # meaningful in the pre-implementation window.
    real_path = Rails.root.join("app/models/concerns/synthesizable_content.rb")
    skip "Implementer has landed the concern; default-path guard no longer applies" if File.exist?(real_path)

    error = assert_raises(SystemExit) do
      capture_io { Rake::Task[TASK_NAME].invoke }
    end
    assert_equal 1, error.status,
      "task must exit 1 when the concern file is missing"
  end
end
