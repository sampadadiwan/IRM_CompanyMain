module DocGeneratorHelper
  # Typed value object for account entry breakdown rows.
  # Replaces OpenStruct for explicit shape and better performance
  # (OpenStruct allocates a per-instance method table; Struct does not).
  AccountEntryBreakdown = Struct.new(
    :name, :audit_name, :reporting_date, :folio_id, :amount, :entry_type,
    keyword_init: true
  )

  # The columns the breakdown reads, plus id so the AR objects keep their identity.
  # Loading full rows pulls in wide columns (json_fields, notes, explanation) we never read.
  BREAKDOWN_COLUMNS = %i[id name reporting_date folio_id amount_cents entry_type capital_commitment_id].freeze

  # Current process resident set size in MB.
  # Reads /proc/self/status on Linux; falls back to `ps` elsewhere (e.g. macOS dev machines)
  def current_rss_mb
    if File.readable?("/proc/self/status")
      File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i / 1024
    else
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    end
  end

  # Log the current RSS with a label and return it, so callers can diff before/after
  def log_memory_usage(label)
    rss_mb = current_rss_mb
    Rails.logger.info { "[MemoryUsage] #{label}: #{rss_mb} MB RSS" }
    rss_mb
  end

  # Warn if memory grew during the block bounded by rss_before_mb and was not released.
  # Ruby rarely returns freed heap pages to the OS, so RSS still elevated after a full
  # GC.start indicates objects are genuinely retained (e.g. a cached association holding
  # a large loaded relation), not just allocator slack.
  def warn_if_memory_retained(rss_before_mb, label, threshold_mb: 100)
    GC.start # full GC so anything unreachable is collected before we measure retention
    rss_after_mb = current_rss_mb
    retained_mb = rss_after_mb - rss_before_mb
    return if retained_mb < threshold_mb

    Rails.logger.warn do
      "[MemoryUsage] #{label}: RSS grew by #{retained_mb} MB and was not released after GC " \
        "(#{rss_before_mb} MB -> #{rss_after_mb} MB) - possible retained relation/association"
    end
  end

  # Extract cumulative flag from method name based on scope type
  # @param method_name [String] The merge field name (e.g., 'fundaecumulative_revenue')
  # @param scope_type [Symbol] The scope type (:fund_entries, :kyc_commitments, :folio_commitment, :aes_breakdown)
  # @return [Boolean] True if the field has a cumulative suffix for the scope type
  def extract_cumulative_flag(method_name, scope_type)
    prefix = { fund_entries: "fundaecumulative_", kyc_commitments: "kycaecumulative_",
               folio_commitment: "folioaecumulative_", aes_breakdown: "aescumulative_" }[scope_type]
    method_name.starts_with?(prefix)
  end

  # Extract method name by removing prefix based on scope type
  # @param method_name [String] The full merge field name (e.g., 'fundae_revenue')
  # @param scope_type [Symbol] The scope type (:fund_entries, :kyc_commitments, :folio_commitment, :aes_breakdown)
  # @param cumulative [Boolean] Whether the field has cumulative flag
  # @return [String] The field name without prefix (e.g., 'revenue')
  def extract_method_name(method_name, scope_type, cumulative)
    case scope_type
    when :fund_entries
      cumulative ? method_name.gsub("fundaecumulative_", "") : method_name.gsub("fundae_", "")
    when :kyc_commitments
      cumulative ? method_name.gsub("kycaecumulative_", "") : method_name.gsub("kycae_", "")
    when :folio_commitment
      cumulative ? method_name.gsub("folioaecumulative_", "") : method_name.gsub("folioae_", "")
    when :aes_breakdown
      cumulative ? method_name.gsub("aescumulative_", "") : method_name.gsub("aes_", "")
    end
  end

  # Normalize method name to match account entry names in database
  # Converts to lowercase, replaces underscores with spaces, removes special chars
  # @param method_name [String] The method name to normalize (e.g., 'revenue_earned')
  # @return [String] Normalized name for database matching (e.g., 'revenue earned')
  def normalize_method_name(method_name)
    method_name.to_s.downcase.tr('_', ' ').gsub(/[^a-z0-9 ]/, '').gsub(/\s+/, ' ')
  end

  # Build account entries scope with filters based on scope type
  # Applies date range, cumulative flag, entry type, and scope-specific filters
  # @param account_entries [ActiveRecord::Relation] The account entries collection to filter
  # @param scope_type [Symbol] The scope type (:fund_entries, :kyc_commitments, :folio_commitment, :aes_breakdown)
  # @param cumulative [Boolean] Filter by cumulative flag
  # @param entry_type [String, nil] Filter by specific entry type if provided
  # @param normalized_pattern [String] The normalized name pattern to match
  # @param as_of_date [Date] The reference date for the reporting_date range
  # @param capital_commitment [CapitalCommitment, nil] Required for :folio_commitment and :aes_breakdown
  # @param kyc_commitments [ActiveRecord::Relation, nil] Required for :kyc_commitments and :aes_breakdown
  # @return [ActiveRecord::Relation] Filtered account entries query
  def build_account_entries_scope(account_entries, scope_type, cumulative, entry_type, normalized_pattern, as_of_date, capital_commitment = nil, kyc_commitments = nil)
    entries = account_entries.where(
      cumulative: cumulative,
      reporting_date: (as_of_date - 1.month)..as_of_date
    )

    entries = entries.where(entry_type: entry_type) if entry_type.present?

    # Apply scope-specific filters
    case scope_type
    when :fund_entries
      entries = entries.fund_entries
    when :kyc_commitments, :aes_breakdown
      entries = entries.where(capital_commitment_id: kyc_commitments.select(:id))
    when :folio_commitment
      entries = entries.where(capital_commitment_id: capital_commitment.id)
    end

    entries.where(
      "TRIM(REGEXP_REPLACE(REGEXP_REPLACE(LOWER(name), '[^a-z0-9 ]', ''), ' +', ' ')) = ?",
      normalized_pattern
    )
  end

  # Fetch account entries breakdown for a given field
  # Extracts and normalizes field name, queries matching account entries, and returns the latest AE per distinct folio_id
  # @param field_name [String] The merge field name (e.g., 'aes_revenue')
  # @param account_entries [ActiveRecord::Relation] The account entries collection to query
  # @param scope_type [Symbol] The scope type (:fund_entries, :kyc_commitments, :folio_commitment, :aes_breakdown)
  # @param as_of_date [Date] The reference date for the reporting_date range
  # @param currency [String] The currency code for Money objects
  # @param capital_commitment [CapitalCommitment, nil] Required for :folio_commitment and :aes_breakdown
  # @param kyc_commitments [ActiveRecord::Relation, nil] Required for :kyc_commitments and :aes_breakdown
  # @param distribution [CapitalDistribution, nil] Optional distribution for fee_type/audit_name mapping
  # @return [Array<AccountEntryBreakdown>] Array of breakdown items with properties:
  #   - name [String] Display name (from distribution.audit_name or entry.name)
  #   - reporting_date [Date] The date the entry was recorded
  #   - folio_id [String] Folio identifier
  #   - amount [Money] The entry amount as Money object
  #   - entry_type [String] The type of entry (from distribution or database)
  def fetch_account_entries_breakdown(field_name, account_entries, scope_type, as_of_date, currency, capital_commitment = nil, kyc_commitments = nil, distribution = nil)
    # none? issues a cheap `SELECT 1 ... LIMIT 1`; blank? would load and cache the ENTIRE
    # relation (the whole fund's ledger when called with fund.account_entries)
    return [] if account_entries.none?

    cumulative = extract_cumulative_flag(field_name, scope_type)
    method_name_str = extract_method_name(field_name, scope_type, cumulative)
    method_name_str, entry_type = method_name_str.split("_enttype_")

    normalized_pattern = normalize_method_name(method_name_str)

    entries = build_account_entries_scope(
      account_entries,
      scope_type,
      cumulative,
      entry_type,
      normalized_pattern,
      as_of_date,
      capital_commitment,
      kyc_commitments
    )

    # Load once, restricted to the columns we actually read
    records = entries.select(*BREAKDOWN_COLUMNS).to_a
    return [] if records.empty?

    dist_fee_map = {}
    if distribution.present?
      distribution.distribution_fees.each do |fee|
        dist_fee_map[fee.name.downcase] = { audit_name: fee.audit_name.presence || fee.name, fee_type: fee.fee_type }
      end
    end

    latest_entries_by_folio = records.group_by(&:folio_id).map do |_folio_id, folio_entries|
      folio_entries.max_by(&:reporting_date)
    end.sort_by(&:capital_commitment_id)

    latest_entries_by_folio.map do |entry|
      AccountEntryBreakdown.new(
        name: entry.name,
        audit_name: dist_fee_map[entry.name.downcase]&.dig(:audit_name) || "",
        reporting_date: entry.reporting_date,
        folio_id: entry.folio_id,
        amount: Money.new(entry.amount_cents, currency),
        entry_type: dist_fee_map[entry.name.downcase]&.dig(:fee_type) || entry.entry_type
      )
    end
  end
end
