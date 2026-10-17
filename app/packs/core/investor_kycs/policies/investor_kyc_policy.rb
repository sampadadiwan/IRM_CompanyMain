class InvestorKycPolicy < ApplicationPolicy
  include WorkflowablePolicyMethods # journey?, assign_workflow?

  class Scope < Scope
    def resolve
      if user.investor_advisor? && user.curr_role == "investor"
        scope.for_investor_advisor(user)
      elsif user.curr_role == "investor"
        # Give access to all the KYCs for the investor, where he has investor_accesses approved
        scope.for_investor(user)
      elsif user.entity_type == "Group Company" || user.has_cached_role?(:company_admin)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee)
        # enable_kycs is the one condition every staff path needs (V6) - without it the
        # employee sees no KYCs at all, whatever else they hold.
        return scope.none unless user.enable_kycs

        # get_extended_permissions, not extended_permissions: for an advisor switched into this
        # entity it reads their grant's toggles, which is what applies to them here.
        InvestorKycPolicy.staff_visible_kycs(scope, entity_id: user.entity_id, user_id: user.id,
                                                    extended_permissions: user.get_extended_permissions)
      else
        scope.none
      end
    end
  end

  # The KYC visibility rule for an entity's own staff - its employees, and investor advisors
  # acting through a staff grant on it. One rule for the KYC list (Scope above), the KYC page
  # (show?) and the KYC notification emails (InvestorKyc#notify_kyc gates on show?), so nobody is
  # emailed a KYC they cannot open, and nobody can open a KYC their list hides.
  # Worked examples V1-V11: openspec/changes/kyc-advisor-notification-delivery-fix/design.md#worked-examples
  #
  # Takes the entity, user and toggles explicitly (rather than reading them off a user) because a
  # switched-out advisor is checked against their grant on the KYC's entity, not against whatever
  # entity and persona they are currently in.
  def self.staff_visible_kycs(scope, entity_id:, user_id:, extended_permissions:)
    kycs = scope.where(entity_id:)

    # Investor Kyc Read or Investor Kyc Update: every KYC in the entity, whatever the fund (V1, V2).
    # Before this rule these toggles only applied on top of fund access, so on their own they
    # showed nothing.
    return kycs if extended_permissions.set?(:investor_kyc_read) || extended_permissions.set?(:investor_kyc_update)

    # Otherwise: only KYCs committed to a fund the user holds an access right on (V3, V4). A KYC
    # with no commitment yet has no fund to check, so it stays hidden here (V5) - only the toggles
    # above (or company admin) reveal it, and so only those users get its emails. Subquery rather
    # than a join, so a KYC with several commitments is not returned once per commitment.
    my_fund_ids = AccessRight.where(entity_id:, user_id:, owner_type: "Fund").select(:owner_id)
    on_my_funds = CapitalCommitment.where(entity_id:, fund_id: my_fund_ids).select(:investor_kyc_id)

    kycs.where(id: on_my_funds)
  end

  def index?
    user.enable_kycs
  end

  def analytics?
    index?
  end

  def bulk_actions?
    index?
  end

  # Each path below is additive (return true if ...), never an exclusive elsif: failing one path
  # must not stop a user who qualifies by another, e.g. a fund-of-funds LP whose users carry the
  # :employee role still reaches the investor-owns-this-KYC check at the end (V10).
  def show?(across_all_entities: false)
    # 1. The entity's own staff, while in it: the KYC must be in their KYC list (Scope), which is
    #    where staff_visible_kycs is applied - so the page and the list can never disagree.
    return true if entity_staff_can_see?

    # 2. A staff grant on the KYC's entity, judged by the grant itself - covers an advisor who is
    #    switched out of the entity, which is what lets their KYC emails reach them (V7, V8, V9).
    return true if advisor_grant_can_see?

    # 3. Pre-existing investor-side paths, unchanged.
    if user.has_cached_role?(:investor_advisor)
      InvestorKyc.for_investor_advisor(user, across_all_entities:).exists?(id: record.id) ||
        # At home an advisor is also a plain investor: their OWN investor's KYC opens exactly as it
        # does for any other contact (the KYC list, Scope above, already shows it). for_investor_advisor
        # only reaches a KYC through a commitment on a permissioned fund, so a KYC with no
        # commitment yet was denied, and its KYC-form email skipped them.
        # Worked example E15 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
        (advisor_at_home? && user.entity_id == record.investor&.investor_entity_id)
    else
      # Investor viewing their own KYC.
      user.entity_id == record.investor&.investor_entity_id
    end
  end

  def create?(emp_perm = :investor_kyc_create)
    permissioned_employee?(emp_perm) || investor_owns_kyc?
  end

  # The investor-side "it's our own KYC" test behind create? / update? / edit? / extract_docs_data? /
  # send_notification?. For an advisor switched into a client, a KYC already committed to funds
  # follows the same rule as show? (InvestorKyc.for_investor_advisor: a commitment in a fund they
  # were granted), so they can no longer edit a client KYC tied only to funds they were NOT given
  # (B4-2). A KYC with no commitment yet is the client's onboarding, which the advisor may fill in
  # (the doc-first wizard saves, then continues on edit) (B4-2-H). Plain investors, advisors at
  # home and magic links (signed_id_access?) are unchanged.
  # Worked examples B4-2, B4-2-H — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
  def investor_owns_kyc?
    return false unless user.entity_id == record.investor&.investor_entity_id
    return true unless user.has_cached_role?(:investor_advisor) && !advisor_at_home? && record.persisted?
    # Onboarding: nothing committed yet, so no fund grant to judge it by.
    return true if record.capital_commitments.none?

    InvestorKyc.for_investor_advisor(user).exists?(id: record.id)
  end

  def generate_docs?
    permissioned_employee?(:investor_kyc_update)
  end

  def new?
    create?
  end

  def toggle_verified?
    permissioned_employee?(:investor_kyc_approve)
  end

  def send_kyc_reminder?
    permissioned_employee?
  end

  def notify_kyc_required?
    permissioned_employee?
  end

  def send_kyc_reminder_to_all?
    user.enable_kycs && user.curr_role == "employee"
  end

  def import?
    user.enable_kycs && user.curr_role == "employee"
  end

  def ckyc_or_kra_enabled?
    record.entity.ckyc_or_kra_enabled?
  end

  def generate_new_aml_report?
    toggle_verified? && user.entity.entity_setting.aml_enabled
  end

  def override_aml_status?
    toggle_verified? && user.entity.entity_setting.aml_enabled
  end

  def assign_kyc_data?
    create?(:investor_kyc_update)
  end

  def compare_kyc_datas?
    create?(:investor_kyc_update)
  end

  def create_and_send_kyc_to_investor?
    create?(:investor_kyc_create)
  end

  def generate_new_kyc_data?
    create?(:investor_kyc_update)
  end

  def extract_docs_data?
    # Investor filling their own KYC via magic link or logged-in investor, plus fund employees
    return true if signed_id_access?

    create?(:investor_kyc_update) || investor_owns_kyc?
  end

  def download_kra_data?
    create?(:investor_kyc_update) && record.entity.permissions.enable_kra?
  end

  def fetch_ckyc_data?
    create?(:investor_kyc_update) && record.entity.permissions.enable_ckyc?
  end

  def update?
    return true if signed_id_investor?

    (create?(:investor_kyc_update) || support?) && !record.verified
  end

  # Used to send notification to fund that kyc needs updates
  def send_notification?
    # the user should see the updates requires button when the record is verified (synched with submission_verified) or submission completed
    investor_owns_kyc? && (record.verified || record.submission_completed?)
  end

  def preview?
    permissioned_employee?(:investor_kyc_read)
  end

  def esign_emails?
    permissioned_employee?(:investor_kyc_read)
  end

  def edit?
    # Allow signed-id investors to view the form even after completion (for the locked-state page).
    signed_id_access? || update?
  end

  def processing?
    edit?
  end

  def doc_first_upload?
    update?
  end

  # same as edit except doesnt check verified
  def edit_reporting_fields?
    update_reporting_fields?
  end

  # same as update except doesnt check verified
  def update_reporting_fields?
    (create?(:investor_kyc_update) && !user.curr_role_investor?) || support?
  end

  def destroy?
    create?(:investor_kyc_delete) && !record.verified
  end

  def request_updates?
    permissioned_employee?(:investor_kyc_update) && !record.verified
  end

  def investor_pending?
    user.curr_role == "investor"
  end

  def permissioned_employee?(perm = nil)
    extended_permissioned_employee?(perm)
  end

  private

  # show? path 1: a user currently in the KYC's entity (or its Group Company parent).
  def entity_staff_can_see?
    return false unless belongs_to_entity?(user, record)

    # The same list the KYC index shows them: every KYC for a company admin or Group Company user,
    # staff_visible_kycs (with its enable_kycs gate) for an employee. No investor_kyc_read check
    # here any more - under the visibility rule fund access alone is enough to open a KYC (V3).
    # Scoped from the base class, not record.class (ApplicationPolicy#policy_scope): KYCs are STI,
    # and for an IndividualKyc the company-admin scope (ForInvestor.for_company_admin) derives its
    # table name from the class name - "individual_kycs.entity_id", a table that does not exist.
    Pundit.policy_scope!(user, InvestorKyc).exists?(id: record.id)
  end

  # show? path 2: the user holds a staff grant on the KYC's entity. Everything is read off the
  # grant and the KYC's entity - never user.enable_kycs or user.get_extended_permissions, which
  # follow whichever entity the advisor is switched into right now. Reading those made a
  # switched-out advisor's KYC emails depend on an unrelated entity's settings (V7).
  def advisor_grant_can_see?
    grant = record.entity.investor_advisors.find_by(user_id: user.id)
    # A grant with only investor-side roles is not a staff grant; path 3 handles those users.
    return false unless grant && (grant.is_employee? || grant.is_company_admin?)

    # enable_kycs on both the grant and the KYC's entity - the switched-out equivalent of the
    # user.enable_kycs gate staff get in Scope (V9).
    return false unless grant.permissions.enable_kycs? && record.entity.permissions.enable_kycs?

    # A company_admin grant sees every KYC in the entity, as a company admin does when switched
    # in, without needing fund access rights (V8).
    return true if grant.is_company_admin?

    # Otherwise the same rule as the entity's employees, applied to the grant's toggles.
    InvestorKycPolicy.staff_visible_kycs(InvestorKyc.all, entity_id: record.entity_id, user_id: user.id,
                                                          extended_permissions: grant.extended_permissions)
                     .exists?(id: record.id)
  end

  # Returns true when access was granted via a signed magic link token and
  # the KYC is not yet completed or verified (investor can still edit it).
  def signed_id_investor?
    signed_id_access? &&
      !record.submission_completed? &&
      !record.submission_verified?
  end
end
