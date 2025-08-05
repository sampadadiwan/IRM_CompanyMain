# The FundFormulaExplainer class is responsible for generating a detailed, human-readable
# explanation for a given FundFormula object. It constructs a comprehensive prompt
# for a Large Language Model (LLM) by combining the formula's details with contextual
# information from a YAML configuration file.
class FundFormulaExplainer
  # The primary entry point for the class. It orchestrates the process of
  # building a prompt and calling the LLM service.
  #
  # @param fund_formula [FundFormula] The formula object to be explained.
  # @return [String] The AI-generated explanation.
  def self.explain(fund_formula)
    rule_type = fund_formula.rule_type.to_sym
    # Retrieve consolidated variables from the dedicated service.
    variables = FundFormulaVariableService.variables_for(rule_type)

    # Format the variable lists for clean inclusion in the prompt.
    ctx_var_lines = variables[:ctx].map { |v| "- #{v}" }.join("\n")
    instance_var_lines = variables[:instance].map { |v| "- #{v}" }.join("\n")
    derived_var_lines = variables[:derived].map { |v| "- #{v}" }.join("\n")

    # The heredoc below constructs the full prompt sent to the LLM.
    full_prompt = build_prompt(fund_formula, ctx_var_lines, instance_var_lines, derived_var_lines)

    Rails.logger.info "FundFormulaExplainer: Generated prompt for formula #{fund_formula.name} - rule_type '#{rule_type}':\n#{full_prompt}"

    # Call the LlmService to send the prompt to the configured AI provider
    # and retrieve the generated explanation.
    response = LlmService.chat(
      prompt: full_prompt,
      provider: "gemini", # Consider making this configurable
      llm_model: "gemini-2.5-flash-preview-05-20" # Consider making this configurable
    ).strip

    Rails.logger.info "FundFormulaExplainer: Received LLM response for formula #{fund_formula.name} - rule_type '#{rule_type}':\n#{response}"
    response
  end

  # private scope for helper methods
  class << self
    private

    # Constructs the detailed prompt for the LLM.
    # @param fund_formula [FundFormula] The formula being explained.
    # @param ctx_var_lines [String] Formatted list of context variables.
    # @param instance_var_lines [String] Formatted list of instance variables.
    # @param derived_var_lines [String] Formatted list of derived variables.
    # @return [String] The complete prompt.
    def build_prompt(fund_formula, ctx_var_lines, instance_var_lines, derived_var_lines)
      <<~PROMPT
        You are an expert fund accountant. Your task is to explain fund allocation formulas to clients.

        Each formula is written in Ruby and evaluated using pre-defined variables.

        ---
        Formula Name: #{fund_formula.name}

        Rule Type: #{fund_formula.rule_type}

        Context variables (available from the surrounding context `ctx` object):
        #{ctx_var_lines.presence || '- (none)'}

        Instance variables (available from the fund formula's associated object):
        #{instance_var_lines.presence || '- (none)'}

        Derived or loop variables (generated dynamically as part of evaluation):
        #{derived_var_lines.presence || '- (none)'}

        ---
        Formula:
        ```
        #{fund_formula.formula}
        ```

        #{"User-written description: #{fund_formula.description}" if fund_formula.description.present?}

        ---
        Please describe what this formula computes in plain language.

        - Explain the business meaning of the formula's operations and variables.
        - Assume the audience is non-technical.
        - Keep the explanation concise and focused on the financial purpose.
        - Explain the business purpose and key financial logic behind the formula.
        - Focus on what's being calculated and why it matters (e.g., allocations, percentages, currency conversion).
        - Organize into 1-3 short paragraphs if needed, with good flow.
        - Avoid technical or implementation-specific terms like `eval`, `scope`,`object`, or Ruby-specific syntax.
        - Do not output code, headings, markdown, bullet points, or formatting. Just a plain text explanation.
        - Favor clarity over brevity — don't oversimplify if it hides important logic.

        The final explanation should be understandable by both detail-oriented fund managers and less technical team members.
      PROMPT
    end
  end
end
