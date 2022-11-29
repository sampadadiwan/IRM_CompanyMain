class SignatureWorkflowJob < ApplicationJob
  queue_as :default

  def perform(_id = nil)
    Chewy.strategy(:sidekiq) do
      # Cycle thru each SWF which is not complete
      SignatureWorkflow.not_completed.not_paused each, &:next_step
    end
  end
end
