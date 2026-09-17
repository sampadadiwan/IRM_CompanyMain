# frozen_string_literal: true

module Api
  module V1
    module Mail
      # POST   /api/v1/mail/filings      — file an email against an owner
      # DELETE /api/v1/mail/filings/:id  — undo a filing
      #
      # Both add-ins post the same payload here, so an email filed from Outlook and the
      # same email filed from Gmail produce the same record. Previously each client built
      # its own payload: Outlook sent an HTML body and an EWS item id, Gmail sent a plain
      # text body and a Gmail id, and neither sent the RFC Message-ID that makes them
      # comparable.
      class FilingsController < BaseController
        def create
          result = MailFilingCreate.call(
            user: current_user,
            owner: owner,
            attributes: filing_attributes,
            attachments: params[:attachments]
          )

          return render_error(result[:errors] || "Could not file this email.") unless result.success?

          email = result[:incoming_email]
          render json: {
            success: true,
            id: email.id,
            # Lets the client say "already filed" rather than claiming it just filed it,
            # and makes a double click or a retry indistinguishable from a first attempt.
            already_filed: result[:already_filed].present?,
            url: incoming_email_url(email)
          }, status: result[:already_filed].present? ? :ok : :created
        end

        # POST /api/v1/mail/filings/:id/attachments
        #
        # Separate from #create because the two hosts hand over attachments differently:
        # the Outlook pane can build one multipart request containing the mail fields and
        # the files, while Apps Script posts the JSON filing first and the blobs after.
        def attachments
          email = policy_scope(IncomingEmail).find_by(id: params[:id])
          return render_error("Filing not found.", status: :not_found) if email.nil?
          return render_error("Access denied.", status: :forbidden) unless authorized_for_owner?(email)

          failures = email.save_uploaded_attachments(params[:attachments], user: current_user)
          return render_error(failures) if failures.any?

          render json: { success: true }
        end

        # Undo. The add-ins offer this straight after filing, since the most common
        # mistake is filing against the wrong investor and the old panes gave no way back.
        def destroy
          email = policy_scope(IncomingEmail).find_by(id: params[:id])
          return render_error("Filing not found.", status: :not_found) if email.nil?

          # Gated on the owner, matching #create. IncomingEmailPolicy::Scope is only
          # `where(entity_id:)` and its destroy? is entity-wide, so checking that alone
          # would let any employee delete a filing against an investor they cannot see —
          # while create is restricted to investors in their InvestorPolicy scope.
          return render_error("You do not have permission to remove this filing.", status: :forbidden) unless authorized_for_owner?(email)

          # Not destroy!: the folder this email points at is shared with every other email
          # from the same sender, and cascading into it would delete their documents.
          email.destroy_filing!
          render json: { success: true }
        end

        private

        def owner
          @owner ||= policy_scope(Investor).find(params[:owner_id] || params[:investor_id])
        end

        # True when the current user may file against this filing's owner. Nil owners
        # (SendGrid-ingested mail that never resolved one) are treated as not permitted,
        # since there is no record whose access could be checked.
        def authorized_for_owner?(email)
          return false if email.owner.nil?

          Pundit.policy!(current_user, email.owner).file_mail?
        end

        # Only the mail fields are accepted from the client. entity, owner and
        # filed_by_user are set server-side by MailFilingCreate from the authenticated
        # token, so a client cannot file into another tenant by posting entity_id.
        #
        # to/cc_emails are permitted as arrays as well as strings: Office.js hands back
        # recipient arrays and Apps Script a comma-joined header, and normalising here
        # means neither client has to remember to join.
        def filing_attributes
          permitted = params.permit(
            :subject, :body, :from, :message_id, :internet_message_id, :received_at,
            :to, :cc_emails, { to: [], cc_emails: [] }
          ).to_h.symbolize_keys

          permitted[:to] = join_addresses(permitted[:to])
          permitted[:cc_emails] = join_addresses(permitted[:cc_emails])
          permitted.compact
        end

        def join_addresses(value)
          value.is_a?(Array) ? value.compact_blank.join(", ") : value
        end
      end
    end
  end
end
