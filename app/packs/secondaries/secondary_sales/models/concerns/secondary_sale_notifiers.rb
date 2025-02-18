module SecondarySaleNotifiers
  extend ActiveSupport::Concern

  MAX_TO_SIZE = 40
  NOTIFICATIONS = %w[notify_open_for_offers notify_closing_offers notify_open_for_interests notify_closing_interests notify_allocation notify_spa_sellers notify_spa_buyers adhoc_notification].freeze

  def notify_open_for_interests
    # Get all emails of investors
    all_users = investor_users("Buyer").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(record: self, entity_id:, email: user.email, email_method: :notify_open_for_interests, msg: "Secondary Sale: #{name} by #{entity.name}, open for interests").deliver_later(user)
    end
  end

  def notify_closing_interests
    # Get all emails of investors
    all_users = investor_users("Buyer").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(record: self, entity_id:, email: user.email, email_method: :notify_closing_interests, msg: "Secondary Sale: #{name} by #{entity.name}, reminder to enter your interest").deliver_later(user)
    end
  end

  def notify_open_for_offers
    # Get all emails of investors
    all_users = investor_users("Seller").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(record: self, entity_id:, email: user.email, email_method: :notify_open_for_offers, msg: "Secondary Sale: #{name} by #{entity.name}, open for offers").deliver_later(user)
    end
  end

  def notify_closing_offers
    # Get all emails of investors
    all_users = investor_users("Seller").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(record: self, entity_id:, email: user.email, email_method: :notify_closing_offers, msg: "Secondary Sale: #{name} by #{entity.name}, reminder to enter your offer").deliver_later(user)
    end
  end

  # Notify only verified offers and shortlisted interests
  def notify_allocation
    offers.verified.each do |offer|
      email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
      email_users.each do |user|
        SecondarySaleNotifier.with(record: self, entity_id:, email_method: :notify_allocation_offers, msg: "Secondary Sale: #{name} allocation complete").deliver_later(user)
      end
    end

    interests.short_listed.each do |interest|
      interest.investor.notification_users.each do |user|
        SecondarySaleNotifier.with(record: self, entity_id:, email_method: :notify_allocation_interests, msg: "Secondary Sale: #{name} allocation complete").deliver_later(user)
      end
    end
  end

  def notify_spa_buyers
    interests.short_listed.not_final_agreement.each do |interest|
      interest.investor.approved_users.each do |user|
        SecondarySaleNotifier.with(record: self, entity_id:, email_method: :notify_spa_interests, msg: "Secondary Sale: #{name}, please accept uploaded SPA.").deliver_later(user)
      end
    end
  end

  def notify_spa_sellers
    # Send email to only those who are verified but not confirmed SPA
    offers.verified.not_final_agreement.each do |offer|
      email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
      email_users.each do |user|
        SecondarySaleNotifier.with(record: self, entity_id:, email_method: :notify_spa_offers, msg: "Secondary Sale: #{name}, please accept uploaded SPA.").deliver_later(user)
      end
    end
  end

  def adhoc_notification(custom_notification_id)
    custom_notification = CustomNotification.find(custom_notification_id)

    case custom_notification.to
    when "All Sellers"
      # Get all emails of investors
      offers.each do |offer|
        email_users = offer.investor.notification_users
        email_users.each do |user|
          adhoc_offer(user, custom_notification, offer)
        end
      end

    when "Verified Sellers"
      offers.verified.each do |offer|
        email_users = offer.investor.notification_users
        email_users.each do |user|
          adhoc_offer(user, custom_notification, offer)
        end
      end

    when "Approved Sellers"
      offers.approved.each do |offer|
        email_users = offer.investor.notification_users
        email_users.each do |user|
          adhoc_offer(user, custom_notification, offer)
        end
      end

    when "All Buyers"
      # Get all emails of interests
      interests.each do |interest|
        interest.investor&.notification_users(self)&.each do |user|
          adhoc_interest(user, custom_notification, interest)
        end
      end

    when "Shortlisted Buyers"
      # Get all emails of interests
      interests.short_listed.each do |interest|
        interest.investor&.notification_users(self)&.each do |user|
          adhoc_interest(user, custom_notification, interest)
        end
      end

    end
  end

  def adhoc_interest(user, custom_notification, interest)
    InterestNotifier.with(record: interest, entity_id:, email: user.email, email_method: custom_notification.email_method, msg: custom_notification.body, custom_notification_id: custom_notification.id).deliver_later(user)
  end

  def adhoc_offer(user, custom_notification, offer)
    OfferNotifier.with(record: offer, entity_id:, email: user.email, email_method: custom_notification.email_method, msg: custom_notification.body, custom_notification_id: custom_notification.id).deliver_later(user)
  end
end
