# One feed run for one entity, kind (fx / prices / fno / corp_actions), provider and date.
# Re-running the same date updates the row (E11). `missing` lists what could not be loaded, with
# the reason, for the run history and the Fund accounting email; `notified_at` makes that email
# send-once. openspec/changes/fund-market-data — design card ②.
class MarketDataRun < ApplicationRecord
  KINDS = %w[fx prices fno corp_actions].freeze
  STATUSES = %w[running ok partial empty failed].freeze

  belongs_to :entity

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :provider, :run_date, presence: true

  scope :recent_first, -> { order(run_date: :desc, id: :desc) }

  def missing_items
    Array(missing)
  end

  # A weekday run that could not load everything (X6, X7, E14)
  def needs_attention?
    status.in?(%w[partial empty failed])
  end
end
