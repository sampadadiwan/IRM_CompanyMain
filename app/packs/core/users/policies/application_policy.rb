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

  def permissioned_employee?
    user.entity_id == record.entity_id &&
      record.class.for_employee(user).where("#{record.class.table_name}.id=?", record.id).present?
  end

  def permissioned_investor?
    user.entity_id != record.entity_id &&
      record.class.for_investor(user).where("#{record.class.table_name}.id=?", record.id).present?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.all
    end

    private

    attr_reader :user, :scope
  end
end
