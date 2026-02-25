# frozen_string_literal: true

# Estimates future expenses for a fund using historical AccountEntry data.
#
# Tiered approach:
#   4+ months of data → Linear regression (trend-aware)
#   2-3 months        → Weighted average (recent months weighted higher)
#   1 month           → Last snapshot (current behavior)
#
# @example
#   result = ExpenseEstimator.new(fund, entities, expense_tags).estimate(forecast_days: 90)
#   result[:total]               # => 5000000 (predicted expense in cents for next 90 days)
#   result[:method]              # => "linear_regression"
#   result[:monthly_predictions] # => [1500000, 1650000, 1800000]
#
class ExpenseEstimator
  LOOKBACK_MONTHS = 12
  MIN_MONTHS_FOR_REGRESSION = 4

  def initialize(fund, entities, expense_tags)
    @fund = fund
    @entities = entities
    @expense_tags = expense_tags
  end

  def estimate(forecast_days: 90)
    monthly_totals = build_monthly_totals
    forecast_months = (forecast_days / 30.0).ceil

    if monthly_totals.size >= MIN_MONTHS_FOR_REGRESSION
      predict_with_regression(monthly_totals, forecast_months)
    elsif monthly_totals.size >= 2
      predict_with_weighted_average(monthly_totals, forecast_months)
    elsif monthly_totals.size == 1
      predict_with_snapshot(monthly_totals, forecast_months)
    else
      { total: 0, method: "no_data", monthly_predictions: [], data_points: 0 }
    end
  end

  private

  # Pulls expense entries from last 12 months grouped by month
  # Returns array of { month: Date, total: Integer } sorted by month ASC
  def build_monthly_totals
    cutoff = LOOKBACK_MONTHS.months.ago.to_date.beginning_of_month
    totals = {}

    @entities.each do |entity|
      AccountEntry
        .where(fund_id: @fund.id, entity_id: entity.id)
        .fund_entries
        .where(entry_type: @expense_tags)
        .where(reporting_date: cutoff..)
        .group("DATE_FORMAT(reporting_date, '%Y-%m-01')")
        .sum(:amount_cents)
        .each do |month, amount|
          month_key = month.to_date.beginning_of_month
          totals[month_key] = (totals[month_key] || 0) + amount
        end
    end

    totals.sort_by(&:first).map { |month, total| { month: month, total: total } }
  end

  # 4+ data points: fit a line, predict next N months
  def predict_with_regression(monthly_totals, forecast_months)
    x_data = monthly_totals.each_with_index.map { |_, i| [i.to_f] }
    y_data = monthly_totals.map { |m| m[:total].to_f }

    lr = RubyLinearRegression.new
    lr.load_training_data(x_data, y_data)
    lr.train_normal_equation

    next_index = monthly_totals.size
    predictions = Array.new(forecast_months) do |i|
      [lr.predict([next_index + i.to_f]).round, 0].max
    end

    {
      total: predictions.sum,
      method: "linear_regression",
      monthly_predictions: predictions,
      data_points: monthly_totals.size
    }
  end

  # 2-3 data points: weighted average (recent months count more)
  def predict_with_weighted_average(monthly_totals, forecast_months)
    # Weights: most recent = 3, second = 2, third = 1
    weights = monthly_totals.last(3).each_with_index.map { |_, i| i + 1 }
    values = monthly_totals.last(3).pluck(:total)

    weighted_sum = values.zip(weights).sum { |v, w| v * w }
    weight_total = weights.sum
    avg_month = (weighted_sum.to_f / weight_total).round

    predictions = Array.new(forecast_months, avg_month)

    {
      total: predictions.sum,
      method: "weighted_average",
      monthly_predictions: predictions,
      data_points: monthly_totals.size
    }
  end

  # 1 data point: just repeat the last known value
  def predict_with_snapshot(monthly_totals, forecast_months)
    last_value = monthly_totals.last[:total]
    predictions = Array.new(forecast_months, last_value)

    {
      total: predictions.sum,
      method: "last_snapshot",
      monthly_predictions: predictions,
      data_points: 1
    }
  end
end
