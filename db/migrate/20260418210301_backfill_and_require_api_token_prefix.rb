class BackfillAndRequireApiTokenPrefix < ActiveRecord::Migration[8.1]
  # Hardens token_prefix from nullable to NOT NULL so downstream code
  # (Settings UI, structured logs) can treat it as a non-optional identifier.
  #
  # Any pre-existing row at this point dates to before 20260418201035 — those
  # are all extension-sourced tokens issued through the old pk_live_ flow,
  # so we backfill with a sentinel that preserves the prefix + marks the
  # random portion as unknown (we never stored the plaintext, so we can't
  # recover it). "pk_live_????" is 12 chars — matches the format of
  # newly-generated prefixes so UI display stays consistent.
  def up
    execute(<<~SQL.squish)
      UPDATE api_tokens
      SET token_prefix = 'pk_live_????'
      WHERE token_prefix IS NULL
    SQL
    change_column_null :api_tokens, :token_prefix, false
  end

  def down
    change_column_null :api_tokens, :token_prefix, true
    execute(<<~SQL.squish)
      UPDATE api_tokens
      SET token_prefix = NULL
      WHERE token_prefix = 'pk_live_????'
    SQL
  end
end
