class FormCustomFieldPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.joins(:form_type).where(form_types: { entity_id: user.entity_id })
    end
  end

  def index?
    user.enable_form_types
  end
end
