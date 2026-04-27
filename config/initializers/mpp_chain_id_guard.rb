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
#
# Failure policy (agent-team-vo2c): a confirmed chain-ID mismatch ALWAYS
# fails boot. Transient network failures (timeouts, DNS, connection reset)
# fail-open with a loud WARN log so a momentary Tempo 503 during a Kamal
# rolling deploy doesn't wedge the deploy and tempt operators to set
# TEMPO_SKIP_CHAINID_GUARD=1 permanently. Rationale: a fail-open on no
# signal beats retry-with-backoff because retries still wedge if the
# outage lasts longer than a few seconds, and they amplify load against
# an already-struggling RPC. The guard's job is to catch a STATIC mis-
# configuration; for dynamic outages we trust monitoring on the actual
# 402 verification path.

Rails.application.config.after_initialize do
  if Mpp::VerifiesChainId.bypassed?
    # Bypass should leave a trail. A silent skip post-incident is exactly
    # how this env var ends up permanently set in prod.
    Rails.logger.warn(
      "[mpp] chain-id guard BYPASSED via TEMPO_SKIP_CHAINID_GUARD=1 — " \
      "this should be temporary. Unset to re-enable the guard."
    )
  end

  next unless Mpp::VerifiesChainId.should_run?

  result = Mpp::VerifiesChainId.call

  if result.success?
    Rails.logger.info(
      "[mpp] chain-id guard OK: #{result.data[:rpc_url]} reports chain #{result.data[:chain_id]}"
    )
  elsif result.code == :transient
    # Network glitch, not a confirmed mismatch. Boot, but make it loud.
    Rails.logger.warn(
      "[mpp] chain-id guard FAIL-OPEN (transient): #{result.error}. " \
      "Booting without verification — investigate if this persists across boots."
    )
  else
    raise "MPP chain-id guard failed — refusing to boot. #{result.error} " \
          "Set TEMPO_SKIP_CHAINID_GUARD=1 to bypass (emergency only)."
  end
end
