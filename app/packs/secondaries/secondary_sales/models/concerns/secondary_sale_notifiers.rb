module SecondarySaleNotifiers
  extend ActiveSupport::Concern

  MAX_TO_SIZE = 40
  NOTIFICATIONS = %w[notify_open_for_offers notify_closing_offers notify_open_for_interests notify_closing_interests notify_allocation notify_spa_sellers notify_spa_buyers adhoc_notification].freeze

  def notify_open_for_interests
    # Get all emails of investors & holding company employees
    all_users = investor_users("Buyer").uniq +
                employee_users("Buyer").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email: user.email, email_method: :notify_open_for_interests, msg: "Secondary Sale: #{name} by #{entity.name}, open for interests").deliver_later(user)
    end
  end

  def notify_closing_interests
    # Get all emails of investors & holding company employees
    all_users = investor_users("Buyer").uniq +
                employee_users("Buyer").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email: user.email, email_method: :notify_closing_interests, msg: "Secondary Sale: #{name} by #{entity.name}, reminder to enter your interest").deliver_later(user)
    end
  end

  def notify_open_for_offers
    # Get all emails of investors & holding company employees
    all_users = investor_users("Seller").uniq +
                employee_users("Seller").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email: user.email, email_method: :notify_open_for_offers, msg: "Secondary Sale: #{name} by #{entity.name}, open for offers").deliver_later(user)
    end
  end

  def notify_closing_offers
    # Get all emails of investors & holding company employees
    all_users = investor_users("Seller").uniq +
                employee_users("Seller").uniq

    all_users.uniq.each do |user|
      SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email: user.email, email_method: :notify_closing_offers, msg: "Secondary Sale: #{name} by #{entity.name}, reminder to enter your offer").deliver_later(user)
    end
  end

  # Notify only verified offers and shortlisted interests
  def notify_allocation
    offers.verified.each do |offer|
      email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
      email_users.each do |user|
        SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email_method: :notify_allocation_offers, msg: "Secondary Sale: #{name} allocation complete").deliver_later(user)
      end
    end

    interests.short_listed.each do |interest|
      interest.investor.notification_users.each do |user|
        SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email_method: :notify_allocation_interests, msg: "Secondary Sale: #{name} allocation complete").deliver_later(user)
      end
    end
  end

  def notify_spa_buyers
    interests.short_listed.not_final_agreement.each do |interest|
      interest.investor.approved_users.each do |user|
        SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email_method: :notify_spa_interests, msg: "Secondary Sale: #{name}, please accept uploaded SPA.").deliver_later(user)
      end
    end
  end

  def notify_spa_sellers
    # Send email to only those who are verified but not confirmed SPA
    offers.verified.not_final_agreement.each do |offer|
      email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
      email_users.each do |user|
        SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email_method: :notify_spa_offers, msg: "Secondary Sale: #{name}, please accept uploaded SPA.").deliver_later(user)
      end
    end
  end

  def adhoc_notification(notification_id)
    notification = CustomNotification.find(notification_id)

    case notification.to
    when "All Sellers"
      # Get all emails of investors & holding company employees
      offers.each do |offer|
        email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
        email_users.each do |user|
          adhoc(user, notification)
        end
      end

    when "Verified Sellers"
      offers.verified.each do |offer|
        email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
        email_users.each do |user|
          adhoc(user, notification)
        end
      end

    when "Approved Sellers"
      offers.approved.each do |offer|
        email_users = offer.offer_type == "Employee" ? [offer.user] : [offer.investor.notification_users]
        email_users.each do |user|
          adhoc(user, notification)
        end
      end

    when "All Buyers"
      # Get all emails of interests
      interests.each do |interest|
        interest.investor&.notification_users(self)&.each do |user|
          adhoc(user, notification)
        end
      end

    when "Shortlisted Buyers"
      # Get all emails of interests
      interests.short_listed.each do |interest|
        interest.investor&.notification_users(self)&.each do |user|
          adhoc(user, notification)
        end
      end

    end
  end

  def adhoc(user, notification)
    SecondarySaleNotifier.with(entity_id:, secondary_sale: self, email: user.email, email_method: notification.email_method, msg: notification.body).deliver_later(user)
  end
end
