module SearchHelper
  def add_hidden_fields_from_source(form, data_source)
    query_string = URI.parse(data_source).query

    render partial: "layouts/form_hidden_field", locals: { form:, query_string: }
  end
end
