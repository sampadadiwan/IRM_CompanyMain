class ClearMessagesCountJob < ApplicationJob
  queue_as :low

  def perform(*_args)
    Chewy.strategy(:active_job) do
      DealInvestor.update(todays_messages_investor: 0, todays_messages_investee: 0)
    end
  end
end
