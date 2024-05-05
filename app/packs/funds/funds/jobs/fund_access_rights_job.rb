class FundAccessRightsJob < ApplicationJob
  queue_as :low
  retry_on StandardError, attempts: 1
  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, create_missing, user_id = nil)
    Chewy.strategy(:active_job) do
      # Need to generate docs for all commitments of the fund
      fund = Fund.find(fund_id)
      fund.check_access_rights(create_missing:)
      UserAlert.new(user_id:, message: "AccessRights creation completed", level: "info").broadcast
    end
  end
end
