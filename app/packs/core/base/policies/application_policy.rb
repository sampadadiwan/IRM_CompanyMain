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

  def support?
    user.has_cached_role?(:support)
  end

  def super_user?
    user.has_cached_role?(:super)
  end

  # This method checks if the user is of the record entity or of the parent group company
  # Example: If user is of entity "A" and record is of entity "A", then user can perform  actions
  # If user is of entity "A" and record is of entity "B" and entity "B" is a child of entity "A", then user can perform actions
  # If user is of entity "A" and record is of entity "B" and entity "B" is not a child of entity "A", then user cannot perform actions
  def belongs_to_entity?(user, record)
    user.entity_id == record.entity_id ||
      (user.entity_type == "Group Company" && user.entity.child_ids.include?(record.entity_id)) || support?
  end

  def company_admin_or_emp_crud?(user, record, crud = "read")
    user.has_cached_role?(:company_admin) || crud?(user, record, crud)
  end

  # This method checks if the user has the extended permission to perform the action on the record
  def crud?(user, record, crud = "read")
    perm = "#{record.class.name.underscore}_#{crud}"
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
end
