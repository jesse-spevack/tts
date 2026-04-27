# frozen_string_literal: true

# Fail-fast boot check that TEMPO_RPC_URL and TEMPO_CURRENCY_TOKEN target
# the same chain. Mismatch silently strands payments.
#
# Gate logic on Mpp::VerifiesChainId.should_run? for unit-testability.
# Failure policy: confirmed mismatch always aborts boot; transient network
# errors fail-open (boot + WARN). Rationale for fail-open over retry: a
# real outage outlasts any reasonable backoff and retries amplify load on
# an already-struggling upstream. Static config drift is what this guard
# catches; dynamic outages surface in the 402 verification path's metrics.

Rails.application.config.after_initialize do
  if Mpp::VerifiesChainId.bypassed?
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
    Rails.logger.warn(
      "[mpp] chain-id guard FAIL-OPEN (transient): #{result.error}. " \
      "Booting without verification — investigate if this persists across boots."
    )
  else
    raise "MPP chain-id guard failed — refusing to boot. #{result.error} " \
          "Set TEMPO_SKIP_CHAINID_GUARD=1 to bypass (emergency only)."
  end
end
