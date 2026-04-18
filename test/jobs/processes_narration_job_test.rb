# frozen_string_literal: true

require "test_helper"

class ProcessesNarrationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Mocktail::DSL

  setup do
    @narration = narrations(:one)
    Mocktail.replace(ProcessesNarration)
  end

  teardown do
    Mocktail.reset
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessesNarrationJob) do
      ProcessesNarrationJob.perform_later(narration_id: @narration.id)
    end
  end

  test "delegates to ProcessesNarration service" do
    stubs { |m| ProcessesNarration.call(narration: m.any) }.with { nil }

    ProcessesNarrationJob.perform_now(narration_id: @narration.id)

    calls = Mocktail.calls(ProcessesNarration, :call)
    assert_equal 1, calls.size, "Expected ProcessesNarration.call to be called once"
  end
end
