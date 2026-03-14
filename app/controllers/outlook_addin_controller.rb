class OutlookAddinController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:taskpane]
  before_action :authenticate_user!

  layout 'outlook_addin'

  def taskpane
    skip_authorization
    # This action will render the task pane ERB template
  end

  def investors
    skip_authorization
    @investors = policy_scope(Investor).order(:investor_name)
    render json: @investors.map { |i| { id: i.id, investor_name: i.investor_name } }
  end
end
