module SecondarySaleNotifiers
  extend ActiveSupport::Concern

  def notify_advisors
    SecondarySaleMailer.with(id:).notify_advisors.deliver_later
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

  def notify_spa
    SecondarySaleMailer.with(id:).notify_spa_offers.deliver_later
    SecondarySaleMailer.with(id:).notify_spa_interests.deliver_later
  end
end
