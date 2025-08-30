class AddNameToValuation < ActiveRecord::Migration[8.0]
  def change
    add_column :valuations, :name, :string, limit: 60

    Valuation.includes(:investment_instrument, :owner).all.each do |v|
      if v.investment_instrument.present?
        name = "#{v.investment_instrument} - #{v.valuation_date}" if name.blank?
      else
        name = "#{v.entity} - #{v.valuation_date}" if name.blank?
      end

      v.update_columns(name: name.truncate(60))

    end
  end
end
