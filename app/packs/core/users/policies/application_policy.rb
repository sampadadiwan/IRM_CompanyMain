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

  def super_user?
    user.has_cached_role?(:super)
  end

  def belongs_to_entity?(user, record)
    user.entity_id == record.entity_id ||
      (user.entity_type == "Group Company" && user.entity.child_ids.include?(record.entity_id))
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.all
    end

    def resolve_admin
      scope.joins(:entity).where('entities.enable_support': true)
    end

    private

    attr_reader :user, :scope
  end
end
