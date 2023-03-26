class PortfolioAttribution < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :sold_pi, class_name: "PortfolioInvestment"
  belongs_to :bought_pi, class_name: "PortfolioInvestment", touch: true

  before_save :compute_cost_of_sold_cents

  monetize :cost_of_sold_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :bought_pi, column_name: 'sold_quantity', delta_column: 'quantity'
  # counter_culture :bought_pi, column_name: 'cost_of_sold_cents', delta_column: 'cost_of_sold_cents'
  counter_culture :sold_pi, column_name: 'cost_of_sold_cents', delta_column: 'cost_of_sold_cents'
  after_save :update_cost_of_sold

  # Compute the cost_of_sold for the sold_pi
  def update_cost_of_sold
    # This is required to trigger PI.compute_fmv
    sold_pi.reload.save
  end

  def compute_cost_of_sold_cents
    self.cost_of_sold_cents = quantity * bought_pi.cost_cents
  end

  # This is so that the bought_pi net_quantity is updated
  after_destroy_commit -> { bought_pi.reload.save }
end
