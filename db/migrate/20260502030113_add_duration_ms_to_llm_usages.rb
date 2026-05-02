class AddDurationMsToLlmUsages < ActiveRecord::Migration[8.1]
  def change
    add_column :llm_usages, :duration_ms, :integer
  end
end
