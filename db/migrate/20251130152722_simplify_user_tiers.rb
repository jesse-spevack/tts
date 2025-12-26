class SimplifyUserTiers < ActiveRecord::Migration[8.1]
  def up
    # Map old tiers to new tiers:
    # basic(1), plus(2), premium(3) -> pro(1)
    # unlimited(4) -> unlimited(2)

    User.where(tier: [ 1, 2, 3 ]).update_all(tier: 1)  # -> pro
    User.where(tier: 4).update_all(tier: 2)          # -> unlimited
  end

  def down
    # Cannot safely reverse - would lose original tier info
    raise ActiveRecord::IrreversibleMigration
  end
end
