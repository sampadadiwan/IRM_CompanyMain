module AccountEntryAllocation
  module RunCheckSuggestions
    # One suggested pre/post-run check, as plain data so a suggestion set can be stored in
    # FundFormulaOperation#plan and read back unchanged:
    #
    #   "key"          stable id within a set, e.g. "rule:allowed_names:Non Deal Expense" or "ai:3"
    #   "source"       "rule" or "ai"
    #   "name", "description", "rule_type" (PreRunCheck | PostRunCheck)
    #   "helper", "args" a helper call split in two, so severity can be switched: helper(args[, severity: :warning])
    #   "formula"      the text for an AI suggestion that is not a single helper call
    #   "severity"     "fail" or "warning" (only when the helper takes severity:)
    #   "evidence"     [{"formula_id", "sequence", "name", "detail"}] or [{"detail"}] for facts about the data
    #   "already_present" formula id of an existing check with the same text, else nil
    #   "similar_to"   [{"formula_id", "sequence", "name"}] existing checks calling the same helper
    #   "errors"       FundFormula validation errors; a suggestion with errors cannot be added
    #   "result"       the test run: {"result", "summary", "columns", "rows", "truncated", "duration_ms"} or {"result" => "not_tested"}
    class Suggestion
      # Helpers that accept severity: (every CheckHelpers helper except check!)
      SEVERITY_HELPERS = CheckHelpers::HELPER_CATALOGUE.filter_map { |h| h[:signature][/\A(\w+)\(/, 1] }.to_set.freeze
      HELPER_CALL = /\A\s*(\w+)\((.*)\)\s*\z/m

      attr_reader :data

      # A single helper call, or a free-form formula (AI)
      def self.build(key:, source:, name:, description:, rule_type:, evidence: [], helper: nil, args: nil, formula: nil, severity: "fail")
        # The text an import would store (ImportUtil cleans every cell), so what is validated and test-run
        # here is exactly what "Add selected" writes and what the downloaded xlsx imports as
        args = ImportUtil.sanitize_cell(args)
        formula = ImportUtil.sanitize_cell(formula)
        if formula && (call = helper_call(formula))
          helper, args = call
          # A trailing severity: becomes the switchable severity; one anywhere else keeps the text as written
          if (sev = args.match(/,\s*severity:\s*:(fail|warning)\s*\z/))
            severity = sev[1]
            args = args[0...sev.begin(0)]
          end
          if args.include?("severity:")
            helper = args = nil
          else
            formula = nil
          end
        end
        new("key" => key, "source" => source, "name" => name, "description" => description, "rule_type" => rule_type,
            "helper" => helper, "args" => args, "formula" => formula, "severity" => severity, "evidence" => evidence)
      end

      # [helper, args] when text is exactly one call to a helper that takes severity:, else nil. HELPER_CALL
      # alone also matches "helper(a)\ncheck!(b)" or "helper(a) && other(b)": the args must not close the
      # call's own parenthesis part-way through (parentheses inside string literals do not count).
      def self.helper_call(text)
        m = text.to_s.match(HELPER_CALL)
        return nil unless m && SEVERITY_HELPERS.include?(m[1]) && balanced?(m[2])

        [m[1], m[2].strip]
      end

      def self.balanced?(args)
        depth = 0
        quote = nil
        escaped = false
        args.each_char do |c|
          if escaped
            escaped = false
          elsif quote
            escaped = c == "\\"
            quote = nil if c == quote
          elsif ['"', "'"].include?(c)
            quote = c
          elsif c == "("
            depth += 1
          elsif c == ")"
            depth -= 1
            return false if depth.negative?
          end
        end
        depth.zero? && quote.nil?
      end

      def initialize(data)
        @data = data.to_h.deep_stringify_keys
      end

      %w[key source name description rule_type helper args severity evidence already_present similar_to errors result].each do |k|
        define_method(k) { data[k] }
      end

      def supports_severity? = helper.present? && SEVERITY_HELPERS.include?(helper)
      def ai? = source == "ai"
      def addable? = already_present.nil? && errors.blank?

      # Helper arguments made only of literals: strings without interpolation, symbols, keywords, numbers,
      # true/false/nil, arrays, hashes and =>. Nothing in them can run code.
      LITERAL_TOKENS = /"(?:[^"\\#]|\\.)*"|'(?:[^'\\]|\\.)*'|:\w+|\w+:|=>|-?\d+(?:\.\d+)?|\b(?:true|false|nil)\b|[\[\]{},\s]/

      def self.literal_args?(args) = args.to_s.gsub(LITERAL_TOKENS, "").empty?

      # Whether the test run may evaluate this suggestion before anyone has chosen it. Rule suggestions are
      # built here from fixed templates. An AI suggestion is text a model wrote from a prompt that quotes
      # user-uploaded entry names, so it is evaluated only when it is a single helper call with literal
      # arguments; anything else waits until a person reads it and adds it.
      def safe_to_test? = !ai? || (helper.present? && self.class.literal_args?(args))

      # The formula text at a severity ("fail" leaves the helper's default)
      def formula(severity: self.severity)
        return data["formula"] if helper.blank?

        parts = [args.presence]
        parts << "severity: :warning" if supports_severity? && severity.to_s == "warning"
        call = parts.compact.join(", ")
        call.empty? ? helper : "#{helper}(#{call})"
      end

      def pre? = rule_type == FundFormula::PRE_RUN_CHECK

      # The FundFormula attributes this suggestion becomes, exactly as importing its xlsx row would store them
      def formula_attributes
        FundFormulaAttributes.as_imported(name:, description:, rule_type:, rule_for: "accounting", formula:, enabled: true).except(:sequence)
      end

      def []=(k, v)
        data[k.to_s] = v
      end

      def to_h = data
    end
  end
end
