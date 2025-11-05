class SupportAgentReport < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :support_agent

  enum :status, { pending: "Pending", completed: "Completed", failed: "Failed" }

  def self.ransackable_attributes(_auth_object = nil)
    %w[owner_id owner_name owner_type status support_agent_name updated_at]
  end
end
