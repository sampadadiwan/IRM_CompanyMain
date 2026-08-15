# frozen_string_literal: true

module Api
  module V1
    module Mail
      # POST /api/v1/mail/match
      #
      # Given the participants on an email, returns the owner records it might belong to,
      # plus whether it has already been filed. Both add-ins call this as soon as a message
      # is opened.
      #
      # The already-filed half is new. Neither client could previously tell the user that a
      # thread was already in CapHive, which is the single most common complaint about mail
      # filing tools and the reason duplicates accumulate.
      class MatchesController < BaseController
        def create
          matcher = InvestorEmailMatcher.new(
            # Sender only. To/CC are still sent by the clients and stored on the filed
            # record, but they take no part in matching — a recipient address says little
            # about who an email is about, and a wrong suggestion costs more than an absent
            # one. Mail the fund sent to an investor is filed by picking the record.
            from_email: params[:from_email],
            # Reported by the add-in host, and distinct from current_user.email — the mail
            # account and the CapHive login are separate identities. Excluding it stops the
            # user's own sent mail matching an investor registered against their address.
            mailbox_email: params[:mailbox_email],
            user: current_user
          )
          result = matcher.match

          render json: {
            match_type: result.match_type,
            candidates: result.matches.map { |m| serialize_candidate(m[:investor], m[:reason]) },
            filed: filed_state
          }
        end

        private

        def serialize_candidate(investor, reason)
          {
            id: investor.id,
            type: "Investor",
            name: investor.investor_name,
            # Lets the pane explain itself ("matched on domain") instead of asserting a
            # match the user cannot evaluate.
            reason: reason
          }
        end

        # Has this exact message already been filed, by anyone the current user can see?
        # Keyed on the RFC 5322 Message-ID so it holds across Outlook and Gmail.
        #
        # Scoped twice on purpose. IncomingEmailPolicy::Scope is only
        # `where(entity_id: user.entity_id)`, which is broader than the per-investor access
        # InvestorPolicy::Scope enforces everywhere else — returning on that alone would
        # disclose the investor's name and the filer's name for records the user cannot
        # otherwise see, and Message-IDs from forwarded threads could be used to enumerate
        # them. So the owner must also be visible to this user before anything is named.
        def filed_state
          internet_message_id = params[:internet_message_id].presence
          return { filed: false } if internet_message_id.blank?

          existing = policy_scope(IncomingEmail)
                     .where(internet_message_id: internet_message_id)
                     .includes(:owner, :filed_by_user)
                     .find { |email| owner_visible?(email.owner) }
          return { filed: false } if existing.nil?

          {
            filed: true,
            id: existing.id,
            owner_name: existing.owner.try(:investor_name) || existing.owner.try(:name),
            filed_by: existing.filed_by_user&.full_name,
            filed_at: existing.created_at,
            url: incoming_email_url(existing)
          }
        end

        def owner_visible?(owner)
          return false if owner.nil?

          Pundit.policy!(current_user, owner).file_mail?
        rescue Pundit::NotDefinedError
          false
        end
      end
    end
  end
end
