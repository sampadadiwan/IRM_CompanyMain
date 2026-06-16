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

  def self.associations_for(klass)
    klass.reflect_on_all_associations.filter_map do |r|
      next if r.options[:polymorphic]

      target_klass = begin
        r.klass
      rescue StandardError
        next
      end

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
