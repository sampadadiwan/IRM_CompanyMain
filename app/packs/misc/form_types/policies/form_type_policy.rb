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

  def generate_upload_xlsx?
    show?
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

  def edit_step_labels?
    update?
  end

  def update_step_labels?
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

  # M25 — cloning copies another firm's form type, Calculation fields included, into the user's current
  # firm. It is a support tool: support only, and only where the user may create form types (a company
  # admin of the destination firm, which is always the user's current one). M25-2, M25-H in
  # features/security/security_review_2026_10_medium.feature
  def clone?
    support? && new_policy(FormType.new(entity_id: user.entity_id)).create?
  end
end
