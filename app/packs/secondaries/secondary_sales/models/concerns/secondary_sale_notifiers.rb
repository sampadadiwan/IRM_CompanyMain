module SecondarySaleNotifiers
  extend ActiveSupport::Concern

  MAX_TO_SIZE = 30
  NOTIFICATIONS = %w[notify_open_for_offers notify_closing_offers notify_open_for_interests notify_closing_interests notify_allocation notify_spa_sellers notify_spa_buyers].freeze

  def notify_investment_advisors
    SecondarySaleMailer.with(id:).notify_investment_advisors.deliver_later
  end

  def notify_open_for_interests
    SecondarySaleMailer.with(id:).notify_open_for_interests.deliver_later
  end

  def notify_open_for_offers
    # Get all emails of investors & holding company employees
    all_emails = investor_users("Seller").collect(&:email).flatten +
                 employee_users("Seller").collect(&:email).flatten

    all_emails.each_slice(MAX_TO_SIZE) do |list|
      SecondarySaleMailer.with(id:, list:).notify_open_for_offers.deliver_later
    end
  end

  def notify_closing_offers
    # Get all emails of investors & holding company employees
    all_emails = investor_users("Seller").collect(&:email).flatten +
                 employee_users("Seller").collect(&:email).flatten
    all_emails.each_slice(MAX_TO_SIZE) do |list|
      SecondarySaleMailer.with(id:, list:).notify_closing_offers.deliver_later
    end
  end

  def notify_closing_interests
    SecondarySaleMailer.with(id:).notify_closing_interests.deliver_later
  end

  def notify_allocation
    all_emails = investor_users("Seller").collect(&:email).flatten +
                 employee_users("Seller").collect(&:email).flatten

    all_emails.each_slice(MAX_TO_SIZE) do |list|
      SecondarySaleMailer.with(id:, list:).notify_allocation_offers.deliver_later
    end

    SecondarySaleMailer.with(id:).notify_allocation_interests.deliver_later
  end

  def notify_spa_all
    SecondarySaleMailer.with(id:).notify_spa_offers.deliver_later
    SecondarySaleMailer.with(id:).notify_spa_interests.deliver_later
  end

  def notify_spa_buyers
    all_emails = interests.short_listed.not_final_agreement.collect(&:notification_emails).flatten
    all_emails.each_slice(MAX_TO_SIZE) do |list|
      SecondarySaleMailer.with(id:, list:).notify_spa_interests.deliver_later
    end
  end

  def notify_spa_sellers
    if seller_signature_types.include?("adhaar")
      # Trigger the Signature Job - this will cause all the adhaar signature requests to go out
      OfferSpaSignatureJob.perform_later(id, nil)
    else
      # Send email to only those who are verified but not confirmed SPA
      all_offers = offers.includes(:user).verified.not_final_agreement
      all_emails = all_offers.collect(&:user).collect(&:email)
      all_emails.each_slice(MAX_TO_SIZE) do |list|
        SecondarySaleMailer.with(id:, list:).notify_spa_offers.deliver_later
      end
    end
  end
end
