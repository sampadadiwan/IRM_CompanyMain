class ReportBuilderModelDiscovery
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

  # Models eligible as report roots: must define STANDARD_COLUMNS and have entity_id.
  def self.roots
    eager_load!
    app_models
      .select { |k| k.const_defined?(:STANDARD_COLUMNS) }
      .select { |k| k.column_names.include?("entity_id") }
      .sort_by(&:name)
  end

  def self.all_models
    eager_load!
    app_models.sort_by(&:name)
  end

  def self.associations_for(klass)
    klass.reflect_on_all_associations.filter_map do |r|
      next if r.options[:polymorphic]
      next unless r.klass rescue next

      {
        name:        r.name.to_s,
        model:       r.klass.name,
        macro:       r.macro.to_s,
        foreign_key: foreign_key_for(klass, r),
        label:       r.name.to_s.humanize
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

  def self.foreign_key_for(root_class, reflection)
    case reflection.macro
    when :has_many, :has_one then reflection.foreign_key.to_s
    when :belongs_to         then reflection.foreign_key.to_s
    end
  end
  private_class_method :foreign_key_for

  def self.app_models
    ActiveRecord::Base.descendants
      .select { |k| k.ancestors.include?(ApplicationRecord) }
      .reject(&:abstract_class?)
      .reject { |k| k.name.nil? }
      .select { |k| k.table_exists? rescue false }
      .reject { |k| EXCLUDED_TABLES.include?(k.table_name) }
  end
  private_class_method :app_models

  def self.eager_load!
    # In Zeitwerk (Rails 7+), we should use the autoloader or eager_load
    if Rails.respond_to?(:autoloaders) && Rails.autoloaders.main
      # This is a bit heavy but ensures everything is loaded for discovery
      Rails.application.eager_load!
    else
      Dir.glob(Rails.root.join("app/packs/**/*.rb")).each { |f| require_dependency f rescue nil }
    end
  end
  private_class_method :eager_load!
end
