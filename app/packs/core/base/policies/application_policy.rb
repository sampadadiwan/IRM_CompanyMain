# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    raise Pundit::NotAuthorizedError, "Must be logged in" unless user

    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # Permission to file an email against this record from the Outlook/Gmail add-ins.
  # incoming_emails.owner is polymorphic, so any owner type can opt in by overriding
  # this; denying by default keeps new types out of the add-ins until considered.
  # @see MailFilingCreate
  def file_mail?
    false
  end

  def validate_docs_with_ai?
    user.entity.enable_doc_llm_validation
  end

  def allow_external?(action, role = nil)
    extenal = Permission.allow(record, user, role)
    extenal ? extenal.set?(action) : false
  end

  delegate :support?, to: :user

  def super_user?
    user.has_cached_role?(:super)
  end

  # This method checks if the user is of the record entity or of the parent group company
  # Example: If user is of entity "A" and record is of entity "A", then user can perform  actions
  # If user is of entity "A" and record is of entity "B" and entity "B" is a child of entity "A", then user can perform actions
  # If user is of entity "A" and record is of entity "B" and entity "B" is not a child of entity "A", then user cannot perform actions
  def belongs_to_entity?(user, record)
    users_firm?(user, record.entity_id)
  end

  # The parent a record hangs off (its fund, folder, owner, …) is in one of the user's firms. A record's
  # own entity_id comes from the request, so it alone can't be trusted. No parent: nothing to check.
  def parent_in_users_firms?(parent)
    parent.nil? || users_firm?(user, parent.is_a?(Entity) ? parent.id : parent.entity_id)
  end

  # The user's own firm, or a child firm of their group company
  def users_firm?(user, entity_id)
    user.entity_id == entity_id || (user.entity_type == "Group Company" && user.entity.child_ids.include?(entity_id))
  end

  def belongs_to_investor_entity?(user, record)
    user.entity_id == record.investor&.investor_entity_id if record.respond_to?(:investor)
  end

  def company_admin_or_emp_crud?(user, record, crud = "read")
    user.has_cached_role?(:company_admin) || crud?(user, record, crud)
  end

  # This method checks if the user has the extended permission to perform the action on the record
  def crud?(user, _record, crud = "read")
    perm = "#{self.class.name.gsub('Policy', '').underscore}_#{crud}"
    user.get_extended_permissions.set?(perm.to_sym)
  end

  class Scope < BaseScope
  end

  def owner_policy
    Pundit.policy(user, record.owner)
  end

  def new_policy(model)
    Pundit.policy(user, model)
  end

  # This gives back the policy_scope for this user and record class
  def policy_scope
    Pundit.policy_scope!(user, record.class)
  end

  # Checks if the user was granted access via a signed ID shared link.
  # This is used for public/shared links where a user might not be logged in.
  # The controller marks the user object with this method via `define_singleton_method`.
  #
  # @return [Boolean] True if the user has signed ID access.
  def signed_id_access?
    user.respond_to?(:signed_id_access?) && user.signed_id_access?
  end

  def get_model_with_access_rights(owner: nil)
    # Get the model_with_access_rights from the record
    model_with_access_rights = record.model_with_access_rights if record.respond_to?(:model_with_access_rights)
    # Get the model_with_access_rights from the record.owner
    model_with_access_rights ||= record.owner.model_with_access_rights if record.respond_to?(:owner) && record.owner.respond_to?(:model_with_access_rights)
    # Get the model_with_access_rights from the optional owen
    model_with_access_rights ||= owner.model_with_access_rights if owner.respond_to?(:model_with_access_rights)

    model_with_access_rights
  end

  def permissioned_employee?(perm = nil, owner: nil)
    # The record that governs access: a fund record's fund, an approval response's approval, …
    model_with_access_rights = get_model_with_access_rights(owner:)
    # Its parents: that record, and its fund (also for fund models outside ForInvestor) (D)
    parents = [model_with_access_rights, record.try(:fund)]
    # Does the user belong to the entity that owns the record, and to the ones that own its parents?
    if belongs_to_entity?(user, record) && parents.all? { |parent| parent_in_users_firms?(parent) }
      # Is the user a company admin?
      if user.has_cached_role?(:company_admin)
        # Can see everything
        true
      else
        return false if model_with_access_rights.blank?

        # Live DB lookup — indexed on (owner_type, owner_id, user_id)
        ar = AccessRight.where(
          entity_id: model_with_access_rights.entity_id,
          owner_type: model_with_access_rights.class.name,
          owner_id: model_with_access_rights.id,
          user_id: user.id
        ).first

        ar.present? && (perm.nil? || perm == :read || ar.permissions.set?(perm))
      end
    else
      support?
    end
  end

  def extended_permissioned_employee?(perm = nil)
    # Does the user belong to the entity that owns the record?
    if belongs_to_entity?(user, record)
      # Is the user a company admin?
      if user.has_cached_role?(:company_admin)
        # Can see everything
        true
      else
        @visible_record = policy_scope.where("#{record.class.table_name}.id=?", record.id)
        # If the user can see the record and the permission is nil or read or the user has the extended permission
        (perm.nil? || perm == :read || user.get_extended_permissions.set?(perm)) && @visible_record.present?
      end
    else
      false
    end
  end

  # own_entity_only: count only contact rows on investors in the user's current entity. Used for an
  # advisor at home, whose other approved contact rows are on their CLIENTS' investors (added by
  # the advisor grants) and must never open anything in the home view.
  def permissioned_investor_non_advisor?(metadata = "none", owner: nil, own_entity_only: false)
    # Is the user an investor
    if %w[investor].include?(user.curr_role) &&
       !belongs_to_entity?(user, record)

      model_with_access_rights = get_model_with_access_rights(owner:)
      return false if model_with_access_rights.blank?

      # Find ARs for this user via their approved investor accesses.
      # access_to_category is never stored in production (the UI always expands category → per-investor ARs),
      # so matching by access_to_investor_id is sufficient.
      approved_accesses = InvestorAccess.approved.where(user_id: user.id)
      # Worked example E4 — openspec/changes/fix-advisor-own-investor-access/report.md#verification:
      # without this, a fund granted only to a client's investor would open at home.
      approved_accesses = approved_accesses.where(investor_entity_id: user.entity_id) if own_entity_only
      approved_investor_ids = approved_accesses.pluck(:investor_id)
      return false if approved_investor_ids.empty?

      ar = AccessRight.where(
        owner_type: model_with_access_rights.class.name,
        owner_id: model_with_access_rights.id,
        access_to_investor_id: approved_investor_ids
      ).first

      return false unless ar

      permission_metadata_ok = metadata == "none" || metadata.to_s.downcase == ar.metadata.to_s.downcase.strip
      if model_with_access_rights == record
        permission_metadata_ok
      else
        # Some fund-child models (e.g. PortfolioScenario, FundRatio) have no direct
        # investor association; for those the fund-level AR is sufficient.
        investor_check = !record.respond_to?(:investor) || record.investor.nil? ||
                         record.investor.investor_entity_id == user.entity_id
        permission_metadata_ok && investor_check
      end
    else
      # Not an investor
      false
    end
  end

  def permissioned_investor_advisor?(metadata = "none", owner: nil, as_entity_id: nil)
    if user.has_cached_role?(:investor_advisor)
      model_with_access_rights = get_model_with_access_rights(owner:)
      return false if model_with_access_rights.blank?

      # Live DB lookup — indexed on (owner_type, owner_id, user_id)
      entity_id = as_entity_id.presence || user.entity_id
      ar = AccessRight.where(
        entity_id: entity_id,
        owner_type: model_with_access_rights.class.name,
        owner_id: model_with_access_rights.id,
        user_id: user.id
      ).first

      return false unless ar

      permission_metadata_ok = metadata == "none" || metadata.to_s.downcase == ar.metadata.to_s.downcase.strip
      Rails.logger.debug { "Permission metadata ok: #{permission_metadata_ok}, for user: #{user.email}, record: #{record.class.name}##{record.id}, metadata: #{metadata}" }
      if model_with_access_rights == record
        permission_metadata_ok
      else
        # Some fund-child models have no direct investor association; skip entity check for those.
        investor_check = as_entity_id.present? ||
                         !record.respond_to?(:investor) || record.investor.nil? ||
                         record.investor.investor_entity_id == user.entity_id
        permission_metadata_ok && investor_check
      end
    else
      false
    end
  end

  def permissioned_investor?(metadata = "none", owner: nil, as_entity_id: nil)
    if user.has_cached_role?(:investor_advisor)
      # The investor_advisor role is global: holding it for ANY grant (an Investor Advisor grant on
      # a client, or a Fund Advisor grant on a fund company) used to send every investor check down
      # the advisor rule, which only accepts a personal (user-level) grant. An advisor who is also a
      # plain approved contact of their OWN investor therefore lost that investor's fund-wide grant:
      # no call notices, no fund screens (prod: user 2564 / investor 4800 / fund 159).
      #
      # At home (not switched into any grant), they are also judged as a plain investor, limited
      # to contact rows in their home entity. While switched, only the advisor rule applies, so
      # where they happen to be switched never widens what they see.
      # Worked examples H1–H3, H5, H7, E3, E4, E7, E11, E12, X4, X6 —
      # openspec/changes/fix-advisor-own-investor-access/report.md#verification
      permissioned_investor_advisor?(metadata, owner:, as_entity_id:) ||
        (advisor_at_home? && permissioned_investor_non_advisor?(metadata, owner:, own_entity_only: true))
    else
      # An advisor account whose stored home roles leave investor_advisor out (prod: e.g.
      # "employee,investor" on an Investor-type home) loses the role on revert, yet still holds
      # approved contact rows on its CLIENTS' investors - so the same home-entity limit applies.
      # Worked example E16 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
      permissioned_investor_non_advisor?(metadata, owner:, own_entity_only: user.advisor_entity_id.present?)
    end
  end

  # "Not switched into any grant", judged by BOTH switch markers, because neither is reliable on
  # its own in prod data: User#investor_advisor? is false whenever advisor_entity_id is nil (legacy
  # advisors, even while switched), and 3 switched advisors carry a nil investor_advisor_id.
  # InvestorAdvisor#switch sets investor_advisor_id and moves entity_id away from
  # advisor_entity_id; revert undoes both. Worked example X6 — the report above.
  def advisor_at_home?
    !user.investor_advisor? && user.investor_advisor_id.nil?
  end

  # Permissioned for Relationship Manager
  def permissioned_rm?(metadata = "none", owner: nil)
    if user.has_cached_role?(:rm)
      model_with_access_rights = get_model_with_access_rights(owner:)
      return false if model_with_access_rights.blank?

      # Live DB lookup — RM ARs can be granted three ways:
      #   1. access_to_category = 'RM'  (categorical grant to all RMs)
      #   2. user_id = user.id          (direct user grant)
      #   3. access_to_investor_id IN (approved investor IDs) — used for models like SecondarySale
      #      where access is granted per investor and RM users hold InvestorAccess records.
      base_scope = AccessRight.where(
        entity_id: model_with_access_rights.entity_id,
        owner_type: model_with_access_rights.class.name,
        owner_id: model_with_access_rights.id
      )
      approved_investor_ids = InvestorAccess.approved.where(user_id: user.id).pluck(:investor_id)
      ar = if approved_investor_ids.any?
             base_scope.where(
               "access_to_category = 'RM' OR user_id = ? OR access_to_investor_id IN (?)",
               user.id, approved_investor_ids
             ).first
           else
             base_scope.where("access_to_category = 'RM' OR user_id = ?", user.id).first
           end

      return false unless ar

      permission_metadata_ok = metadata == "none" || metadata.to_s.downcase == ar.metadata.to_s.downcase.strip
      if model_with_access_rights == record
        permission_metadata_ok
      elsif record.new_record?
        permission_metadata_ok && record.entity.rm_mappings.exists?(rm_entity_id: user.entity_id)
      else
        permission_metadata_ok && record.entity.rm_mappings.exists?(rm_entity_id: user.entity_id, investor_id: record.investor_id)
      end
    else
      false
    end
  end

  def rm_mapping
    @rm_mapping ||= record.entity.rm_mappings.approved.where(investor_id: record.investor_id, rm_entity_id: user.entity_id).last
    @rm_mapping
  end

  def rm?
    user.has_cached_role?(:rm)
  end

  def run_checks?
    belongs_to_entity?(user, record) && user.entity.enable_compliance
  end
end
