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
    user.entity_id == record.entity_id ||
      (user.entity_type == "Group Company" && user.entity.child_ids.include?(record.entity_id))
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
    # Does the user belong to the entity that owns the record?
    if belongs_to_entity?(user, record)
      # Is the user a company admin?
      if user.has_cached_role?(:company_admin)
        # Can see everything
        true
      else
        # Get the model to wich the access_rights are attached, for the policy record
        # Example for an offer its the associated secondary_sale,
        # for the commitment its the fund etc
        # But for a sale its the sale itself, likewise for fund
        model_with_access_rights = get_model_with_access_rights(owner:)

        # Get the cached_permissions and metadata from the users access_rights_cache
        cached_permissions = nil
        cached_permissions, _metadata = user.get_cached_access_rights_permissions(model_with_access_rights.entity_id, model_with_access_rights.class.name, model_with_access_rights.id) if model_with_access_rights.present?

        # If the user has access rights for the record and the permission is nil or read or the user has the permission
        cached_permissions.present? && (perm.nil? || perm == :read || user.access_rights_cached_permissions.set?(perm))
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

  def permissioned_investor_non_advisor?(metadata = "none", owner: nil)
    # Is the user an investor
    if %w[investor].include?(user.curr_role) &&
       !belongs_to_entity?(user, record)

      # Get the model to wich the access_rights are attached, for the policy record
      # Example for an offer its the associated secondary_sale,
      # for the commitment its the fund etc
      # But for a sale its the sale itself, likewise for fund
      model_with_access_rights = get_model_with_access_rights(owner:)

      # Get the cached_permissions and metadata from the users access_rights_cache
      cached_permissions = nil
      cached_permissions, cached_metadata = user.get_cached_access_rights_permissions(user.entity_id, model_with_access_rights.class.name, model_with_access_rights.id) if model_with_access_rights.present?

      # If the user has access rights for the record and the permission is nil or read or the user has the permission
      # binding.pry
      permission_metadata_ok = cached_permissions.present? && (metadata == "none" || metadata.to_s.downcase == cached_metadata.to_s.downcase)
      if model_with_access_rights == record
        permission_metadata_ok
      else
        permission_metadata_ok && record.investor.investor_entity_id == user.entity_id
      end
    else
      # Not an investor
      false
    end
  end

  def permissioned_investor_advisor?(metadata = "none", owner: nil, as_entity_id: nil)
    # Is the user an investor
    if user.has_cached_role?(:investor_advisor) && !belongs_to_entity?(user, record)

      # Get the model to wich the access_rights are attached, for the policy record
      # Example for an offer its the associated secondary_sale,
      # for the commitment its the fund etc
      # But for a sale its the sale itself, likewise for fund
      model_with_access_rights = get_model_with_access_rights(owner:)

      # Get the cached_permissions and metadata from the users access_rights_cache for the model_with_access_rights
      cached_permissions = nil
      entity_id = as_entity_id.presence || user.entity_id
      # Here we check the access_rights_cache without an entity_id, so it scans thru all entities the user has access to
      cached_permissions, cached_metadata = user.get_cached_access_rights_permissions(entity_id, model_with_access_rights.class.name, model_with_access_rights.id) if model_with_access_rights.present?

      # If the user has access rights for the record and the permission is nil or read or the user has the permission
      permission_metadata_ok = cached_permissions.present? && (metadata == "none" || metadata.to_s.downcase == cached_metadata.to_s.downcase)
      Rails.logger.debug { "Permission metadata ok: #{permission_metadata_ok}, for user: #{user.email}, record: #{record.class.name}##{record.id}, metadata: #{metadata}" }
      if model_with_access_rights == record
        permission_metadata_ok
      else
        permission_metadata_ok && (as_entity_id.present? || record.investor.investor_entity_id == user.entity_id)
      end
    else
      # Not an investor
      false
    end
  end

  def permissioned_investor?(metadata = "none", owner: nil, as_entity_id: nil)
    if user.has_cached_role?(:investor_advisor)
      permissioned_investor_advisor?(metadata, owner:, as_entity_id:)
    else
      permissioned_investor_non_advisor?(metadata, owner:)
    end
  end

  # Permissioned for Relationship Manager
  def permissioned_rm?(metadata = "none", owner: nil)
    if user.has_cached_role?(:rm)
      # Get the model to wich the access_rights are attached, for the policy record
      # Example for an offer its the associated secondary_sale,
      # for the commitment its the fund etc
      # But for a sale its the sale itself, likewise for fund
      model_with_access_rights = get_model_with_access_rights(owner:)

      # Get the cached_permissions and metadata from the users access_rights_cache
      cached_permissions = nil
      cached_permissions, cached_metadata = user.get_cached_access_rights_permissions(user.entity_id, model_with_access_rights.class.name, model_with_access_rights.id) if model_with_access_rights.present?

      # If the user has access rights for the record and the permission is nil or read or the user has the permission
      permission_metadata_ok = cached_permissions.present? && (metadata == "none" || metadata.to_s.downcase == cached_metadata.to_s.downcase)
      if model_with_access_rights == record
        permission_metadata_ok
      elsif record.new_record?
        permission_metadata_ok && record.entity.rm_mappings.exists?(rm_entity_id: user.entity_id)
      # We may not have the investor_id yet, see the UI for offers and interests for RMs where they select the investor
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
