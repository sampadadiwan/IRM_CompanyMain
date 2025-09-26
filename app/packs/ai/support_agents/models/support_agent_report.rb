class SupportAgentReport < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :support_agent
end
