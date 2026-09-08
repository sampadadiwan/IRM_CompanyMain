# frozen_string_literal: true

# Adds legal classification and polymorphic source to support portfolio
# investment obligations alongside the existing side letter obligations.
class AddPortfolioSupportToSideLetterObligations < ActiveRecord::Migration[8.0]
  def change
    add_column :side_letter_obligations, :legal_category, :integer, default: 2, comment: "0=condition_precedent, 1=condition_subsequent, 2=side_letter_obligation"
    add_column :side_letter_obligations, :sourceable_type, :string, limit: 50
    add_column :side_letter_obligations, :sourceable_id, :bigint

    add_index :side_letter_obligations, [:sourceable_type, :sourceable_id], name: "idx_slo_sourceable"
  end
end
