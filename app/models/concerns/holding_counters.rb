module HoldingCounters
  extend ActiveSupport::Concern

  INVESTMENT_FOR = %w[Employee Founder].freeze
  EQUITY_LIKE = %w[Equity Preferred Options].freeze

  included do
    # Add the quantity to the investment
    counter_culture :investment,
                    column_name: proc { |h| h.call_counter_cache? ? 'quantity' : nil },
                    delta_column: 'quantity'

    counter_culture :investment,
                    column_name: proc { |h| h.call_counter_cache? ? 'amount_cents' : nil },
                    delta_column: 'value_cents'

    # Add the quantity to the aggregate_investment, counter culture does not
    # automatically update aggregate_investment even though the investment is updated
    counter_culture %i[investment aggregate_investment],
                    column_name: proc { |h| h.call_counter_cache? ? h.investment_instrument.downcase : nil },
                    delta_column: 'quantity'

    counter_culture %i[investment entity],
                    column_name: proc { |h| h.call_counter_cache? ? h.investment_instrument.downcase : nil },
                    delta_column: 'quantity'

    counter_culture %i[investment entity],
                    column_name: proc { |h| h.call_counter_cache? ? 'total_investments' : nil },
                    delta_column: 'value_cents'

    counter_culture :funding_round,
                    column_name: proc { |h| h.call_counter_cache? ? 'amount_raised_cents' : nil },
                    delta_column: 'value_cents'

    counter_culture :funding_round,
                    column_name: proc { |h| h.call_counter_cache? ? h.investment_instrument.downcase : nil },
                    delta_column: 'quantity'

    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'allocated_quantity' : nil },
                    delta_column: 'uncancelled_quantity' # quantity keeps getting smaller as excercises happen, but the uncancelled_quantity is what we want to count as allocated

    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'vested_quantity' : nil },
                    delta_column: 'vested_quantity'
    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'lapsed_quantity' : nil },
                    delta_column: 'lapsed_quantity'
    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'cancelled_quantity' : nil },
                    delta_column: 'cancelled_quantity'

    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'gross_avail_to_excercise_quantity' : nil },
                    delta_column: 'gross_avail_to_excercise_quantity'
    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'unexcercised_cancelled_quantity' : nil },
                    delta_column: 'unexcercised_cancelled_quantity'
    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'net_avail_to_excercise_quantity' : nil },
                    delta_column: 'net_avail_to_excercise_quantity'

    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'gross_unvested_quantity' : nil },
                    delta_column: 'gross_unvested_quantity'
    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'unvested_cancelled_quantity' : nil },
                    delta_column: 'unvested_cancelled_quantity'
    counter_culture :option_pool,
                    column_name: proc { |h| h.update_option_pool? ? 'net_unvested_quantity' : nil },
                    delta_column: 'net_unvested_quantity'
  end

  def call_counter_cache?
    investment &&
      INVESTMENT_FOR.include?(holding_type) &&
      EQUITY_LIKE.include?(investment_instrument) &&
      approved
  end

  def update_option_pool?
    investment &&
      INVESTMENT_FOR.include?(holding_type) &&
      investment_instrument == "Options" &&
      approved
  end
end
