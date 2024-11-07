class AddNotesToCapitalDistribution < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_distributions, :notes, :text
  end
end
