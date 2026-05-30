class FormCustomFieldPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.joins(:form_type).where(form_types: { entity_id: user.entity_id })
    end
  end

  def index?
    user.enable_form_types
  end

  def show?
    user.enable_form_types && record.form_type.entity_id == user.entity_id
  end

  def new?
    user.enable_form_types
  end

  def create?
    new?
  end

  def edit?
    show?
  end

  def update?
    show?
  end

  def destroy?
    show?
  end
end
