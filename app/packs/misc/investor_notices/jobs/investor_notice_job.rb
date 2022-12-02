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
    entries = []

    # Generate import of only new_interest_ids
    all_investor_ids = investor_notice.entity.investors.pluck(:id)
    existing_investor_ids = investor_notice.investor_notice_entries.pluck(:investor_id)
    new_investor_ids = all_investor_ids - existing_investor_ids

    Investor.where(id: new_investor_ids).each do |investor|
      entries << InvestorNoticeEntry.new(investor_id: investor.id, investor_notice_id: investor_notice.id,
                                         investor_entity_id: investor.investor_entity_id,
                                         entity_id: investor_notice.entity_id, active: true)

      investor_entity_ids << investor.investor_entity_id
    end

    if entries.present?
      Rails.logger.debug { "InvestorNoticeJob: importing #{entries.length} investor notices" }
      InvestorNoticeEntry.import entries
      # Bulk update the investor_entity_ids so the cache is busted
      Entity.where(id: investor_entity_ids).update_all(updated_at: Time.zone.now)
    else
      Rails.logger.debug "InvestorNoticeJob: nothing to import"
    end
  end
end
