class ApplicationRecord < ActiveRecord::Base
  SAFE_EVAL_REGEX = /alter|truncate|drop|insert|select|destroy|delete|update|create|save|rollback|system|fork/

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
  SIGNED_ID_ALLOWED_MODELS = %w[KpiReport].freeze

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
    user = User.find_by(email: data[:email])
    [record, user]
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
