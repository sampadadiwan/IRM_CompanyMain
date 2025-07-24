class KeyBizMetricsJob < ApplicationJob
  queue_as :low

  DATES = { day: 1.day, week: 1.week, month: 1.month, quarter: 3.months, year: 1.year, all: 100.years }.freeze

  # This will run early morning
  def perform(run_date = nil)
    @run_date = run_date || (Time.zone.today - 1.day)
    @end_date = @run_date + 1.day
    Chewy.strategy(:sidekiq) do
      # Cleanup old metrics
      delete_all

      # Generate these count metrics
      metrics = %w[logins commitments_count calls_count investors_count investor_access_count investor_advisors_count secondary_sales_count offers_count interests_count deals_count]
      metrics.each do |name|
        create_for_dates(name)
      end

      # Generate these amount metrics
      currencies = %w[USD INR]
      metrics = %w[committed_amount call_amount collected_amount secondary_sales_total_sell_amount]
      currencies.each do |currency|
        metrics.each do |name|
          create_for_dates(name, "#{name.titleize} #{currency}", currency)
        end
      end
    end
  end

  def delete_all
    # Delete metrics for Day metric older than 30 days
    KeyBizMetric.where(metric_type: "Day", run_date: @run_date - 30.days).delete_all
  end

  def create_for_dates(name, label = nil, *params)
    label ||= name.titleize

    DATES.each_key do |key|
      for_date = key == :all ? (@run_date - 10.years) : @run_date.send(:"beginning_of_#{key}")
      if params.present?
        query, value, display_value = send(name.to_s, for_date..(@end_date + 1.day), params)
      else
        query, value, display_value = send(name.to_s, for_date..(@end_date + 1.day))
      end

      kbm = KeyBizMetric.find_or_initialize_by(name: label, metric_type: key.to_s.titleize, run_date: for_date)

      kbm.value = value
      kbm.display_value = display_value
      kbm.query = query.to_sql
      kbm.save
    end
  end

  def logins(date_range)
    query = User.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, last_sign_in_at: date_range)
    [query, query.count, query.count]
  end

  def commitments_count(date_range)
    query = CapitalCommitment.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def calls_count(date_range)
    query = CapitalCall.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def investors_count(date_range)
    query = Investor.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def investor_access_count(date_range)
    query = InvestorAccess.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def investor_advisors_count(date_range)
    query = InvestorAdvisor.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def secondary_sales_count(date_range)
    query = SecondarySale.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def offers_count(date_range)
    query = Offer.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def interests_count(date_range)
    query = Interest.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def deals_count(date_range)
    query = Deal.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, created_at: date_range)
    [query, query.count, query.count]
  end

  def committed_amount(date_range, params)
    currency = params[0]
    query = CapitalCommitment.joins(:fund, entity: :entity_setting).where(entity_setting: { test_account: false }, funds: { currency: }, created_at: date_range)
    value = query.sum(:committed_amount_cents) / 100
    [query, value, Money.new(value, currency.upcase).format]
  end

  def call_amount(date_range, params)
    currency = params[0]
    query = CapitalRemittance.joins(:fund, entity: :entity_setting).where(entity_setting: { test_account: false }, funds: { currency: }, created_at: date_range)
    value = query.sum(:call_amount_cents) / 100
    [query, value, Money.new(value, currency.upcase).format]
  end

  def collected_amount(date_range, params)
    currency = params[0]
    query = CapitalRemittancePayment.joins(:fund, entity: :entity_setting).where(entity_setting: { test_account: false }, funds: { currency: }, created_at: date_range)
    value = query.sum(:amount_cents) / 100
    [query, value, Money.new(value, currency.upcase).format]
  end

  def secondary_sales_total_sell_amount(date_range, params)
    currency = params[0]
    query = SecondarySale.joins(entity: :entity_setting).where(entity_setting: { test_account: false }, entity: { currency: }, created_at: date_range)
    value = query.sum(:total_offered_amount_cents) / 100
    [query, value, Money.new(value, currency.upcase).format]
  end
end
