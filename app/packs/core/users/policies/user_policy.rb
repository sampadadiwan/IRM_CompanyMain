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
    user.id == record.id || (admin_of_records_company? && user.has_cached_role?(:company_admin)) || support?
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || support?
  end

  def new?
    user.has_cached_role?(:company_admin) || support?
  end

  def update?
    user.id == record.id ||
      (admin_of_records_company? && user.has_cached_role?(:company_admin)) || support?
  end

  # Whether the acting user is in the company the target user belongs to. For an advisor that is
  # their HOME (advisor_entity_id), not the client they happen to be switched into: judged by
  # users.entity_id, a client's company admin could edit a switched-in advisor's email or 2FA and
  # take over the account - and with it every other client of the advisor (R5). The advisor's own
  # firm's admins keep editing them wherever they are switched.
  # Worked example R5 — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def admin_of_records_company?
    return belongs_to_entity?(user, record) unless record.is_a?(User) && record.advisor_entity_id.present? &&
                                                   record.has_cached_role?(:investor_advisor)

    user.entity_id == record.advisor_entity_id ||
      (user.entity_type == "Group Company" && user.entity.child_ids.include?(record.advisor_entity_id))
  end

  def edit?
    update?
  end

  def destroy?
    # Only make user flag inactive, never destroy the user, else we loose associated data.
    false
  end

  # Who may mint a cross-region hand-off credential, and FOR WHICH region.
  #
  # This used to be `user.regions.present?` - "does the requester have any region access at
  # all" - and the controller then signed a credential for whatever `params[:site]` said. A
  # user whose profile listed only IN could therefore hand-craft `?site=US` and be signed in on
  # a region they have no access to. The requested destination is now the thing being
  # authorised, not just the requester.
  #
  # `site` is nil only when something calls the policy without a destination; that is not a
  # request we can authorise, so it is refused.
  def cross_site_link?(site: nil)
    code = SiteRegistry.normalize(site)
    return false if code.nil?

    record.switchable_region_codes.include?(code)
  end

  # Who may see the two-factor row on the user page (status + method badge). Widened from
  # "self only" so an administrator can see WHICH method a user is on before resetting it.
  def view_two_factor?
    user.id == record.id || (admin_of_records_company? && user.has_cached_role?(:company_admin)) || support?
  end

  # Changing an EXISTING mobile number (PhoneChangeStart / PhoneChangeConfirm). Whoever may
  # edit the user may start it; the emailed code to the user is what actually gates it.
  # A user with no number adds one from the edit form instead.
  def change_phone?
    record.phone.present? && update?
  end

  # Who may clear a user's two-factor METHOD back to "none" (TwoFactorReset). The user
  # themselves (they re-prove their password inside the operation), a company admin of the
  # same entity, or support. Only meaningful once a method has actually been chosen — before
  # that the user is already headed for the mode-selection screen, so the button is hidden.
  def reset_two_factor?
    return false unless record.two_factor_enabled? && record.two_factor_mode.present?

    user.id == record.id || (admin_of_records_company? && user.has_cached_role?(:company_admin)) || support?
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

    # R5: an advisor is mapped by their home company, not the client they are switched into, so
    # support for one client cannot impersonate the advisor and reach their other clients.
    mapped_entity_id = record.has_cached_role?(:investor_advisor) && record.advisor_entity_id.present? ? record.advisor_entity_id : record.entity_id
    mapping = SupportClientMapping.find_by(user_id: user.id, entity_id: mapped_entity_id, enabled: true)
    mapping&.allow_login_as(user.email) || false
  end
end
