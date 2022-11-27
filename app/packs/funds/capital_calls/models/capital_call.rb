class CapitalCall < ApplicationRecord
  include WithFolder
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include FundScopes

  belongs_to :entity
  belongs_to :fund, touch: true

  belongs_to :form_type, optional: true
  belongs_to :approved_by_user, class_name: "User", optional: true
  serialize :properties, Hash

  has_many :capital_remittances, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy

  validates :name, :due_date, :percentage_called, presence: true
  validates :percentage_called, numericality: { in: 0..100 }

  monetize :call_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  after_save :send_notification, if: :approved
  def send_notification
    CapitalCallJob.perform_later(id) if saved_change_to_approved?
  end

  def setup_folder_details
    setup_folder_from_path("#{fund.folder_path}/Capital Calls/#{name}")
  end

  def to_s
    "#{name}: #{percentage_called}%"
  end

  def due_amount
    call_amount - collected_amount
  end

  def percentage_raised
    call_amount_cents.positive? ? (collected_amount_cents * 100.0 / call_amount_cents).round(2) : 0
  end

  def notify_capital_call
    FundMailer.with(id:).notify_capital_call.deliver_later
  end

  def reminder_capital_call
    FundMailer.with(id:).reminder_capital_call.deliver_later
  end
end
