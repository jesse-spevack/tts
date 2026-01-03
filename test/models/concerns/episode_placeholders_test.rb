# frozen_string_literal: true

require "test_helper"

class EpisodePlaceholdersTest < ActiveSupport::TestCase
  test "TITLE constant is defined" do
    assert_equal "Processing...", EpisodePlaceholders::TITLE
  end

  test "AUTHOR constant is defined" do
    assert_equal "Processing...", EpisodePlaceholders::AUTHOR
  end

  test "description_for returns url description" do
    assert_equal "Processing article from URL...", EpisodePlaceholders.description_for(:url)
  end

  test "description_for returns paste description" do
    assert_equal "Processing pasted text...", EpisodePlaceholders.description_for(:paste)
  end

  test "description_for returns file description" do
    assert_equal "Processing uploaded file...", EpisodePlaceholders.description_for(:file)
  end

  test "description_for accepts string source type" do
    assert_equal "Processing article from URL...", EpisodePlaceholders.description_for("url")
  end

  test "description_for returns default for unknown type" do
    assert_equal "Processing...", EpisodePlaceholders.description_for(:unknown)
  end
end
