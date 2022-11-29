class InvestorNoticeJob < ApplicationJob
  queue_as :default

  def perform(id = nil)
    Chewy.strategy(:sidekiq) do
      if id.present?
        investor_notice = InvestorNotice.find(id)

        investor_notice.entity.investors.each do |investor|
          if InvestorNoticeEntry.where(investor_id: investor.id, investor_notice_id: investor_notice.id).first.present?
            Rails.logger.debug { "InvestorNoticeJob: InvestorNoticeEntry already present for #{investor.investor_name} for notice #{investor_notice.id}" }
          else
            InvestorNoticeEntry.create!(investor_id: investor.id, investor_notice_id: investor_notice.id,
                                        investor_entity_id: investor.investor_entity_id,
                                        entity_id: investor_notice.entity_id, active: true)
          end
        end

      else
        InvestorNotice.where("end_date < ?", Time.zone.today).update(active: false)
      end
    end
  end
end
