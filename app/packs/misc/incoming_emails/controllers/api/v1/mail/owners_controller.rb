# frozen_string_literal: true

module Api
  module V1
    module Mail
      # GET /api/v1/mail/owners?q=acme
      #
      # Typeahead over the records an email can be filed against, for when matching finds
      # nothing or the user wants to override the match.
      #
      # Replaces /outlook_addin/investors, which returned every investor in the entity with
      # no search, no limit and no pagination — a multi-megabyte payload rendered into a
      # dropdown inside a 320px pane. The Gmail add-on had no override at all: an unmatched
      # email simply could not be filed.
      class OwnersController < BaseController
        # Caps the response regardless of query. A typeahead list longer than this is not
        # usable in either host's UI, and the point is to never load the full table.
        LIMIT = 25

        def index
          render json: { owners: investors.map { |i| serialize(i) } }
        end

        private

        def investors
          scope = policy_scope(Investor)
          query = params[:q].to_s.strip

          scope = scope.where(Investor.arel_table[:investor_name].matches("%#{sanitize_like(query)}%")) if query.present?

          scope.order(:investor_name).limit(LIMIT).select(:id, :investor_name, :primary_email)
        end

        # Escapes LIKE metacharacters so a user typing "50%" searches for that literal
        # string instead of matching everything.
        def sanitize_like(value)
          ActiveRecord::Base.sanitize_sql_like(value)
        end

        def serialize(investor)
          { id: investor.id, type: "Investor", name: investor.investor_name, email: investor.primary_email }
        end
      end
    end
  end
end
