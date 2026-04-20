# frozen_string_literal: true

require "test_helper"
require "yaml"

# Assertions on config/deploy.yml that lock in the agent-team-tv6e fix:
# the prod deploy must NOT pin TEMPO_RPC_URL globally (AppConfig derives
# it from Rails.env so the mainnet/testnet pairing can't drift), but it
# MUST pin TEMPO_CURRENCY_TOKEN to the USDC.e mainnet address.
#
# These tests parse the YAML directly rather than booting Kamal, so they
# don't require any Kamal tooling to be installed in CI.
class DeployYmlTest < ActiveSupport::TestCase
  DEPLOY_YML_PATH = Rails.root.join("config/deploy.yml")
  USDC_E_CONTRACT = "0x20c000000000000000000000b9537d11c60e8b50"

  setup do
    @config = YAML.load_file(DEPLOY_YML_PATH, aliases: true)
  end

  test "config/deploy.yml parses as valid YAML" do
    assert_kind_of Hash, @config
  end

  test "prod clear env sets TEMPO_CURRENCY_TOKEN to the USDC.e mainnet address" do
    clear_env = @config.dig("env", "clear") || {}
    assert_equal USDC_E_CONTRACT, clear_env["TEMPO_CURRENCY_TOKEN"],
      "Prod must ship the USDC.e mainnet token address"
  end

  test "prod clear env does NOT set TEMPO_RPC_URL (agent-team-tv6e guard)" do
    # Hardcoding TEMPO_RPC_URL in env.clear is the exact footgun that
    # shipped a testnet RPC alongside a mainnet token. AppConfig::Mpp
    # derives the URL from Rails.env so prod can't drift.
    clear_env = @config.dig("env", "clear") || {}
    refute clear_env.key?("TEMPO_RPC_URL"),
      "TEMPO_RPC_URL must NOT be pinned in deploy.yml — AppConfig derives it from Rails.env"
  end

  test "prod clear env does not set TEMPO_RPC_URL in any other clear-env map either" do
    # Belt-and-suspenders: even if someone later adds a destination-specific
    # env.clear block, the rule is "never hardcode TEMPO_RPC_URL globally".
    each_clear_env(@config) do |clear_env, path|
      refute clear_env.key?("TEMPO_RPC_URL"),
        "Found TEMPO_RPC_URL under #{path} — must not be pinned in deploy.yml"
    end
  end

  private

  # Walk every Hash in the parsed YAML and yield any "clear" hash found
  # under an "env" key. Handles both top-level env and destination-specific
  # destinations.*.env shapes.
  def each_clear_env(config, path = "", &block)
    return unless config.is_a?(Hash)

    config.each do |key, value|
      current_path = path.empty? ? key.to_s : "#{path}.#{key}"
      if key == "env" && value.is_a?(Hash) && value["clear"].is_a?(Hash)
        yield value["clear"], "#{current_path}.clear"
      elsif value.is_a?(Hash)
        each_clear_env(value, current_path, &block)
      end
    end
  end
end
