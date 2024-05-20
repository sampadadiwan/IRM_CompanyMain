module WithApprovals
  extend ActiveSupport::Concern

  included do
    has_many :approvals
  end

  # This method is called when an approval responses are created
  # It should return the owner for the approval_response, like commtment for a fund, offer for a sale etc
  def approval_for(_investor_id)
    raise "Not implemented"
  end

  # This method is called when an approval is closed
  def post_approval(approval)
    Rails.logger.debug { "#{approval.title}: post approval" }
  end
end
