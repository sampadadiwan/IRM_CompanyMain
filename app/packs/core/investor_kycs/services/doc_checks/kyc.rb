# The Investor KYC entry of the Document Checks registry: which documents a KYC has, which KYC fields a
# check may fill in or compare (an explicit allowlist — control columns like verified or entity_id are
# never writable), how values are read and written, and the hooks back into the KYC journey.
# See openspec/changes/document-checks/design.md (card ② Registry).
module DocChecks
  class Kyc
    # Standard KYC columns a check may use. Explicit on purpose: a column added to investor_kycs is not
    # writable by Document Checks until it is listed here. loose = names/addresses (word order ignored).
    COLUMNS = {
      "full_name" => { label: "Full name", loose: true },
      "PAN" => { label: "PAN" },
      "address" => { label: "Address", loose: true },
      "corr_address" => { label: "Correspondence address", loose: true },
      "birth_date" => { label: "Date of birth", date: true },
      "expiry_date" => { label: "Expiry date", date: true },
      "bank_name" => { label: "Bank name" },
      "bank_branch" => { label: "Bank branch" },
      "bank_account_number" => { label: "Bank account number" },
      "bank_account_type" => { label: "Bank account type" },
      "ifsc_code" => { label: "IFSC code" },
      "esign_emails" => { label: "eSign emails" },
      "residency" => { label: "Residency" }
    }.freeze

    # KYC form types whose custom fields are offered
    FORM_TYPE_NAMES = %w[InvestorKyc IndividualKyc NonIndividualKyc].freeze

    # Custom field types that can't hold a value read from a document
    SKIPPED_FIELD_TYPES = %w[File Calculation GridColumns].freeze

    class << self
      def record_label
        "KYC"
      end

      def record_class
        ::InvestorKyc
      end

      # Where a person fixes the record by hand ("Edit KYC")
      def edit_path(kyc)
        Rails.application.routes.url_helpers.edit_investor_kyc_path(kyc)
      end

      def show_path(kyc)
        Rails.application.routes.url_helpers.investor_kyc_path(kyc)
      end

      # Every document name a check can be set up for (the settings page cards): both KYC document lists
      # plus the required file fields of the entity's KYC forms, de-duplicated ignoring case, first
      # spelling kept. Worked example E1 — openspec/changes/document-checks/design.md#worked-examples
      def document_names(entity)
        setting = entity.entity_setting
        names = [setting&.individual_kyc_doc_list, setting&.non_individual_kyc_doc_list]
                .flat_map { |list| list.to_s.split(",") }.map(&:strip)
        # Required File fields on any of the entity's KYC forms are documents too
        names += ::FormCustomField.where(form_type_id: kyc_form_type_ids(entity), field_type: "File", required: true)
                                  .pluck(:label, :name).map { |label, name| label.presence || name.to_s.humanize }
        names.compact_blank.uniq(&:downcase)
      end

      # The documents this KYC has, by its own type (individual / non-individual) and form.
      # Worked example E6 — openspec/changes/document-checks/design.md#worked-examples
      def document_names_for(kyc)
        kyc.required_document_names
      end

      def find_document(kyc, name)
        kyc.find_document_by_name(name)
      end

      # The fields a check may use: the allowlisted columns, then the non-file custom fields of the
      # entity's KYC forms (deduplicated by name; the first form's label wins).
      def fields_for(entity)
        columns = COLUMNS.map do |name, opts|
          Field.new(name:, label: opts[:label], storage: :column, loose: opts[:loose] || false, date: opts[:date] || false)
        end
        custom = ::FormCustomField.where(form_type_id: kyc_form_type_ids(entity))
                                  .where.not(field_type: SKIPPED_FIELD_TYPES)
                                  .order(:form_type_id, :position).pluck(:name, :label, :field_type)
                                  .uniq(&:first)
                                  .reject { |name, _, _| COLUMNS.key?(name) }
                                  .map do |name, label, field_type|
          Field.new(name:, label: label.presence || name.to_s.humanize, storage: :json,
                    loose: name.to_s.match?(/name|address/i), date: field_type == "DateField")
        end
        columns + custom
      end

      # The field a check names, or nil when it is not (or no longer) allowed
      def field(entity, name)
        fields_for(entity).find { |f| f.name == name.to_s }
      end

      def read(kyc, field)
        field.storage == :column ? kyc.public_send(field.name) : (kyc.json_fields || {})[field.name]
      end

      # Sets the value on the KYC without saving. Dates are parsed first.
      # Raises Error::BadValue when a date can't be read.
      def write(kyc, field, value)
        value = parse_date(value) if field.date?
        if field.storage == :column
          kyc.public_send(:"#{field.name}=", value)
        else
          kyc.json_fields = (kyc.json_fields || {}).merge(field.name => value.is_a?(Date) ? value.iso8601 : value)
        end
        value
      end

      def parse_date(value)
        return value if value.is_a?(Date)

        Date.parse(value.to_s)
      rescue Date::Error, TypeError
        raise Error::BadValue, value.to_s
      end

      # Save fields Document Checks wrote, audited ("Document checks"). Runs inside the caller's
      # transaction; returns true when something was saved. Worked examples H3, H5 —
      # openspec/changes/document-checks/design.md#worked-examples
      def save_details!(kyc)
        return false unless kyc.changed?

        kyc.audit_comment = "Document checks" if kyc.respond_to?(:audit_comment=)
        kyc.save!(validate: false)
        true
      end

      # After the save has committed: reset "Review KYC" as a fund user's edit would
      def details_changed!(kyc, user:)
        kyc.journey_details_changed!(actor: user)
      end

      # Keep all_docs_valid in step with the assessment (written only when it changes). A derived flag:
      # the run and its results are the evidence, so skip callbacks (indexing, PAN/bank re-verification)
      # rather than re-saving the whole KYC.
      def on_assessed(kyc, settled)
        return if kyc.all_docs_valid == settled

        kyc.update_column(:all_docs_valid, settled)
      end

      # Re-assess after something outside a run changed (a document replaced or removed). No-op for KYCs
      # never checked; never raises into the caller's callback.
      def reassess(kyc)
        return unless ::DocCheckRun.exists?(record_type: "InvestorKyc", record_id: kyc.id, current: true)

        on_assessed(kyc, Assessment.new(kyc).settled?)
      rescue StandardError => e
        Rails.logger.error("DocChecks::Kyc.reassess failed for KYC #{kyc.id}: #{e.class} #{e.message}")
      end

      # Fund users of the KYC's own entity who may view / edit it. Investors (another entity) never.
      def can_view?(user, kyc)
        user.entity_id == kyc.entity_id && InvestorKycPolicy.new(user, kyc).show?
      end

      def can_edit?(user, kyc)
        user.entity_id == kyc.entity_id && InvestorKycPolicy.new(user, kyc).update?
      end

      def kyc_form_type_ids(entity)
        entity.form_types.where(name: FORM_TYPE_NAMES).pluck(:id)
      end
    end
  end
end
