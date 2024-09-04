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

  def permissioned_employee?(owner_id, owner_type, perm = nil)
    # Does the user belong to the entity that owns the record?
    if belongs_to_entity?(user, record)
      # Is the user a company admin?
      if user.has_cached_role?(:company_admin)
        # Can see everything
        true
      else
        # Get the cached access rights from the user for the record
        cached_permissions = user.get_cached_access_rights_permissions(owner_type, owner_id)

        # If the user has access rights for the record and the permission is nil or read or the user has the permission
        cached_permissions.present? && (perm.nil? || perm == :read || user.access_rights_cached_permissions.set?(perm))
      end
    else
      false
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

  def permissioned_investor?(metadata = "none")
    # Is the user an investor or holding
    if (user.curr_role == 'investor' || user.curr_role == 'holding') && !belongs_to_entity?(user, record)
      # is this record visible to the user
      visible_record = policy_scope.where("#{record.class.table_name}.id=?", record.id)
      # Cache the result
      @pi_record ||= {}
      @pi_record[metadata] ||= if metadata == "none"
                                 visible_record
                               else
                                 visible_record.where("access_rights.metadata=?", metadata)
                               end
      @pi_record[metadata].present?
    else
      # Not an investor
      false
    end
  end
end
