module SecondarySaleNotifiers
  extend ActiveSupport::Concern

  def notify_investment_advisors
    SecondarySaleMailer.with(id:).notify_investment_advisors.deliver_later
  end

  def notify_open_for_interests
    SecondarySaleMailer.with(id:).notify_open_for_interests.deliver_later
  end

  def notify_open_for_offers
    SecondarySaleMailer.with(id:).notify_open_for_offers.deliver_later
  end

  def notify_closing_offers
    SecondarySaleMailer.with(id:).notify_closing_offers.deliver_later
  end

  def notify_closing_interests
    SecondarySaleMailer.with(id:).notify_closing_interests.deliver_later
  end

  def notify_allocation
    SecondarySaleMailer.with(id:).notify_allocation_offers.deliver_later
    SecondarySaleMailer.with(id:).notify_allocation_interests.deliver_later
  end

  def notify_spa_all
    SecondarySaleMailer.with(id:).notify_spa_offers.deliver_later
    SecondarySaleMailer.with(id:).notify_spa_interests.deliver_later
  end

  def notify_spa_buyers
    all_emails = interests.short_listed.not_final_agreement.collect(&:notification_emails).flatten
    all_emails.each_slice(10) do |list|
      SecondarySaleMailer.with(id:, list:).notify_spa_interests.deliver_later
    end
  end

  def notify_spa_sellers
    # Send email to only those who are verified but not confirmed SPA
    all_offers = offers.includes(:user).verified.not_final_agreement
    all_emails = all_offers.collect(&:user).collect(&:email)
    all_emails.each_slice(10) do |list|
      SecondarySaleMailer.with(id:, list:).notify_spa_offers.deliver_later
    end

    # Trigger the Signature Job - this will cause all the adhaar signature requests to go out
    OfferSpaSignatureJob.perform_later(id, nil)
  end
end
