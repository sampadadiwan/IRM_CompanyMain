class ApplicationRecord < ActiveRecord::Base
  # Raised when a string bound for `eval` contains a code-execution construct.
  class UnsafeEvalError < StandardError; end

  # Denylist of tokens that must never appear inside an eval-ed expression (formulas, fee
  # notes, calculation meta_data, etc).
  #
  # IMPORTANT: this is a GUARD-RAIL, not a complete RCE defence. A denylist can always be
  # evaded by a determined attacker (string building, encoding). It exists to stop the obvious
  # shell / filesystem / CRUD payloads. The real fix is a sandboxed evaluator — see
  # docs/technical/security_review_2026_07.md (finding C1).
  #
  # Matching is performed against the DOWNCASED source, so every token below is lowercase.
  # Word boundaries (\b) guard short/common tokens so legitimate finance terms don't false-trip
  # (e.g. "ratio" must not match \bio\b, "revenue"/"environment" must not match \benv\b,
  # "download" must not match \bload\b, "profile" must not match \bfile\b).
  SAFE_EVAL_REGEX = %r{
    # --- SQL / ActiveRecord bulk mutation (original tokens, kept verbatim for back-compat;
    #     intentionally unbounded so delete_all/destroy_all/update_all/insert_all are caught) ---
    alter | truncate | drop | insert | select | destroy | delete | update | create | save | rollback |
    # --- shell / process execution (backticks and %x were the biggest gap) ---
    ` | %x | \bsystem\b | \bexec\b | \bspawn\b | \bfork\b | \bsyscall\b | popen | open3 | \bpty\b |
    # --- nested eval / binding escape ---
    \beval\b | instance_eval | class_eval | module_eval | \bbinding\b |
    # --- reflective dispatch (defeats send("sys" + "tem") style bypasses) ---
    \bsend\b | __send__ | public_send |
    # --- loading arbitrary code ---
    \brequire\b | require_relative | \bload\b | autoload |
    # --- metaprogramming ---
    constantize | const_get | define_method | method_missing |
    # --- filesystem / process / env access ---
    \bfile\b | \bio\b | \bdir\b | \bkernel\b | \bprocess\b | \bthread\b | \benv\b | fileutils | \bmarshal\b | \bopen\b
  }x

  # Guard an expression at the eval CALL SITE and return it unchanged when safe, so callers can
  # write `eval(ApplicationRecord.safe_eval!(expr), binding)`.
  #
  # Enforced here — not only in model validations — because validations are skipped by
  # update_column/update_columns, insert_all, importers, db:seed, and save(validate: false).
  # The `*_kosher?` validations remain as an early, user-friendly rejection at write time; this
  # is the last line of defence at execution time.
  def self.safe_eval!(source, context: nil)
    str = source.to_s
    return str unless str.downcase.match?(SAFE_EVAL_REGEX)

    label = context ? " (#{context})" : ""
    Rails.logger.error("[safe_eval] blocked unsafe expression#{label}: #{str.truncate(200)}")
    raise UnsafeEvalError, "Refusing to evaluate an unsafe expression#{label}"
  end

  primary_abstract_class
  include DatabaseRoleHelper

  # Currently we write and read from the primary database
  connects_to database: { writing: :primary, reading: :primary }

  # if Rails.env.production?
  #   connects_to database: { writing: :primary, reading: :primary }
  # else
  #   connects_to database: { writing: :primary, reading: :primary_replica }
  # end

  def investors
    investor_list = []
    access_rights.includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  # Check if we should save the record to ES or not
  def index_record?(index_class = nil)
    # For InvestorKyc we have STI, hence index_class is passed in as param, for all else we use the class name
    index_class ||= "#{self.class.name}Index".constantize
    # We need to check if the record is new or any of the searchable fields have changed
    previous_changes.empty? || previous_changes.keys.map(&:to_sym).intersect?(index_class::SEARCH_FIELDS)
    # Only if they have changed we index to ES
  end

  DEFAULT_DATA_TYPE = "String".freeze
  def self.ag_grids_default_columns
    self::STANDARD_COLUMNS.map do |label, key|
      clean_label = label.split(";").first.strip
      clean_key = key.split(";").first.strip
      data_type = if clean_key.include?("custom_fields.")
                    DEFAULT_DATA_TYPE
                  else
                    columns_hash[clean_key]&.type.to_s.capitalize.presence ||
                      columns_hash["#{clean_key}_cents"]&.type.to_s.capitalize.presence ||
                      DEFAULT_DATA_TYPE
                  end

      { label: clean_label, key: clean_key, data_type: data_type }
    end
  end

  def default_currency_units
    currency == "INR" ? "Crores" : "Million"
  end

  # This method is used to find the record in the snapshot table or the main table
  # based on the id passed in. If the id is a composite key, we need to find the record in the snapshot table
  # If the id is not a composite key, we need to find the record in the main table
  # If the id is not found in either table, we return nil
  def self.find_or_snapshot(id)
    # Check if the id is a composite key i.e id_yyyymm-dd
    if id.to_s.include?("_")
      # Extract the base id and date from the composite key
      base_id, = id.split("_")
      # If the id is a composite key, we need to find the record in the snapshot table
      snapshot_class = "#{name}Snapshot".constantize
      snapshot_class.find_by(id: base_id)
    else
      # If the id is not a composite key, we need to find the record in the main table
      find_by(id: id)
    end
  end

  def esign_emails_must_be_valid
    return if esign_emails.blank?

    emails = esign_emails.split(',')

    invalid = emails.grep_v(URI::MailTo::EMAIL_REGEXP)
    errors.add(:esign_emails, "contains invalid email(s): #{invalid.join(', ')}") if invalid.any?
  end

  def self.signed_id_for_user(record, user, expires_in: 15.days)
    # We use a custom verifier to embed both the record ID and the user email
    # for the purpose of a specific action (e.g., uploading KPIs).
    verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
    verifier.generate({ record_id: record.id, email: user.email, model: name }, expires_in: expires_in, purpose: :shared_access)
  end

  # Models that are permitted to be looked up via a signed access token.
  # Extend this list when adding new shared-link flows.
  SIGNED_ID_ALLOWED_MODELS = %w[KpiReport InvestorKyc].freeze

  # Verifies a signed ID and returns the associated record and user.
  # The signed ID is expected to contain :model, :record_id, and :email.
  #
  # @param signed_id [String] The signed token to verify.
  # @return [Array<Object, User>, nil] An array containing [record, user], or nil if invalid.
  #
  # @raise [ActiveSupport::MessageVerifier::InvalidSignature] Handled internally to return nil.
  def self.find_by_signed_id_for_user(signed_id)
    verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
    data = verifier.verify(signed_id, purpose: :shared_access)
    return nil unless data

    # Allowlist prevents arbitrary class instantiation if the secret is ever compromised.
    unless SIGNED_ID_ALLOWED_MODELS.include?(data[:model])
      Rails.logger.warn "Rejected signed_id for disallowed model: #{data[:model]}"
      return nil
    end

    model_class = data[:model].constantize
    record = model_class.find_by(id: data[:record_id])
    # Scope to active users so that deactivating an account immediately revokes all
    # outstanding magic-link tokens tied to that email — unscoped find_by would leave
    # deactivated accounts with valid token access for the remaining 15-day TTL.
    user = User.active.find_by(email: data[:email])
    [record, user]
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.run_all_jobs
    Sidekiq::Queue.find_each do |queue|
      queue.each { |job| job.delete && Object.const_get(job.klass).new.perform(*job.args) }
    end
  end
end
