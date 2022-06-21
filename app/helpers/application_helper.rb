module ApplicationHelper
  def display_boolean(field)
    render partial: "/layouts/display_boolean", locals: { field: }
  end

  def upload_server
    Rails.configuration.upload_server
  end
end
