# frozen_string_literal: true

# Fail-fast boot check for the Tempo RPC chain-id (agent-team-tv6e).
# Ensures TEMPO_RPC_URL and TEMPO_CURRENCY_TOKEN can't silently drift to
# different chains — that class of misconfiguration strands user payments.
#
# Gate logic lives on Mpp::VerifiesChainId.should_run? so it's unit-testable
# without re-booting Rails. Summary:
#  - Production: on by default.
#  - Non-prod envs: off unless MPP_CHAINID_GUARD=1 is set (opt-in).
#  - Any env: TEMPO_SKIP_CHAINID_GUARD=1 disables (emergency only in prod).
#  - Rake tasks (asset precompile in the Docker build, migrations, etc.)
#    are always skipped — they don't need network access to Tempo.

Rails.application.config.after_initialize do
  next unless Mpp::VerifiesChainId.should_run?

  result = Mpp::VerifiesChainId.call

  if result.success?
    Rails.logger.info(
      "[mpp] chain-id guard OK: #{result.data[:rpc_url]} reports chain #{result.data[:chain_id]}"
    )
  else
    raise "MPP chain-id guard failed — refusing to boot. #{result.error} " \
          "Set TEMPO_SKIP_CHAINID_GUARD=1 to bypass (emergency only)."
  end
end
