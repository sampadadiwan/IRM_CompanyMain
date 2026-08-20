class InvestorNoticeJob < ApplicationJob
  queue_as :low

  def perform(id = nil)
    Chewy.strategy(:sidekiq) do
      if id.present?
        create_notice_entries(id)
      else
        expire_ended_notices
      end
    end
  end

  def create_notice_entries(id)
    investor_notice = InvestorNotice.find(id)
    investor_entity_ids = []
    entries = []

    # Generate import of only new_interest_ids
    # Audience is owner-scoped (Fund/SecondarySale/Deal) or entity-wide —
    # see InvestorNotice#investors.
    all_investors = investor_notice.investors
    all_investors = all_investors.where(category: investor_notice.category) if investor_notice.category.present?

    all_investor_ids = all_investors.pluck(:id)

    existing_investor_ids = investor_notice.investor_notice_entries.pluck(:investor_id)
    new_investor_ids = all_investor_ids - existing_investor_ids

    Investor.where(id: new_investor_ids).find_each do |investor|
      entries << InvestorNoticeEntry.new(investor_id: investor.id, investor_notice_id: investor_notice.id,
                                         investor_entity_id: investor.investor_entity_id,
                                         entity_id: investor_notice.entity_id, active: true)

      investor_entity_ids << investor.investor_entity_id
    end

    if entries.present?
      Rails.logger.debug { "InvestorNoticeJob: importing #{entries.length} investor notices" }
      InvestorNoticeEntry.import entries, on_duplicate_key_ignore: true, track_validation_failures: true
      # Bulk update the investor_entity_ids so the cache is busted
      Entity.where(id: investor_entity_ids).update_all(updated_at: Time.zone.now)
    else
      Rails.logger.debug "InvestorNoticeJob: nothing to import"
    end
  end

  private

  # Deactivate notices whose end_date has passed. Uses update_all (a single
  # UPDATE, no callbacks) rather than relation#update (which loads every row
  # and saves each individually) — expiring a notice doesn't need
  # InvestorNotice#update_investors to re-touch every linked investor entity
  # every day, so the affected entities are bulk-touched once here instead,
  # matching the pattern in create_notice_entries above.
  def expire_ended_notices
    expiring = InvestorNotice.where(active: true).where(end_date: ...Time.zone.today)
    investor_entity_ids = InvestorNoticeEntry.where(investor_notice_id: expiring.select(:id)).distinct.pluck(:investor_entity_id)

    expiring.update_all(active: false, updated_at: Time.zone.now)
    Entity.where(id: investor_entity_ids).update_all(updated_at: Time.zone.now) if investor_entity_ids.present?
  end
end
