class InvestorNoticeJob < ApplicationJob
  queue_as :low

  def perform(id = nil)
    Chewy.strategy(:sidekiq) do
      if id.present?
        create_notice_entries(id)
      else
        InvestorNotice.where("end_date < ?", Time.zone.today).update(active: false)
      end
    end
  end

  def create_notice_entries(id)
    investor_notice = InvestorNotice.find(id)
    investor_entity_ids = []
    investor_notice.entity.investors.each do |investor|
      if InvestorNoticeEntry.where(investor_id: investor.id, investor_notice_id: investor_notice.id).first.present?
        Rails.logger.debug { "InvestorNoticeJob: InvestorNoticeEntry already present for #{investor.investor_name} for notice #{investor_notice.id}" }
      else

        InvestorNoticeEntry.create(investor_id: investor.id, investor_notice_id: investor_notice.id,
                                   investor_entity_id: investor.investor_entity_id,
                                   entity_id: investor_notice.entity_id, active: true)

        investor_entity_ids << investor.investor_entity_id
      end
    end

    # Bulk update the investor_entity_ids so the cache is busted
    investor_notice.investor_notice_entries.pluck(:investor_entity_id)
    Entity.where(id: investor_entity_ids).update_all(updated_at: Time.zone.now)
  end
end
