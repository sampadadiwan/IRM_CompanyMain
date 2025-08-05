# app/packs/ai/fund_formula_variable_service.rb

# This service is responsible for loading, parsing, and providing access to the
# fund formula variable mapping defined in `config/fund_formula_variable_map.yml`.
# It acts as a single source of truth for this configuration, preventing duplication
# and ensuring consistent access across different parts of the application.
class FundFormulaVariableService
  # Path to the configuration file. Using a constant makes it easy to update if the location changes.
  CONFIG_PATH = Rails.root.join("config/fund_formula_variable_map.yml").freeze

  # Provides a cached, read-only instance of the parsed YAML configuration.
  # The `||=` operator ensures the file is loaded and parsed only once per class lifecycle.
  #
  # @return [Hash] The deeply symbolized configuration hash.
  # @raise [RuntimeError] If the configuration file is missing or malformed.
  def self.variable_map
    @variable_map ||= begin
      YAML.load_file(CONFIG_PATH).deep_symbolize_keys
    rescue Errno::ENOENT
      raise "Missing fund_formula_variable_map.yml configuration file."
    rescue Psych::SyntaxError
      raise "Malformed fund_formula_variable_map.yml configuration file."
    end
  end

  # Retrieves the consolidated list of variables for a specific rule type.
  # It handles merging variables from the rule itself, any inherited rules,
  # and common variables.
  #
  # @param rule_type [Symbol] The rule type for which to retrieve variables.
  # @return [Hash<Symbol, Array<String>>] A hash containing the consolidated lists
  #   of `:ctx`, `:instance`, and `:derived` variables.
  def self.variables_for(rule_type)
    rules = variable_map[:rules]
    common = variable_map[:common_variables] || {}
    vars = rules[rule_type] || {}
    inherited = rules[vars[:inherits].to_sym] if vars[:inherits]

    # Consolidate variables from all sources, ensuring uniqueness.
    ctx_vars = ((vars[:ctx] || []) + (inherited&.dig(:ctx) || []) + (common[:ctx] || [])).uniq
    instance_vars = ((vars[:instance_variables] || []) + (inherited&.dig(:instance_variables) || []) + (common[:instance_variables] || [])).uniq
    derived_vars = ((vars[:derived] || []) + (inherited&.dig(:derived) || [])).uniq

    {
      ctx: ctx_vars,
      instance: instance_vars,
      derived: derived_vars
    }
  end
end
