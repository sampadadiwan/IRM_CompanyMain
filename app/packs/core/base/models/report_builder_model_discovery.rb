class ReportBuilderModelDiscovery
  # Add or remove class names here to control what appears in the "New Report" dropdown.
  ROOT_MODELS = %w[
    Fund
    Investor
    InvestorKyc
    CapitalCommitment
    CapitalCall
    CapitalRemittance
    CapitalRemittancePayment
    CapitalDistributionPayment
    CapitalDistribution
    PortfolioInvestment
    AggregatePortfolioInvestment
    AccountEntry
    FundUnit
    CommitmentAdjustment
    ExchangeRate
    KpiReport
    Kpi
    Document
  ].freeze

  EXCLUDED_TABLES = %w[
    versions audits solid_cache_entries
    active_storage_attachments active_storage_blobs active_storage_variant_records
    action_mailbox_inbound_emails action_text_rich_texts
    friendly_id_slugs noticed_events noticed_notifications
    oauth_access_grants oauth_access_tokens oauth_applications oauth_openid_requests
    devise_api_tokens blazer_audits blazer_checks blazer_dashboard_queries
    blazer_dashboards blazer_queries taggings tags
    exception_tracks sync_records
  ].freeze

  # Models eligible as report roots — edit ROOT_MODELS above to control this list.
  def self.roots
    @roots ||= ROOT_MODELS.filter_map do |name|
      klass = name.safe_constantize
      next unless klass

      begin
        next unless klass.column_names.include?("entity_id")
      rescue StandardError
        nil
      end
      klass
    end.sort_by(&:name)
  end

  def self.all_models
    @all_models ||= begin
      eager_load!
      app_models.sort_by(&:name)
    end
  end

  # Reset cached results — called by Rails reloader in development.
  def self.reset_cache!
    @roots      = nil
    @all_models = nil
  end

  # Associations that are noise for report building, hidden from the "+ Add
  # related data" pickers (both the advanced builder and the guided wizard,
  # plus the /report_builder/associations drill-down endpoint — all three
  # go through this method). Internal plumbing (Entity/EntitySetting,
  # FormType/FormCustomFields), audit trails, incoming-email records, and
  # exchange-rate lookups aren't things a business user is reporting on;
  # the whole Workflow subsystem is excluded by target-model prefix since
  # it spans many association names. Edit here to change what's offered.
  EXCLUDED_ASSOCIATION_NAMES = %w[
    form_type form_types form_custom_fields
    entity entity_setting entity_settings
    audits associated_audits own_and_associated_audits
    incoming_emails incoming_email
    exchange_rate exchange_rates
    investor_signatory trustee_signatory
    folder folders document_folder document_folders data_room_folder
    noticed_events custom_notifications
    access_rights fund_formulas ratio_formulas portfolio_scenarios
    approvals approval_responses
  ].freeze

  # Hand-picked "+ Add related data" options per root model — the join-picker
  # equivalent of ADDITIONAL_COLUMNS_FROM (which already curates which
  # associations' *columns* are joinable). Auto-discovering every AR
  # association (the previous behaviour, still used as the fallback below for
  # any root model not listed here) surfaces 30-40+ options per model, most
  # of them irrelevant to reporting — this keeps only the handful that are
  # actually central to that model's story. Add an entry here for a root
  # model as it comes up in practice; there's no requirement to curate all of
  # ReportBuilderModelDiscovery::ROOT_MODELS up front.
  CURATED_JOINS = {
    "Investor" => %w[capital_commitments investor_kycs capital_distribution_payments capital_remittances fund_units],
    "Fund" => %w[capital_commitments capital_calls capital_distribution_payments capital_remittances fund_units portfolio_investments],
    "CapitalCommitment" => %w[investor fund capital_remittances capital_distribution_payments capital_remittance_payments fund_units],
    "CapitalCall" => %w[fund capital_remittances],
    "CapitalDistributionPayment" => %w[fund investor capital_commitment capital_distribution]
  }.freeze

  # Packs that are gated behind an entity-level feature flag (Entity#permissions,
  # see EntityEnabled) rather than always being available. A tenant that
  # doesn't have Deals turned on shouldn't be offered "+ Add related data"
  # options that only make sense for Deals (Offer, SecondarySale, ...) when
  # reporting on a Funds-pack root, and vice versa — the packs a model lives
  # under (see .pack_for) line up with these three flags closely enough to
  # use directly. Packs not listed here (Core, Misc, AI, Other) are treated
  # as always-available shared/foundational data.
  PACK_PERMISSION_FLAGS = {
    "Funds" => :enable_funds,
    "Startups" => :enable_deals,
    "Secondaries" => :enable_secondary_sale
  }.freeze

  # entity: when given, associations belonging to a pack the entity hasn't
  # enabled are hidden (see PACK_PERMISSION_FLAGS above). Left nil, no
  # entity-based filtering happens — every caller that has a current entity
  # in scope should pass one.
  def self.associations_for(klass, entity: nil)
    curated_names = CURATED_JOINS[klass.name]
    reflections = if curated_names
                    curated_names.filter_map { |name| klass.reflect_on_association(name.to_sym) }
                  else
                    klass.reflect_on_all_associations
                  end

    reflections.filter_map do |r|
      next if r.options[:polymorphic]

      target_klass = begin
        r.klass
      rescue StandardError
        next
      end

      next if excluded_association?(r.name.to_s, target_klass.name)
      next if entity && !pack_enabled_for?(target_klass, entity)

      {
        name: r.name.to_s,
        model: target_klass.name,
        macro: r.macro.to_s,
        foreign_key: foreign_key_for(klass, r),
        label: r.name.to_s.humanize,
        has_children: target_klass.reflect_on_all_associations.any? { |child| !child.options[:polymorphic] }
      }
    rescue NameError
      nil
    end
  end

  def self.excluded_association?(name, target_model_name)
    EXCLUDED_ASSOCIATION_NAMES.include?(name) ||
      name.start_with?("workflow") ||
      target_model_name.to_s.start_with?("Workflow")
  end
  private_class_method :excluded_association?

  def self.pack_enabled_for?(target_klass, entity)
    flag = PACK_PERMISSION_FLAGS[pack_for(target_klass)]
    return true unless flag
    return true unless entity.respond_to?(:permissions)

    entity.permissions.public_send("#{flag}?")
  rescue StandardError
    true
  end
  private_class_method :pack_enabled_for?

  def self.pack_for(klass)
    path = Object.const_source_location(klass.name)&.first.to_s
    if    path.include?("/funds/")        then "Funds"
    elsif path.include?("/core/")         then "Core"
    elsif path.include?("/startups/")     then "Startups"
    elsif path.include?("/secondaries/")  then "Secondaries"
    elsif path.include?("/misc/")         then "Misc"
    elsif path.include?("/ai/")           then "AI"
    else  "Other"
    end
  end

  def self.foreign_key_for(_root_class, reflection)
    case reflection.macro
    when :has_many, :has_one, :belongs_to then reflection.foreign_key.to_s
    end
  end
  private_class_method :foreign_key_for

  def self.app_models
    ActiveRecord::Base.descendants
                      .select { |k| k.ancestors.include?(ApplicationRecord) }
                      .reject(&:abstract_class?)
                      .reject { |k| k.name.nil? }
                      .select do |k|
      k.table_exists?
    rescue StandardError
      false
    end
                      .reject { |k| EXCLUDED_TABLES.include?(k.table_name) }
  end
  private_class_method :app_models

  def self.eager_load!
    if Rails.respond_to?(:autoloaders)
      # Eager load each Zeitwerk loader directly, bypassing the @eager_loaded cache
      # that can cause stale results when roots is first called before all packs are warm.
      Rails.autoloaders.each do |loader|
        begin
          loader.eager_load(force: true)
        rescue StandardError
          loader.eager_load
        end
      rescue StandardError
        nil
      end
    else
      Rails.application.eager_load!
    end
  end
  private_class_method :eager_load!
end
