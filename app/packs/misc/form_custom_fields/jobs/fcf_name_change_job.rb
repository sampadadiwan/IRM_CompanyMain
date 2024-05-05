class FcfNameChangeJob < ApplicationJob
  queue_as :serial

  def perform(fcf_id, old_name)
    Chewy.strategy(:active_job) do
      fcf = FormCustomField.find(fcf_id)
      fcf.change_name(old_name)
    end
  end
end
