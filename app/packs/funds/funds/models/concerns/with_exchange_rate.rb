module WithExchangeRate
  extend ActiveSupport::Concern

  included do
    belongs_to :exchange_rate, optional: true
  end

  def convert_currency(from, to, amount, as_of)
    if to == from
      amount
    else
      raise "No date specified" unless as_of

      @exchange_rate = get_exchange_rate(from, to, as_of)
      if @exchange_rate
        # This sets the exchange rate being used for the conversion
        self.exchange_rate = @exchange_rate if respond_to?(:exchange_rate_id)
        amount * @exchange_rate.rate
      else
        errors.add(:base, "Exchange rate from #{from} to #{to} not found for date #{as_of}.")
        # throw(:abort)
      end
    end
  end

  def get_exchange_rate(from, to, as_of)
    exchange_rates = entity.exchange_rates.where(from:, to:).order(as_of: :asc)
    @exchange_rate = as_of ? exchange_rates.where(as_of: ..as_of).last : exchange_rates.latest.last
    @exchange_rate
  end

  # Tracking currency is defined in the fund
  # The TrackingExchangeRate is the exchange_rate between the fund currency and the tracking_currency
  # The date of the exchange_rate is defined by tracking_exchange_rate_date
  # Any model using the tracking currency should provide the date used to find the exchange rate
  def tracking_exchange_rate_date
    raise "#{self.class.name} #{id} Undefined tracking exchange rate date"
  end

  # The TrackingExchangeRate is the exchange_rate between the fund currency and the tracking_currency
  def tracking_exchange_rate(caller_label: "")
    f = if instance_of?(Fund)
          self
        else
          fund
        end

    if f.tracking_currency.present? && f.tracking_currency != f.currency
      er = get_exchange_rate(f.currency, f.tracking_currency, tracking_exchange_rate_date)
      raise "Tracking Exchange rate from #{f.currency} to #{f.tracking_currency} for #{caller_label} not found for date #{tracking_exchange_rate_date}" unless er

      er
    else
      raise "Undefined tracking currency in fund #{f.name}"
    end
  end
end
