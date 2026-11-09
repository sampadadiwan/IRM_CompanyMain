class ApplicationRecord < ActiveRecord::Base
  # Raised when a string bound for `eval` contains a code-execution construct.
  class UnsafeEvalError < StandardError; end

  # Denylist of tokens that must never appear inside an eval-ed expression (formulas, fee
  # notes, calculation meta_data, etc).
  #
  # IMPORTANT: this is a GUARD-RAIL, not a complete RCE defence. A denylist can always be
  # evaded by a determined attacker (string building, encoding). It exists to stop the obvious
  # shell / filesystem / CRUD payloads. The real fix is a sandboxed evaluator — see
  # docs/security/security_review_2026_07.md (finding C1).
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
    \bfile\b | \bio\b | \bdir\b | \bkernel\b | \bprocess\b | \bthread\b | \benv\b | fileutils | \bmarshal\b | \bopen\b |
    # --- OWASP 2026-11 C1: bypasses that got through the list above, closed until FORMULA_SANDBOX=enforce.
    #     method(("sy"+"stem").to_sym).call — a Method object built from a runtime string
    \bmethod\b | public_method | instance_method | singleton_method | singleton_class |
    #     secrets: Rails.application.credentials / secret_key_base
    credentials | secret_key_base | \bsecrets\b | rails\.application |
    #     raw SQL that the select/insert/... words miss when built at runtime ("SEL"+"ECT")
    \bconnection\b | \bexec_ | \bexecute\b |
    #     escaping default scopes, reading private state, enumerating every live object
    unscoped | instance_variable | objectspace | instance_exec | class_exec
    # None of these words appears in any stored formula, fee note, Calculation field or KPI mapping
    # in the production copy (6,571 texts checked 2026-11-09), so no working formula is refused.
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

  # A record never moves to another firm once created: entity_id is written on create and left out of
  # every update. User opts out (advisor / support switches). To re-file records under another firm,
  # use update_all, as entity merge does. docs/modules/funds/funds_api_security_policy_plan.md (A)
  attr_readonly :entity_id

  # For a parent that may move inside a firm (a document's folder, a folder's parent, …): the new parent
  # must be in this record's own firm. The stored firm is the reference, since entity_id never changes
  # (an in-memory change, like Document#setup_entity copying the folder's firm, is not saved).
  # docs/modules/funds/funds_api_security_policy_plan.md (C)
  def validate_parent_in_own_firm(association, record: nil)
    # record: the parent when the caller already has it loaded (Folder#parent_for_callbacks); else read it
    parent = record || public_send(association)
    return if parent.nil?

    parent_firm = parent.is_a?(Entity) ? parent.id : parent.entity_id
    errors.add(association, "must be in this record's firm") unless parent_firm == (entity_id_in_database || entity_id)
  end

  # H10 — the same idea one level down, for a fund record whose parent is another fund record (a
  # payment's remittance, a remittance's call or commitment, a unit's commitment): the parent must be in
  # this record's own fund. The stored fund is the reference, since fund_id is attr_readonly on these models.
  # The parent id is attr_readonly too, and an attempt to move an existing record is refused here rather
  # than left to attr_readonly: that drops the column from the UPDATE but still reports it as a saved
  # change, so counter caches (a payment's collected amount) would move to the other parent anyway.
  # docs/security/security_review_2026_10.md#h10--parent-ids-on-payments-remittances-fund-units
  def validate_parent_in_own_fund(association)
    foreign_key = self.class.reflect_on_association(association).foreign_key
    # Nothing to check unless the parent is being set (create) or changed (update)
    return unless will_save_change_to_attribute?(foreign_key)
    # An existing record never moves to another parent (H10-2, H10-3)
    return errors.add(association, "cannot be changed") if persisted?

    parent = public_send(association)
    return if parent.nil?

    # A new record's parent must be in its fund (H10-1, H10-4, H10-X1)
    errors.add(association, "must be in this record's fund") unless parent.fund_id == (fund_id_in_database || fund_id)
  end

  # L14 — the model class a request param (`owner_type`, `target_type`, …) names, or nil. Replaces
  # `params[:x_type].constantize`, which raises (a 500) on an unknown name and resolves any constant at
  # all (Kernel, ActiveRecord::Base, a service class). Only concrete ApplicationRecord models come back;
  # `allowed:` narrows that to a per-site list of names (e.g. SupportAgent::RUN_TARGET_TYPES), compared
  # as written, so `::Investor` or a subclass name is not a way round the list. Callers answer nil with a
  # 404. docs/security/security_review_2026_10.md (L14 row; first used by N8)
  def self.model_class_from_param(name, allowed: nil)
    # Only a non-blank string can name a model
    name = name.to_s
    return nil if name.blank?
    # The call site's list, when it has one, is checked on the name itself (N8-X); no list: any model
    return nil if allowed&.map(&:to_s)&.exclude?(name)

    # safe_constantize answers nil for an unknown name instead of raising
    klass = name.safe_constantize
    # A concrete model of this app — never Kernel, ActiveRecord::Base or an abstract base like this one
    return nil unless klass.is_a?(Class) && klass < ApplicationRecord && !klass.abstract_class?

    klass
  end

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

  # A create or a destroy must always reach the index -- to add the document, or to remove it.
  # Neither is detectable from `previous_changes` by the time Chewy's after_commit runs:
  #   * create  -- an `after_save` hook that re-saves the row (Entity#run_post_process ->
  #                SetupCompany) applies a second, empty changeset and wipes it.
  #   * destroy -- Trackable makes most models `acts_as_paranoid`, whose soft delete writes
  #                `deleted_at` outside dirty tracking and leaves `destroyed?` false.
  # `previous_changes.empty?` used to stand in for both, but it also matched a save that
  # persisted nothing, so every no-op save enqueued a full reindex. Flag the two real
  # lifecycle events instead.
  after_create :mark_index_lifecycle_event
  after_destroy :mark_index_lifecycle_event

  # Check if we should save the record to ES or not
  def index_record?(index_class = nil)
    # For InvestorKyc we have STI, hence index_class is passed in as param, for all else we use the class name
    index_class ||= "#{self.class.name}Index".constantize
    return true if @index_lifecycle_event || destroyed?

    # Otherwise index only when a field the index actually stores has changed.
    previous_changes.keys.map(&:to_sym).intersect?(index_class::SEARCH_FIELDS)
  end

  def mark_index_lifecycle_event
    @index_lifecycle_event = true
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
