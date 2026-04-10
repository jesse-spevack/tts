class AddMppPaymentToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_reference :episodes, :mpp_payment, null: true, foreign_key: true
  end
end
