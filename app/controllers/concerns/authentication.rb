module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :redirect_if_soft_deleted
    helper_method :authenticated?
  end

  class_methods do
    # Skips only the "must be authenticated" gate. Soft-delete redirection
    # still runs so an authenticated-but-deleted user with a stale cookie is
    # always pushed to the restore flow — even on actions that are otherwise
    # public. Use `allow_soft_deleted_access` to skip the soft-delete check.
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    def allow_soft_deleted_access(**options)
      skip_before_action :redirect_if_soft_deleted, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # When a session belongs to a soft-deleted user, push them to the restore
    # confirmation page instead of letting them into the app. Controllers that
    # participate in the revive flow (RestoreAccountsController,
    # SessionsController#destroy) opt out via `allow_soft_deleted_access`.
    def redirect_if_soft_deleted
      # Resolve the session here so the check works on allow_unauthenticated_access
      # actions too — those skip require_authentication, which means
      # Current.session wouldn't otherwise be populated before this filter runs.
      resume_session
      return unless Current.session
      return unless soft_deleted_session_user?

      redirect_to new_restore_account_path
    end

    # belongs_to :user on Session respects User.default_scope, so
    # `session.user` returns nil for soft-deleted users. Use an unscoped
    # lookup to detect the soft-deleted state explicitly.
    def soft_deleted_session_user?
      user = User.unscoped.find_by(id: Current.session.user_id)
      user&.deleted_at.present?
    end

    def find_session_by_cookie
      return nil unless cookies.signed[:session_id]

      session = Session.find_by(id: cookies.signed[:session_id])
      # A session whose user is entirely gone cannot resume. A soft-deleted
      # user's session IS honored just far enough for `redirect_if_soft_deleted`
      # to push them to the revive flow — that check uses an unscoped lookup.
      if session
        user_exists = User.unscoped.exists?(id: session.user_id)
        return nil unless user_exists
      end

      session
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to root_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || new_episode_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
