class InvestorNoticeJob < ApplicationJob
  queue_as :default

  def perform
    InvestorNotice.where("end_date < ?", Time.zone.today).update(active: false)
  end
end
