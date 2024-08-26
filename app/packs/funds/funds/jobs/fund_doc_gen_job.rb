class FundDocGenJob < DocGenJob
  def templates(_model = nil)
    @fund.documents.where(owner_tag: "Fund Template")
  end

  def models
    [@fund]
  end

  def validate(_fund)
    [true, ""]
  end

  def generator
    FundDocGenerator
  end

  def valid_inputs
    return false unless super

    if @start_date > @end_date
      send_notification("Invalid Dates", @user_id, "danger")
      return false
    end
    true
  end

  def perform(fund_id, start_date, end_date, user_id)
    @fund_id = fund_id
    @fund = Fund.find(fund_id)
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end
  end
end
