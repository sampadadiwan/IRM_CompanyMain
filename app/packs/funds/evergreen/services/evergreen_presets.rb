# Reads config/evergreen_presets.yml. Presets only fill the settings form (never save).
# Worked example H2 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenPresets
  PATH = Rails.root.join("config/evergreen_presets.yml")

  def self.all
    @all ||= YAML.safe_load_file(PATH).deep_stringify_keys
  end

  # [[label, key], ...] for a select
  def self.options
    all.map { |key, preset| [preset["label"], key] }
  end

  # Field values for a preset, or nil for an unknown name
  def self.values(name)
    all.dig(name.to_s, "values")&.deep_dup
  end
end
