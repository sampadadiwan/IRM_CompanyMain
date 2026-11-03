# Dumps model reflection (no DB queries) as JSON for the schema explorer. Run via build.py.
# eager_load! covers gem models; the pack models need the explicit constantize loop below.
Rails.application.eager_load!

failed = []
Rails.root.glob("app/**/models/**/*.rb").each do |path|
  cpath = Rails.autoloaders.main.cpath_expected_at(path)
  cpath&.constantize
rescue StandardError, LoadError => e
  failed << "#{path}: #{e.class}"
end
warn "load failures: #{failed.size}"
failed.first(10).each { |line| warn line }

SKIP_PREFIXES = %w[HABTM_ ActiveRecord:: ActiveStorage:: ActionText:: ActionMailbox:: SolidQueue Doorkeeper PaperTrail].freeze

def association_info(reflection)
  info = { macro: reflection.macro, name: reflection.name, through: reflection.options[:through], as: reflection.options[:as] }
  if reflection.polymorphic?
    info[:poly] = true
  else
    info[:klass] = reflection.class_name
  end
  info[:fk] = reflection.foreign_key.to_s
  info.compact
rescue StandardError
  # A reflection whose target class cannot be resolved is left out rather than failing the dump.
  nil
end

out = {}
ActiveRecord::Base.descendants.each do |model|
  next if model.abstract_class? || model.name.nil?
  next if model.name.end_with?("Sqlite") || model.name.start_with?(*SKIP_PREFIXES)

  table = model.table_name
  next if table.blank?

  out[table] ||= []
  out[table] << {
    model: model.name,
    table: table,
    sti: model.base_class == model ? nil : model.base_class.name,
    custom_fields: model.include?(WithCustomField),
    money: model.respond_to?(:monetized_attributes) ? model.monetized_attributes.values.map(&:to_s) : [],
    enums: model.defined_enums.transform_values(&:keys),
    assocs: model.reflect_on_all_associations.filter_map { |r| association_info(r) }
  }
end

File.write(ARGV[0], JSON.pretty_generate(out))
puts "wrote #{out.size} tables"
