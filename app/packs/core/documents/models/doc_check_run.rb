# One check of one record's documents. A completed (done), non-trial run becomes the record's current
# run — its results are what the tab, the attention list and the journey read. A run that could not run
# never becomes current, so the earlier results stay.
# See openspec/changes/document-checks/design.md (card ④ Run, Lifecycles).
class DocCheckRun < ApplicationRecord
  STATUSES = %w[queued running done could_not_run].freeze
  TRIGGERS = %w[manual bulk again trial].freeze
  # A queued/running run older than this is treated as lost and expired
  EXPIRE_AFTER = 30.minutes

  belongs_to :entity
  belongs_to :record, polymorphic: true
  belongs_to :user, optional: true
  has_many :doc_check_results, -> { order(:id) }, dependent: :delete_all, inverse_of: :doc_check_run

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :real, -> { where(trial: false) }
  scope :active, -> { where(status: %w[queued running]) }
  scope :for_record, ->(record) { where(record_type: DocChecks::Registry.record_type_of(record), record_id: record.id) }

  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

  def active?
    queued? || running?
  end

  # An active run nobody will finish (the worker died). Worked example: card ④ Expiry.
  def expired?
    active? && created_at < EXPIRE_AFTER.ago
  end

  def expire!
    update!(status: "could_not_run", error_message: "Timed out", finished_at: Time.current, current: false)
  end

  def attention_count
    (counts || {})["attention"].to_i
  end

  def ok_count
    (counts || {})["ok"].to_i
  end
end
