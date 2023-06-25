module SecondarySaleNotifiers
  extend ActiveSupport::Concern

  MAX_TO_SIZE = 40
  NOTIFICATIONS = %w[notify_open_for_offers notify_closing_offers notify_open_for_interests notify_closing_interests notify_allocation notify_spa_sellers notify_spa_buyers].freeze

  def notify_open_for_interests
    # Get all emails of investors & holding company employees
    all_emails = investor_users("Buyer").collect(&:email).flatten +
                 employee_users("Buyer").collect(&:emails).flatten

    all_emails.uniq.each do |email|
      SecondarySaleMailer.with(id:, email:).notify_open_for_interests.deliver_later
    end
  end

  def notify_open_for_offers
    # Get all emails of investors & holding company employees
    all_emails = investor_users("Seller").collect(&:email).flatten +
                 employee_users("Seller").collect(&:email).flatten

    all_emails.uniq.each do |email|
      SecondarySaleMailer.with(id:, email:).notify_open_for_offers.deliver_later
    end
  end

  def notify_closing_offers
    # Get all emails of investors & holding company employees
    all_emails = investor_users("Seller").collect(&:email).flatten +
                 employee_users("Seller").collect(&:email).flatten

    all_emails.uniq.each do |email|
      SecondarySaleMailer.with(id:, email:).notify_closing_offers.deliver_later
    end
  end

  def notify_closing_interests
    # Get all emails of investors & holding company employees
    all_emails = investor_users("Buyer").collect(&:email).flatten +
                 employee_users("Buyer").collect(&:email).flatten

    all_emails.uniq.each do |email|
      SecondarySaleMailer.with(id:, email:).notify_closing_interests.deliver_later
    end
  end

  # Notify only verified offers and shortlisted interests
  def notify_allocation
    offers.verified.each do |offer|
      email = offer.offer_type == "Employee" ? offer.user.email : offer.investor.emails("All").join(",")
      SecondarySaleMailer.with(id:, email:).notify_allocation_offers.deliver_later
    end

    interests.short_listed.each do |interest|
      email = interest.investor.emails("All").join(",")
      SecondarySaleMailer.with(id:, email:).notify_allocation_interests.deliver_later
    end
  end

  def notify_spa_buyers
    all_emails = interests.short_listed.not_final_agreement.collect(&:notification_emails).flatten
    all_emails.uniq.each do |email|
      SecondarySaleMailer.with(id:, email:).notify_spa_interests.deliver_later
    end
  end

  def notify_spa_sellers
    if seller_signature_types.include?("adhaar")
      # Trigger the Signature Job - this will cause all the adhaar signature requests to go out
      OfferSpaSignatureJob.perform_later(id, nil)
    else
      # Send email to only those who are verified but not confirmed SPA
      offers.verified.each do |offer|
        email = offer.offer_type == "Employee" ? offer.user.email : offer.investor.emails("All").join(",")
        SecondarySaleMailer.with(id:, email:).notify_spa_offers.deliver_later
      end

      interests.short_listed.each do |interest|
        email = interest.investor.emails("All").join(",")
        SecondarySaleMailer.with(id:, email:).notify_spa_offers.deliver_later
      end
    end
  end
end
