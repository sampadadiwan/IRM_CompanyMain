module Api
  module Outlook
    class EmailMatchesController < ApplicationController
      before_action :authenticate_user!

      def create
        skip_authorization

        Rails.logger.debug { "Received match request with params: #{params.inspect}" }

        matcher = InvestorEmailMatcher.new(
          from_email: params[:from_email],
          to_emails: params[:to_emails],
          cc_emails: params[:cc_emails],
          user: current_user
        )
        result = matcher.match

        render json: {
          match_type: result[:match_type],
          investors: result[:investors].map { |i| { id: i.id, name: i.investor_name } }
        }
      end
    end
  end
end
