# CapitalCommitmentAssistantDataManager
#
# Handles the business logic and data retrieval for the CapitalCommitmentAssistant.
# This class contains the implementation of the actions exposed by the assistant's tools.
# It uses Pundit policies to ensure the user only accesses authorized data and
# Ransack for flexible querying.
#
class CapitalCommitmentAssistantDataManager
  # Query object for filtering CapitalCommitments.
  class CapitalCommitmentQuery
    include HasScope

    has_scope :lp_onboarding_complete, type: :boolean
    has_scope :lp_onboarding_incomplete, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering CapitalRemittances.
  class CapitalRemittanceQuery
    include HasScope

    has_scope :paid, type: :boolean
    has_scope :pending, type: :boolean
    has_scope :verified, type: :boolean
    has_scope :unverified, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering CapitalDistributionPayments.
  class CapitalDistributionPaymentQuery
    include HasScope

    has_scope :completed, type: :boolean
    has_scope :incomplete, type: :boolean
    has_scope :notification_sent, type: :boolean
    has_scope :notification_not_sent, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Initializes the data manager.
  #
  # @param user [User] The user context for data retrieval.
  # @param capital_commitment [CapitalCommitment] The commitment context.
  def initialize(user:, capital_commitment: nil)
    @user = user
    @capital_commitment = capital_commitment
  end

  # Retrieves detailed information for a specific capital commitment.
  #
  # @param commitment_id [Integer] ID of the commitment.
  # @return [Hash, String] Commitment details or error message.
  def get_commitment_details(commitment_id:)
    cid = commitment_id || @capital_commitment&.id
    return "No commitment ID provided" unless cid

    commitment = Pundit.policy_scope(@user, CapitalCommitment).includes(:fund, :investor).find_by(id: cid)
    return "Commitment not found or access denied" unless commitment

    {
      id: commitment.id,
      folio_id: commitment.folio_id,
      investor: commitment.investor_name,
      fund: commitment.fund&.name,
      unit_type: commitment.unit_type,
      commitment_date: commitment.commitment_date,
      committed_amount: commitment.committed_amount.format,
      call_amount: commitment.call_amount.format,
      collected_amount: commitment.collected_amount.format,
      distribution_amount: commitment.distribution_amount.format,
      onboarding_completed: commitment.onboarding_completed,
      fund_close: commitment.fund_close,
      currency: commitment.folio_currency,
      view_link: "/capital_commitments/#{commitment.id}"
    }
  end

  # Lists capital remittances for a specific commitment.
  #
  # @param commitment_id [Integer] ID of the commitment.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of capital remittances.
  def list_capital_remittances(commitment_id:, scope: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    cid = commitment_id || @capital_commitment&.id
    raise "commitment_id must be provided or available in context." unless cid

    # Ensure we don't have duplicate keys in the ransack query hash
    # This helps avoid 'Repeated map key' errors in some LLM providers
    ransack_query = ransack_query.transform_keys(&:to_sym)
    ransack_query.delete(:capital_commitment_id_eq)
    ransack_query[:capital_commitment_id_eq] = cid

    relation = Pundit.policy_scope(@user, CapitalRemittance).where(capital_commitment_id: cid).includes(:fund, :capital_call, :capital_commitment)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = CapitalRemittanceQuery.new.perform(collection: relation, params: scope_params)

    remittances = relation.ransack(ransack_query).result
    remittances.map do |r|
      {
        id: r.id,
        capital_call: r.capital_call&.name,
        call_amount: r.call_amount.format,
        collected_amount: r.collected_amount.format,
        due_amount: r.due_amount.format,
        status: r.status,
        verified: r.verified,
        payment_date: r.payment_date,
        remittance_date: r.remittance_date,
        view_link: "/capital_remittances/#{r.id}"
      }
    end
  end

  # Lists distribution payments for a specific commitment.
  #
  # @param commitment_id [Integer] ID of the commitment.
  # @param scope [String, nil] Predefined scope name.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of distribution payments.
  def list_capital_distribution_payments(commitment_id:, scope: nil, sort: nil)
    cid = commitment_id || @capital_commitment&.id
    raise "commitment_id must be provided or available in context." unless cid

    relation = Pundit.policy_scope(@user, CapitalDistributionPayment).includes(:fund, :capital_commitment)
    relation = relation.where(capital_commitment_id: cid)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = CapitalDistributionPaymentQuery.new.perform(collection: relation, params: scope_params)

    payments = sort.present? ? relation.ransack(s: sort).result : relation
    payments.map do |p|
      {
        id: p.id,
        net_payable: p.net_payable.format,
        gross_payable: p.gross_payable.format,
        payment_date: p.payment_date,
        units_quantity: p.units_quantity,
        completed: p.completed,
        notification_sent: p.notification_sent,
        view_link: "/capital_distribution_payments/#{p.id}"
      }
    end
  end

  # Lists documents associated with the commitment.
  def list_documents(commitment_id:, scope: nil, query: {}, sort: nil)
    cid = commitment_id || @capital_commitment&.id
    return [] unless cid

    commitment = Pundit.policy_scope(@user, CapitalCommitment).find_by(id: cid)
    return [] unless commitment

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    # Find documents associated with the commitment
    relation = Pundit.policy_scope(@user, Document).where(owner_id: cid, owner_type: 'CapitalCommitment')
    relation = relation.send(scope) if scope.present? && Document.respond_to?(scope)
    documents = relation.ransack(ransack_query).result

    documents.map do |d|
      {
        id: d.id,
        name: d.name,
        folder: d.folder&.full_path,
        tags: d.tag_list,
        owner_tag: d.owner_tag,
        created_at: (I18n.l(d.created_at) if d.created_at),
        belongs_to: d.owner_type,
        details: d.text,
        esign_status: d.esign_status&.titleize,
        esign_on_page: d.display_on_page&.titleize,
        esign_order_forced: d.force_esign_order,
        file_url: d.file.url,
        view_link: "/documents/#{d.id}"
      }
    end
  end

  # Gets details and text for a specific document.
  def get_document(commitment_id:, document_id: nil, name: nil)
    cid = commitment_id || @capital_commitment&.id
    return "No commitment ID provided" unless cid

    scope = Pundit.policy_scope(@user, Document).where(owner_id: cid, owner_type: 'CapitalCommitment')
    document = if document_id.present?
                 scope.find_by(id: document_id)
               elsif name.present?
                 scope.find_by(name: name) || scope.where("name LIKE ?", "%#{name}%").first
               end

    return "Document not found or access denied" unless document

    {
      id: document.id,
      name: document.name,
      folder: document.folder&.full_path,
      tags: document.tag_list,
      owner_tag: document.owner_tag,
      created_at: (I18n.l(document.created_at) if document.created_at),
      belongs_to: document.owner_type,
      owner_name: (document.owner.respond_to?(:name) ? document.owner.name : document.owner&.to_s),
      file_url: document.file.url,
      view_link: "/documents/#{document.id}"
    }
  end

  # Analyzes documents using RubyLLM.
  def analyze_documents(commitment_id:, prompt:, document_ids: [], document_names: [])
    cid = commitment_id || @capital_commitment&.id
    return "No commitment ID provided" unless cid

    scope = Pundit.policy_scope(@user, Document).where(owner_id: cid, owner_type: 'CapitalCommitment')
    documents = []

    documents += scope.where(id: document_ids).to_a if document_ids.present?

    if document_names.present?
      document_names.each do |name|
        doc = scope.find_by(name: name) || scope.where("name LIKE ?", "%#{name}%").first
        documents << doc if doc
      end
    end

    documents.uniq!

    return "No documents found to analyze." if documents.empty?

    attachments = documents.map { |d| { d.extension.to_sym => d.file.url } }

    chat = RubyLLM.chat
    response = chat.ask prompt, with: attachments
    response.content
  end
end
