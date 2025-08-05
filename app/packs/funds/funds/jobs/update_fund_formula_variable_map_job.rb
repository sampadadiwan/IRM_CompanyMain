# app/packs/funds/funds/jobs/update_fund_formula_variable_map_job.rb
class UpdateFundFormulaVariableMapJob < ApplicationJob
  queue_as :default

  def perform
    reference_yaml = Rails.root.join("config/fund_formula_variable_map.yml").read
    run_formula = Rails.root.join("app/services/account_entry_allocation/run_formula.rb").read

    service_dir = Rails.root.join("app/services/account_entry_allocation")
    service_files = Dir[service_dir.join("*.rb")].reject { |f| f.include?("run_formula.rb") }
    services_code = service_files.map { |path| File.read(path) }.join("\n\n")

    extra_files = [
      Rails.root.join("app/services/account_entry_allocation/create_account_entry.rb"),
      Rails.root.join("app/services/account_entry_allocation/allocation_base_operation.rb")
    ].select(&:exist?).map { |path| File.read(path) }.join("\n\n")

    full_prompt = build_prompt(reference_yaml, run_formula, services_code, extra_files)

    Rails.logger.debug "Sending to LLM..."
    raw_response = LlmService.chat(prompt: full_prompt, provider: "gemini", llm_model: "gemini-2.5-flash-preview-05-20", format: :json).strip

    # Attempt to extract YAML from markdown code block, otherwise use the whole response
    response = if raw_response.match?(/```ya?ml\n(.+?)```/m)
                 raw_response.match(/```ya?ml\n(.+?)```/m)[1].strip
               else
                 raw_response
               end

    # Basic YAML validation
    begin
      YAML.safe_load(response)
    rescue Psych::SyntaxError => e
      raise "LLM returned invalid YAML: #{e.message}"
    end

    Rails.root.join("config/fund_formula_variable_map.yml").write(response)
    Rails.logger.debug "✅ fund_formula_variable_map.yml updated!"
  end

  private

  def build_prompt(reference_yaml, run_formula_code, services_code, extra_code)
    <<~PROMPT
      You are a Ruby code analysis assistant working on a financial allocation system.

      Below is a YAML reference file describing available variables for each formula `rule_type`.
      Use it as a starting point — you may reuse, correct, or enhance it.

      ---- Existing Reference YAML ----
      #{reference_yaml}
      ---- End Reference ----

      The main dispatch logic is defined in this file:
      ---- run_formula.rb ----
      #{run_formula_code}
      ---- End ----

      The methods for each rule_type are defined in the following files:
      ---- Services ----
      #{services_code}
      ---- End ----

      Additional helpers and variable binding code:
      ---- Extra ----
      #{extra_code}
      ---- End ----

      ✅ Your task: Based on this code, regenerate the YAML mapping of available variables per rule_type.

      Include:
      - Variables from `ctx`
      - Instance variables (e.g., `@fund`, `@setup_fees`, etc.)
      - Derived/loop variables (like `capital_commitment`, `ae`)
      - Use `inherits:` for rule_types that share a base rule
      - Group common variables under `common_variables` if applicable

      Return valid, complete YAML only — no extra explanation or markdown.
    PROMPT
  end
end
