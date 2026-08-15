class EmailMatchesController < ApplicationController
  before_action :authenticate_user!

  def create
    skip_authorization

    Rails.logger.debug { "Received match request with params: #{params.inspect}" }

    # Sender only — see InvestorEmailMatcher. to_emails/cc_emails may still be posted here
    # by older callers; they are ignored rather than rejected.
    matcher = InvestorEmailMatcher.new(
      from_email: params[:from_email],
      mailbox_email: params[:mailbox_email],
      user: current_user
    )
    result = matcher.match

    render json: {
      match_type: result[:match_type],
      investors: result[:investors].map { |i| { id: i.id, name: i.investor_name } }
    }
  end
end
