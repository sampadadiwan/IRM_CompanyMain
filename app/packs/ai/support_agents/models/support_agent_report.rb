class SupportAgentReport < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :support_agent

  enum :status, { pending: "Pending", completed: "Completed", failed: "Failed" }

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
    json_fields["final_status"] == "running"
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
end
