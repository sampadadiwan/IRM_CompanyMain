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
    # D: only on one of the user's firm's form types (it was only enable_form_types)
    # E: a Calculation field runs its formula as code, so only support may create one (and, as the form's
    # field-type dropdown allows, anyone in a local / test environment)
    new? && parent_in_users_firms?(record.form_type) && (record.field_type != "Calculation" || calculation_allowed?)
  end

  # E: the fields this user may send. On an existing field, field_type is only for those who may create a
  # Calculation: otherwise a field could be turned into one after it is created (update? sees the old type)
  def permitted_attributes
    fields = %i[name field_type required read_only form_type_id info reg_env meta_data label help_text position step
                show_user_ids condition_on condition_criteria condition_params condition_state filter_in_search]
    fields += FormCustomField::VALIDATION_RULE_KEYS.map { |k| :"vr_#{k}" }
    fields.delete(:field_type) if record.is_a?(FormCustomField) && record.persisted? && !calculation_allowed?
    fields
  end

  # The same rule as the form's field-type dropdown (form_custom_fields/_form.html.erb)
  def calculation_allowed?
    user.support? || Rails.env.local?
  end

  def edit?
    show?
  end

  def update?
    show? && (record.field_type != "Calculation" || user.support?)
  end

  def destroy?
    show?
  end
end
