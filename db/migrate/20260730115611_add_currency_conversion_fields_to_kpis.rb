# frozen_string_literal: true

# Stores pre-conversion value and applied FX rate on kpis for audit trail and re-computation.
# @see Kpi
class AddCurrencyConversionFieldsToKpis < ActiveRecord::Migration[8.1]

  def change
    add_column :kpis, :original_value, :decimal, precision: 20, scale: 6
    add_column :kpis, :fx_rate_used, :decimal, precision: 20, scale: 8
  end
end
