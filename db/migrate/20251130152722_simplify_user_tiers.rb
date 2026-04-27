class SimplifyUserTiers < ActiveRecord::Migration[8.1]
  # Anonymous AR class scoped to the users table. Avoids loading the live User
  # model, which declares enums/validations against columns added by later
  # migrations (e.g. account_type) and fails to load at this point in history.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    # Map old tiers to new tiers:
    # basic(1), plus(2), premium(3) -> pro(1)
    # unlimited(4) -> unlimited(2)

    MigrationUser.where(tier: [ 1, 2, 3 ]).update_all(tier: 1)  # -> pro
    MigrationUser.where(tier: 4).update_all(tier: 2)          # -> unlimited
  end

  def down
    # Cannot safely reverse - would lose original tier info
    raise ActiveRecord::IrreversibleMigration
  end
end
