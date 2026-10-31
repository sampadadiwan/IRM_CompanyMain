# frozen_string_literal: true

# Tool that resolves a Document id into a short-lived download URL for the LP.
# Used by the LP Assistant after RunQueryTool returns a document_id from the
# `documents` skill (SOAs, drawdown notices, distribution notices, fund data
# room docs, fund reports).
#
# Security: the tool re-verifies — server-side, per owner_type — that the
# requested document belongs to a fund/commitment the LP can access.
# It NEVER trusts the document_id or owner context passed by the LLM.
# On top of that owner check it asks DocumentPolicy#show? for the LP user — the
# same rule as the LP documents screen (approved-or-not-generated, private
# folders, access rights, advisor switch) — and never resolves templates.
# Worked examples H4-1…H4-4, H4-H, H4-X — docs/security/security_review_2026_10.md (H4)
#
# Supported owner_types:
#   CapitalCommitment         -> scoped by fund_id + investor_id
#   CapitalCall               -> scoped by fund_id
#   CapitalDistribution       -> scoped by fund_id
#   Fund                      -> scoped by fund_id (fund.id itself)
# Any other owner_type is rejected.
#
# @see LpChatProvider
# @see RunQueryTool
class DocumentUrlTool < RubyLLM::Tool
  description "Resolve a document_id into a short-lived, clickable download URL. " \
              "Call this AFTER run_query returns a document_id from the documents skill. " \
              "Works for SOAs, drawdown notices, distribution notices, and fund data room docs. " \
              "Embed the returned URL as a Markdown link in your reply so the LP " \
              "can open the PDF in one click. If the tool returns an error, do NOT " \
              "guess the URL — tell the LP the document is unavailable."

  parameter :document_id,
            type: :integer,
            description: 'The documents.id returned by run_query.',
            required: true

  # @param user [User] the LP asking — every document is checked with DocumentPolicy#show? for them (H4)
  # @param entity_ids [Array<Integer>] FM entity_ids the LP can see documents under
  # @param accessible_fund_ids [Array<Integer>] fund_ids scoping Fund/Call/Distribution docs
  # @param accessible_investor_ids [Array<Integer>] investor_ids scoping CapitalCommitment docs
  def initialize(user:, entity_ids:, accessible_fund_ids:, accessible_investor_ids: [])
    super()
    @user = user
    @entity_ids = Array(entity_ids).map(&:to_i).uniq
    @accessible_fund_ids = accessible_fund_ids.map(&:to_i).uniq
    @accessible_investor_ids = accessible_investor_ids.map(&:to_i).uniq
  end

  # @param document_id [Integer] documents.id returned by run_query
  # @return [String] short-lived download URL, or a human-readable error string
  def execute(document_id:)
    # H4 — no user, no policy check: refuse rather than fall back to the owner check alone
    return 'No investor user context available.' if @user.nil?
    return 'No accessible funds for this investor.' if @accessible_fund_ids.empty?
    return 'No accessible fund manager entities for this investor.' if @entity_ids.empty?

    # NOTE: @accessible_investor_ids may be empty for LPs who only have Fund/Call/Distribution
    # access (no personal commitment). SOA-path accessibility check will still fail correctly
    # inside accessible?(doc) because investor_id IN (NULL) returns no rows.

    doc = find_scoped_document(document_id.to_i)
    return "Document #{document_id} not found or not accessible." unless doc
    return "Document #{document_id} has no file attached." if doc.file.blank?

    url = doc.file.url(
      response_content_disposition: "inline; filename=\"#{doc.name_with_extension}\""
    )
    url.to_s
  rescue Shrine::Error, Aws::S3::Errors::ServiceError => e
    "Failed to resolve document URL: #{e.message.lines.first&.strip}"
  end

  SUPPORTED_OWNER_TYPES = %w[CapitalCommitment CapitalCall CapitalDistribution Fund].freeze

  private

  # @param id [Integer]
  # @return [Document, nil] a non-template document scoped to the LP's entities, with a
  #   supported owner_type whose owner row the LP can access, that the LP may open; nil otherwise.
  def find_scoped_document(id)
    # Templates (SOA / call-notice blueprints) are never handed out — H4-2
    doc = Document.not_templates.where(
      id: id,
      entity_id: @entity_ids,
      deleted_at: nil
    ).first
    return nil unless doc
    return nil unless SUPPORTED_OWNER_TYPES.include?(doc.owner_type)
    # Owner row in the LP's funds / own commitments — another LP's SOA stops here (H4-X)
    return nil unless accessible?(doc)
    # The documents screen's own rule: unapproved generated drafts (H4-1, H4-4), private
    # folders (H4-3) and docs without the LP's access right are refused; H4-H passes
    return nil unless Pundit.policy!(@user, doc).show?

    doc
  end

  # @param doc [Document]
  # @return [Boolean] true if the document's owner row is within the LP's scope
  #   (fund_id / investor_id) for its owner_type.
  def accessible?(doc)
    case doc.owner_type
    when 'CapitalCommitment'
      CapitalCommitment.exists?(
        id: doc.owner_id,
        fund_id: @accessible_fund_ids,
        investor_id: @accessible_investor_ids,
        deleted_at: nil
      )
    when 'CapitalCall'
      CapitalCall.exists?(
        id: doc.owner_id,
        fund_id: @accessible_fund_ids,
        deleted_at: nil
      )
    when 'CapitalDistribution'
      CapitalDistribution.exists?(
        id: doc.owner_id,
        fund_id: @accessible_fund_ids,
        deleted_at: nil
      )
    when 'Fund'
      Fund.where(id: @accessible_fund_ids, deleted_at: nil).exists?(id: doc.owner_id)
    else
      false
    end
  end
end
