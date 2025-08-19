class FormTypePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_form_types
  end

  def search?
    true
  end

  def show?
    index? && belongs_to_entity?(user, record)
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

  def add_regulatory_fields?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def rename_fcf?
    update?
  end

  def configure_grids?
    update? && record.name.constantize.const_defined?(:STANDARD_COLUMNS)
  end

  def clone?
    true
  end
end
