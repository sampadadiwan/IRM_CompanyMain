module WithExchangeRate
  extend ActiveSupport::Concern

  included do
    belongs_to :exchange_rate, optional: true
  end

  # Converts with the rate the record's fund accepts (FxRateResolver + SourcePolicy). Records the
  # rate used on the record as before. `policy:` overrides it (e.g. a Valuation converted for a fund).
  # Worked examples H5, E18–E20, X9 — openspec/changes/fund-market-data/business-rules.md
  def convert_currency(from, to, amount, as_of, policy: nil)
    if to == from
      amount
    else
      raise "No date specified" unless as_of

      @exchange_rate = get_exchange_rate(from, to, as_of, policy:)
      if @exchange_rate
        # This sets the exchange rate being used for the conversion
        # A derived rate built on the allocation engine's scratch copy is never stored — don't point at it
        self.exchange_rate = @exchange_rate if respond_to?(:exchange_rate_id) && @exchange_rate.persisted?
        amount * @exchange_rate.rate
      else
        # X9 — Error case: no rate in the fund's accepted sources
        errors.add(:base, FxRateResolver::MissingRate.new(from:, to:, as_of:, policy: policy || fx_source_policy).message)
        raise ActiveRecord::RecordInvalid, self
      end
    end
  end

  # The ExchangeRate row to use (a direct, or a stored derived, rate), or nil
  def get_exchange_rate(from, to, as_of, policy: nil)
    # We sometimes need to use the sqlite exchange rate table specially during allocations.See run_formulas.rb
    # E28 — Edge case: the allocation run resolves exactly like the live screens
    model = self.class.name.include?("Sqlite") ? ExchangeRateSqlite : ExchangeRate
    @exchange_rate = FxRateResolver.lookup(entity_id:, from:, to:, as_of: as_of || Time.zone.today,
                                           policy: policy || fx_source_policy, model:)&.row
    @exchange_rate
  end

  # Which rate sources apply to this record: its fund's (live Fund, also for the allocation engine's
  # SQLite copies), or the entity's defaults for records without a fund.
  def fx_source_policy
    @fx_source_policy ||= begin
      f = if is_a?(Fund) || instance_of?(::FundSqlite)
            self
          elsif respond_to?(:fund)
            fund
          end
      f = Fund.find_by(id: f.id) if f && !f.is_a?(Fund)
      if f
        SourcePolicy.for(f)
      else
        entity = Entity.find_by(id: entity_id)
        entity ? SourcePolicy.for_entity(entity) : SourcePolicy.manual_only
      end
    end
  end

  # Tracking currency is defined in the fund
  # The TrackingExchangeRate is the exchange_rate between the fund currency and the tracking_currency
  # The date of the exchange_rate is defined by tracking_exchange_rate_date
  # Any model using the tracking currency should provide the date used to find the exchange rate
  def tracking_exchange_rate_date
    raise "#{self.class.name} #{id} Undefined tracking exchange rate date"
  end

  # The TrackingExchangeRate is the exchange_rate between the fund currency and the tracking_currency
  def tracking_exchange_rate(caller_label: "", exchange_rate_date: nil)
    exchange_rate_date ||= tracking_exchange_rate_date

    f = if instance_of?(Fund)
          self
        else
          fund
        end

    if f.tracking_currency.present? && f.tracking_currency != f.currency
      er = get_exchange_rate(f.currency, f.tracking_currency, exchange_rate_date)
      raise "Tracking Exchange rate from #{f.currency} to #{f.tracking_currency} for #{caller_label} not found for date #{exchange_rate_date}" unless er

      er
    else
      raise "Undefined tracking currency in fund #{f.name}"
    end
  end
end
