class CustomGridViewPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_form_types
  end

  def create?
    belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def update_column_sequence?
    edit?
  end

  def configure?
    create?
  end

  def show?
    index? && belongs_to_entity?(user, record)
  end
end
