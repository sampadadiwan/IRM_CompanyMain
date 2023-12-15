class FcfNameChangeJob < ApplicationJob
  queue_as :default

  def perform(fcf_id, old_name)
    Chewy.strategy(:sidekiq) do
      fcf = FormCustomField.find(fcf_id)
      fcf.change_name(old_name)
    end
  end
end
