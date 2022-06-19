module ApplicationHelper
  def display_boolean(field)
    render partial: "/layouts/display_boolean", locals: { field: }
  end
end
