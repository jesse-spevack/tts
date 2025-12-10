# frozen_string_literal: true

require "test_helper"

class EpisodeSourceTypeTest < ActiveSupport::TestCase
  test "source_type includes paste" do
    assert_includes Episode.source_types.keys, "paste"
  end

  test "paste source_type has integer value 2" do
    assert_equal 2, Episode.source_types["paste"]
  end
end
