# Contract notes and redemption advices on a dealing date (open-ended-funds § Dealing-date documents).
# Templates are optional:
#  - no "Contract Note Template" / "Redemption Advice Template" for the folio → the investor email goes
#    out as soon as units are allotted / the redemption is paid (no PDF);
#  - a template → ① Generate documents (EvergreenDocumentsJob) → ② Approve & send (emails with the PDF).
class EvergreenDealingDocuments
  TAGS = { contract_note: "Contract Note Template", redemption_advice: "Redemption Advice Template" }.freeze

  class << self
    def kind(fill) = fill.subscription? ? :contract_note : :redemption_advice

    # The folio's template for this fill (a folio-level template overrides the fund's), or nil
    def template_for(fill)
      fill.dealing_order.capital_commitment&.templates(TAGS[kind(fill)])&.first
    end

    # Does the fund use any document template? (drives the journey's optional document steps)
    def templates?(fund)
      fund.documents.templates.exists?(owner_tag: TAGS.values)
    end

    # Called once units are allotted / cancelled for a fill (also on a retried allotment)
    def settled(fill)
      send_email(fill) unless fill.document_sent_at || template_for(fill)
      fill.dealing_order.journey_progress!
      fill.dealing_date.journey_progress!
    end

    # Settled fills of the dealing date that need a document generated
    def to_generate(dealing_date)
      dealing_date.dealing_fills.where.not(fund_unit_id: nil).where(document_id: nil, document_sent_at: nil)
                  .includes(dealing_order: :capital_commitment).select { |f| template_for(f) }
    end

    # Generated documents not yet sent — waiting for approval, or approved but the send failed midway
    # (Approve & send picks both up, so a failure can be retried)
    def awaiting_approval(dealing_date)
      dealing_date.dealing_fills.where(document_sent_at: nil).where.not(document_id: nil).includes(:document)
                  .select(&:document)
    end

    # Settled, unsent fills with neither a document nor a template (the template was removed after
    # settlement): they get the plain email so the date can still close
    def orphaned(dealing_date)
      dealing_date.dealing_fills.where.not(fund_unit_id: nil).where(document_id: nil, document_sent_at: nil)
                  .includes(dealing_order: :capital_commitment).reject { |f| template_for(f) }
    end

    # ① Generate every missing document (idempotent: only fills without one); then tell approvers
    def generate(dealing_date, user_id)
      made = 0
      errors = []
      orphaned(dealing_date).each { |fill| send_email(fill) }
      to_generate(dealing_date).each do |fill|
        # Lock and re-check, so a double click or a parallel Regenerate can't make two documents
        fill.with_lock do
          next if fill.document_id

          fill.update!(document: EvergreenDocTemplateGenerator.new(fill, template_for(fill), user_id).generated_document)
          made += 1
        end
      rescue StandardError => e
        errors << "#{fill.dealing_order.investor.investor_name}: #{e.message}"
        Rails.logger.error("[EvergreenDealingDocuments] fill #{fill.id}: #{e.class}: #{e.message}")
      end
      EvergreenAlerts.documents_generated(dealing_date) if made.positive?
      dealing_date.journey_progress!
      [made, errors]
    end

    # ② Approve every generated document of the date and email each investor with the PDF attached
    def approve_and_send(dealing_date, user)
      sent = 0
      awaiting_approval(dealing_date).each do |fill|
        # Approve under the fill's lock and re-check, so two approvers can't send twice
        approved = fill.with_lock do
          next false if fill.document_sent_at

          fill.document.update!(approved: true, approved_by_id: user.id) unless fill.document.approved
          true
        end
        next unless approved

        send_email(fill)
        sent += 1
      end
      dealing_date.journey_progress!(actor: user)
      sent
    end

    # Regenerate one document, only while it is not approved
    def regenerate(fill, user_id)
      return "Approved documents can't be regenerated" if fill.document&.approved
      # X92: only settled orders (units allotted / cancelled) have a document
      return "Documents are generated once the order is settled" unless fill.fund_unit_id
      return "No template for this document" unless (template = template_for(fill))

      old = fill.document
      fill.update!(document: nil)
      old&.destroy
      fill.update!(document: EvergreenDocTemplateGenerator.new(fill, template, user_id).generated_document)
      nil
    end

    # The investor email (the mailer attaches the fill's document when it is approved)
    def send_email(fill)
      EvergreenNotifier.public_send(kind(fill), fill)
      fill.update!(document_sent_at: Time.current)
      fill.dealing_order.journey_progress!
    end
  end
end
