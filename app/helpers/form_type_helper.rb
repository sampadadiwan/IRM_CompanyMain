module FormTypeHelper
  def custom_form_fields(model, form)
    render partial: "/form_types/custom_form_fields", locals: { model:, form: } if model.form_type.present?
  end

  def display_custom_fields(model)
    render partial: "/form_types/display_custom_fields", locals: { model: }
  end
end
