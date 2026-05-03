# frozen_string_literal: true

require "test_helper"

class WellKnownAssetlinksTest < ActionDispatch::IntegrationTest
  FINGERPRINT = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"

  teardown do
    ENV.delete("ANDROID_CERT_FINGERPRINTS")
  end

  test "returns assetlinks JSON with configured fingerprints" do
    ENV["ANDROID_CERT_FINGERPRINTS"] = FINGERPRINT

    get "/.well-known/assetlinks.json"

    assert_response :success
    json = JSON.parse(response.body)
    assert_kind_of Array, json
    entry = json.first
    assert_equal [ "delegate_permission/common.handle_all_urls" ], entry["relation"]
    assert_equal "android_app", entry["target"]["namespace"]
    assert_equal "app.podread.android", entry["target"]["package_name"]
    assert_equal [ FINGERPRINT ], entry["target"]["sha256_cert_fingerprints"]
  end

  test "returns valid JSON with empty fingerprints when env var unset" do
    ENV.delete("ANDROID_CERT_FINGERPRINTS")

    get "/.well-known/assetlinks.json"

    assert_response :success
    json = JSON.parse(response.body)
    entry = json.first
    assert_equal [], entry["target"]["sha256_cert_fingerprints"]
    assert_equal "app.podread.android", entry["target"]["package_name"]
  end

  test "responds with application/json content type" do
    get "/.well-known/assetlinks.json"

    assert_match %r{application/json}, response.content_type
  end
end
