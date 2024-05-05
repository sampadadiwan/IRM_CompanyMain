class FormTypeJob < ApplicationJob
  queue_as :low

  def perform(form_type_id)
    Chewy.strategy(:active_job) do
      form_type = FormType.find(form_type_id)
      form_type.ensure_json_fields
    end
  end
end
