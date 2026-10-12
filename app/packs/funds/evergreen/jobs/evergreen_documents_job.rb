# "Generate documents" on a dealing date (open-ended-funds § Dealing-date documents)
class EvergreenDocumentsJob < ApplicationJob
  queue_as :doc_gen

  def perform(dealing_date_id, user_id)
    Chewy.strategy(:sidekiq) do
      dealing_date = DealingDate.find(dealing_date_id)
      made, errors = EvergreenDealingDocuments.generate(dealing_date, user_id)
      message = "#{made} #{'document'.pluralize(made)} generated for #{I18n.l(dealing_date.date)} — approve and send them on the #{EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: dealing_date.fund))}"
      message += ". #{errors.size} failed: #{errors.first(3).join('; ')}" if errors.any?
      UserAlert.new(user_id:, message:, level: errors.any? ? :warning : :success).broadcast if user_id
    end
  end
end
