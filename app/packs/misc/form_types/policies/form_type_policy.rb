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

  # The custom fields icon and side panel on a record page (openspec/changes/grid-columns-inline-settings — D17):
  # whoever may edit the form type (company admin of its firm), never a user acting as an investor (X11). The
  # record's own show? is checked by the controller before this. For a form type created on the first save the
  # record is unsaved and carries the firm (H13).
  def inline_fields?
    update? && !user.curr_role_investor?
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
