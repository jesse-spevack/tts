class Current < ActiveSupport::CurrentAttributes
  attribute :session, :action_id
  delegate :user, to: :session, allow_nil: true

  def self.user_admin?
    user&.admin?
  end
end
