class UserPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    !user.investor_advisor?
  end

  def welcome?
    true
  end

  def chat?
    user.enable_user_llm_chat
  end

  def whatsapp_webhook?
    true
  end

  def search_by_email?
    true
  end

  def show?
    user.id == record.id || (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || support?
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || support?
  end

  def new?
    user.has_cached_role?(:company_admin) || support?
  end

  def update?
    user.id == record.id ||
      create? || support?
  end

  def edit?
    update?
  end

  def destroy?
    # Only make user flag inactive, never destroy the user, else we loose associated data.
    false
  end

  def cross_site_link?
    user.regions.present?
  end

  # Who may see the two-factor row on the user page (status + method badge). Widened from
  # "self only" so an administrator can see WHICH method a user is on before resetting it.
  def view_two_factor?
    user.id == record.id || (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || support?
  end

  # Who may clear a user's two-factor METHOD back to "none" (TwoFactorReset). The user
  # themselves (they re-prove their password inside the operation), a company admin of the
  # same entity, or support. Only meaningful once a method has actually been chosen — before
  # that the user is already headed for the mode-selection screen, so the button is hidden.
  def reset_two_factor?
    return false unless record.two_factor_enabled? && record.two_factor_mode.present?

    user.id == record.id || (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || support?
  end

  # Authorizes admin/support impersonation ("login as"). The acting user (`user`) may impersonate
  # the target (`record`) only if:
  #   1. they hold the :support or :super role, AND
  #   2. they hold an enabled SupportClientMapping for the target's entity whose login-as
  #      whitelist includes their OWN email (allow_login_as checks the support user's email).
  # This is enforced server-side against the authenticated acting user, which is why the new
  # login_as flow cannot be redeemed by an anonymous party holding a leaked URL (unlike the old
  # signed-link flow — see UsersController#login_as and docs/security/security_review_2026_07.md H2).
  def login_as?
    return false unless user.has_cached_role?(:support) || user.has_cached_role?(:super)

    mapping = SupportClientMapping.find_by(user_id: user.id, entity_id: record.entity_id, enabled: true)
    mapping&.allow_login_as(user.email) || false
  end
end
