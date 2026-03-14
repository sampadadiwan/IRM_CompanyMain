module Api
  class IncomingEmailsController < ApplicationController
    before_action :authenticate_user!

    def create
      investor = Investor.find(params[:investor_id])
      authorize investor, :update?

      incoming_email = IncomingEmail.new(incoming_email_params)
      skip_authorization # Skip authorization for the incoming_email object itself as we've authorized the investor
      incoming_email.owner = investor
      incoming_email.entity = investor.entity
      incoming_email.filed_by_user = current_user
      incoming_email.received_at ||= Time.current

      if incoming_email.save
        render json: { success: true, id: incoming_email.id }
      else
        render json: { success: false, errors: incoming_email.errors.full_messages }, status: :unprocessable_content
      end
    end

    private

    def incoming_email_params
      params.permit(:subject, :body, :from, :to, :cc_emails, :message_id, :internet_message_id, :received_at)
    end
  end
end
