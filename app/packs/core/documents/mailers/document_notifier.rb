# Resolves the cc addresses for every document notification email - entity-wide,
# per-stakeholder and per-commitment. The full picture, including why a fund data room
# document used to email with only the entity-wide cc, is in
# docs/modules/notifications/document_notification_cc_resolution.md.
class DocumentNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    DocumentMailer
  end

  def email_method(_notification = nil)
    params[:email_method] || :notify_new_document
  end

  def email_data(notification)
    # Resolved OUTSIDE any `if record.owner` guard. The sender
    # (Document#send_notification_for_owner / DocumentSender) now passes the stakeholder that
    # the delivering access right names, and `owner` is an optional belongs_to - nesting this
    # inside an owner check would swallow that value for an owner-less document and drop both
    # cc sources again. A commitment-owned document still answers for itself, which keeps
    # direct sends (no investor_id passed) behaving exactly as before.
    investor_id = params[:investor_id]
    investor_id ||= record.owner.investor_id if record.owner.respond_to?(:investor_id)

    fund_id = record.owner.fund_id if record.owner.respond_to?(:fund_id)
    # A Fund owns its own data room documents and answers false to respond_to?(:fund_id), so
    # ask it for its id directly. This is load-bearing, not cosmetic: fund_id is what scopes
    # commitment_ccs below to THIS fund's commitments - without it the cc addresses would
    # either be missed or pulled from the investor's commitments in unrelated funds.
    fund_id ||= record.owner.id if record.owner_type == "Fund"
    fund_id ||= record.fund_id if record.respond_to?(:fund_id)

    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      document_id: record.id,
      entity_id: params[:entity_id],
      fund_id: fund_id,
      # Passed on to ApplicationMailer#setup_cc, which will only look up this contact's
      # InvestorAccess#cc when an investor_id is present.
      investor_id: investor_id,
      msg: params[:msg],
      email_method: params[:email_method],
      additional_ccs: commitment_ccs(fund_id, investor_id)
    }
  end

  # The commitment-level cc addresses to add on top of entity_setting.cc and
  # InvestorAccess#cc (both applied by ApplicationMailer#setup_cc).
  #
  # A commitment-owned document has exactly one commitment to read `cc` from. A Fund-owned one
  # - anything in the fund's data room - has none of its own, but the access right delivering
  # it names a stakeholder, so use that stakeholder's commitments in this fund. An investor can
  # hold several commitments in the same fund, each with its own cc, so union their addresses
  # rather than picking one (same reasoning as FundInvestorKycNotifier).
  #
  # Fund-scoped in practice: no other data room owner (Deal, SecondarySale,
  # InvestmentOpportunity) responds to fund_id, and neither does Document, so fund_id is only
  # ever populated for a Fund owner. Those documents keep returning nil here, exactly as before.
  #
  # `cc` is a json_fields property, not a column, so the rows have to be loaded - narrowed to
  # the two columns that read needs. The scope is one investor in one fund, so this is a
  # handful of rows.
  def commitment_ccs(fund_id, investor_id)
    return record.owner&.cc if record.owner_type == "CapitalCommitment"
    return nil if fund_id.blank? || investor_id.blank?

    CapitalCommitment.where(fund_id:, investor_id:)
                     .select(:id, :json_fields)
                     .filter_map(&:cc)
                     # Each cc is itself a comma-separated list, so split before deduping -
                     # otherwise two commitments sharing an advisor cc him twice.
                     .flat_map { |cc| cc.split(",") }
                     .map(&:strip)
                     .compact_blank
                     .uniq
                     .join(",")
                     .presence
  end

  notification_methods do
    def message
      @document = record
      @custom_notification ||= custom_notification
      @custom_notification&.subject || params[:msg] || "Document Uploaded: #{@document&.name}"
    end

    def custom_notification
      @document ||= record
      @custom_notification ||= @document&.entity&.custom_notification(params[:email_method], custom_notification_id: params[:custom_notification_id])
      @custom_notification
    end

    def url
      document_path(id: record, sub_domain: record.entity.sub_domain)
    end
  end
end
