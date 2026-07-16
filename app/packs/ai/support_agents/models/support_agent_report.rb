# frozen_string_literal: true

# Stores per-target results for a SupportAgent run (one report per owner per agent).
#
# @see SupportAgent
# @see PortfolioCompanyAgent
class SupportAgentReport < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :support_agent
  # @!attribute investor
  #   Convenience join for Ransack search — assumes owner_type is "Investor".
  belongs_to :investor, foreign_key: :owner_id, optional: true

  enum :status, { pending: "Pending", completed: "Completed", failed: "Failed" }

  validates :owner_name, length: { maximum: 50 }, allow_blank: true
  validates :support_agent_name, length: { maximum: 50 }, allow_blank: true

  scope :latest_only, -> { where(latest: true) }

  after_create :mark_as_latest!

  # Atomically marks this record as latest and clears the flag on any prior report
  # for the same (owner, support_agent) pair.
  def mark_as_latest!
    self.class.transaction do
      self.class
          .where(owner: owner, support_agent: support_agent)
          .where.not(id: id)
          .update_all(latest: false)
      update_column(:latest, true)
    end
  end

  # Step helper methods
  def steps
    json_fields["steps"] || []
  end

  def current_step
    steps.find { |s| s["status"] == "running" }
  end

  def failed_step
    steps.find { |s| s["status"] == "failed" }
  end

  def progress_percentage
    return 0 if steps.empty?

    completed = steps.count { |s| s["status"].in?(%w[success failed skipped]) }
    (completed.to_f / steps.size * 100).round
  end

  def completed_steps_count
    steps.count { |s| s["status"].in?(%w[success failed skipped]) }
  end

  def total_duration
    json_fields["total_duration_ms"]&.then { |ms| "#{(ms / 1000.0).round(1)}s" }
  end

  def running?
    pending? && json_fields["final_status"] == "running"
  end

  def ready?
    json_fields["final_status"] == "ready"
  end

  def blocked?
    json_fields["final_status"] == "blocked"
  end

  def cancelled?
    json_fields["cancelled_at"].present?
  end

  def never_run?
    json_fields["run_at"].blank?
  end

  def run_at
    json_fields["run_at"]&.then { |t| Time.zone.parse(t) }
  end

  def final_status
    json_fields["final_status"]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[owner_id owner_name owner_type status support_agent_name updated_at]
  end

  # Associations allowed for Ransack join-based search (e.g. investor name filtering).
  #
  # @param _auth_object [Object, nil] optional authorization context
  # @return [Array<String>] allowlisted association names
  def self.ransackable_associations(_auth_object = nil)
    %w[investor]
  end
end
