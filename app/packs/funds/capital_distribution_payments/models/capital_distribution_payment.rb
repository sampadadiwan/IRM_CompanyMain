class CapitalDistributionPayment < ApplicationRecord
  include FundScopes
  update_index('capital_distribution_payment') { self }

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :capital_distribution, touch: true
  belongs_to :investor
  belongs_to :form_type, optional: true

  monetize :amount_cents, with_currency: ->(i) { i.entity.currency }

  counter_culture :fund,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil },
                  delta_column: 'amount_cents'

  counter_culture :capital_distribution,
                  column_name: proc { |r| r.completed ? 'distribution_amount_cents' : nil }, delta_column: 'amount_cents'

  after_save :send_notification, if: :completed
  def send_notification
    CapitalDistributionPaymentsMailer.with(id:).send_notification.deliver_later if saved_change_to_completed? && capital_distribution.approved
  end
end
