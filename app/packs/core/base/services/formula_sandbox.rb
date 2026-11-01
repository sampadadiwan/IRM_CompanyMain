require "prism"
require "yaml"

# Allowlist check for every stored formula the app evaluates (fund formulas, run checks, call-fee
# formulas, Calculation custom fields, the entity expense filter). C2 —
# docs/security/security_review_2026_10.md#c2--formula-engine-allowlist-checked-evaluation
#
# A formula is parsed with Prism (parse only, nothing runs) using the local-variable names of the
# binding it will be evaluated in, so the tree that is checked is the tree that runs. Every node,
# method, constant and query root in it must be on the allowlist of the formula's *profile*
# (config/formula_sandbox.yml). Only then is it evaluated, with the same binding as before, so a
# formula that passes gives exactly the result it gave before.
#
# Mode (ENV FORMULA_SANDBOX):
#   off     — today's behaviour exactly: no check, only ApplicationRecord.safe_eval! (the default)
#   log     — check, log "[formula_sandbox] would_reject …" for a formula that fails, still evaluate
#   enforce — refuse a formula that fails with FormulaSandbox::Rejected
# safe_eval! keeps running in every mode until rollout step 4 removes it.
#
# Standalone on purpose (requires only prism, set, yaml): the offline corpus check runs this file
# with plain Ruby, without booting Rails.
module FormulaSandbox
  # A refused formula. A kind of ApplicationRecord::UnsafeEvalError when Rails is loaded, so callers
  # that already treat a safe_eval! refusal as a security refusal (CallFee#calculate_formula) treat
  # this one the same way.
  base_error = defined?(ApplicationRecord::UnsafeEvalError) ? ApplicationRecord::UnsafeEvalError : StandardError
  class Rejected < base_error
    attr_reader :violations

    def initialize(message = nil, violations: [])
      @violations = violations
      super(message)
    end
  end

  # The numeric fold (KPI formulas, N1) refuses text with this
  class NotNumeric < StandardError; end

  MODES = %w[off log enforce].freeze
  # Parse + check results are cached per (profile, text, locals); this caps the cache so a long-lived
  # worker cannot grow it without bound (a cached entry is a short array of strings)
  CACHE_LIMIT = 5_000
  CACHE_LOCK = Mutex.new

  # Operators the numeric fold applies (N1). ** is deliberately absent: a huge exponent ties up a worker.
  FOLD_BINARY = %i[+ - * /].freeze
  FOLD_UNARY = %i[-@ +@].freeze

  module_function

  ##############################################################################
  # Public API
  ##############################################################################

  # Evaluates `text` in `bdg` (the binding it has always been evaluated in), after the check the mode
  # asks for. ApplicationRecord.safe_eval! still guards the text first, in every mode.
  #
  # @param text [String] the stored formula
  # @param bdg [Binding] the evaluation binding; its local names drive the parse (C2-X1)
  # @param profile [String, Symbol] the allowlist profile in config/formula_sandbox.yml
  # @param context [String] names the formula in log lines, e.g. "FundFormula#12"
  # @param file [String], line [Integer] passed to eval for backtraces, as the call sites did before.
  #   Without a file, the label is Ruby's own "(eval at CALLER:LINE)" for the calling line, so syntax
  #   errors and backtraces read as they did when the call site called eval itself.
  def evaluate(text, bdg, profile:, context: nil, file: nil, line: 1)
    source = text.to_s
    file ||= caller_locations(1, 1).first.then { |location| "(eval at #{location.path}:#{location.lineno})" }
    # Today's denylist guard runs in every mode (C2 rollout: removed only after enforce)
    source = ApplicationRecord.safe_eval!(source, context:) if defined?(ApplicationRecord)

    # log / enforce: check the tree against the profile, parsed with the binding's own locals
    check!(source, profile:, locals: bdg.local_variables, context:) unless mode == "off"

    bdg.eval(source, file, line)
  end

  # The validation used on save in log / enforce modes (it replaces each *_kosher? at rollout step 4).
  # Raises Rejected when the text fails; returns true otherwise. A text that does not parse passes
  # here: the existing syntax checks report it with their own message (C2-X12).
  def validate!(text, profile:, locals: [])
    errors = violations(text, profile:, locals:)
    raise Rejected.new(rejection_message(errors), violations: errors) if errors.any?

    true
  end

  # The list of reasons `text` fails `profile` (empty when it passes). Parse only, never evaluates.
  # Cached per (profile, text, sorted locals): the same formula text evaluated with different locals is
  # a different tree, so locals are part of the key (C2-X1).
  def violations(text, profile:, locals: [])
    local_names = locals.map(&:to_sym).uniq.sort
    key = [profile.to_s, text.to_s, local_names].freeze
    # Hit: return the stored result
    cached = CACHE_LOCK.synchronize { cache[key] }
    return cached if cached

    # Miss: walk the tree, then store the (frozen) result; the cache is emptied when it is full
    result = Walker.new(text.to_s, profile_config(profile), local_names).violations.freeze
    CACHE_LOCK.synchronize do
      cache.clear if cache.size >= CACHE_LIMIT
      cache[key] = result
    end
    result
  end

  # Applies the mode to a check: nothing in off, a log line in log, a refusal in enforce.
  # Returns true when the text passed (or mode is off).
  def check!(text, profile:, locals: [], context: nil)
    return true if mode == "off"

    errors = safe_violations(text, profile:, locals:)
    return true if errors.empty?

    # Both modes log, so the weekly audit and the logs agree on what would be refused. An allocation run
    # evaluates one formula once per commitment, so each (profile, text, context) is logged once per process.
    label = context ? " context=#{context}" : ""
    first_time = first_report?([profile.to_s, text.to_s, context.to_s])
    if mode == "enforce"
      log(:error, "[formula_sandbox] rejected profile=#{profile}#{label} reasons=#{errors.join(' | ')} text=#{truncate(text)}") if first_time
      raise Rejected.new(rejection_message(errors, context:), violations: errors)
    end

    # C2-8 — log mode: record the rejection and let the formula run unchanged
    log(:warn, "[formula_sandbox] would_reject profile=#{profile}#{label} reasons=#{errors.join(' | ')} text=#{truncate(text)}") if first_time
    true
  end

  # violations, except that a failure of the check itself never changes a log-mode run: it is reported
  # as a violation (so enforce mode fails closed) and never cached
  def safe_violations(text, profile:, locals:)
    violations(text, profile:, locals:)
  rescue StandardError => e
    ["sandbox check failed: #{e.class}: #{e.message}"]
  end

  # True the first time a key is reported in this process (bounded like the cache)
  def first_report?(key)
    CACHE_LOCK.synchronize do
      @reported ||= Set.new
      @reported.clear if @reported.size >= CACHE_LIMIT
      @reported.add?(key) || false
    end
  end

  # Model validation helper: adds an error in enforce mode, logs a warning in log mode, does nothing
  # in off mode (so off leaves saves exactly as they were).
  def validate_attribute(record, attribute, profile:, locals: [])
    return if mode == "off"

    text = record.public_send(attribute)
    return if text.nil? || text.to_s.strip.empty?

    errors = safe_violations(text, profile:, locals:)
    return if errors.empty?

    label = "#{record.class.name}##{record.id || 'new'} #{attribute}"
    if mode == "enforce"
      record.errors.add(attribute, "uses something formulas may not use: #{errors.first(3).join('; ')}")
    else
      log(:warn, "[formula_sandbox] would_reject profile=#{profile} context=#{label} reasons=#{errors.join(' | ')} text=#{truncate(text)}")
    end
  end

  # The current mode. An unknown value is treated as "log": it checks and reports but never breaks a
  # run, and the mistake shows up in the logs.
  def mode
    value = ENV.fetch("FORMULA_SANDBOX", "off").to_s.strip.downcase
    MODES.include?(value) ? value : "log"
  end

  ##############################################################################
  # N1 — numeric fold for KPI computed formulas (no eval)
  ##############################################################################

  # Evaluates a formula that is only numbers, + - * /, unary minus/plus and parentheses, by folding
  # its parse tree with Ruby's own operators: integer division stays integer division, 1/0 still
  # raises ZeroDivisionError, 1.0/0 is still Infinity. Anything else (a name, **, a method call) raises
  # NotNumeric. Multiple statements give the last one's value, as eval did.
  def numeric_fold(text)
    result = Prism.parse(text.to_s)
    raise NotNumeric, "not valid syntax: #{result.errors.first.message}" if result.errors.any?

    statements = result.value.statements&.body || []
    raise NotNumeric, "empty formula" if statements.empty?

    # Every statement is folded (an invalid one fails the formula); the last is the value
    statements.map { |node| fold_node(node) }.last
  end

  # Folds one node of a numeric formula
  def fold_node(node)
    case node
    when Prism::IntegerNode, Prism::FloatNode
      # Prism folds a leading minus into the literal (-1, -1.5)
      node.value
    when Prism::ParenthesesNode
      # (a + b) — the body is a StatementsNode; "()" is nil in Ruby, which no formula wants
      body = node.body
      raise NotNumeric, "empty parentheses" if body.nil?

      body.is_a?(Prism::StatementsNode) ? body.body.map { |inner| fold_node(inner) }.last : fold_node(body)
    when Prism::CallNode
      fold_call(node)
    else
      raise NotNumeric, "#{node.type.to_s.delete_suffix('_node')} is not allowed in a computed KPI formula"
    end
  end

  # a + b, a - b, a * b, a / b, -a, +a — nothing else
  def fold_call(node)
    args = node.arguments&.arguments || []
    raise NotNumeric, "#{node.name} is not allowed in a computed KPI formula" if node.receiver.nil? || node.block

    receiver = fold_node(node.receiver)
    if FOLD_UNARY.include?(node.name) && args.empty?
      node.name == :-@ ? -receiver : receiver
    elsif FOLD_BINARY.include?(node.name) && args.size == 1
      operand = fold_node(args.first)
      # The four operators, applied exactly as Ruby applies them (Integer#/ floors, Float#/ does not)
      case node.name
      when :+ then receiver + operand
      when :- then receiver - operand
      when :* then receiver * operand
      when :/ then receiver / operand
      end
    else
      raise NotNumeric, "#{node.name} is not allowed in a computed KPI formula"
    end
  end

  ##############################################################################
  # The audit's mechanical rewrite (rake formula_sandbox:audit EXECUTE=1)
  ##############################################################################

  # Pins a query root that is filtered through the engine's own commitment to the fund itself:
  #   PortfolioInvestment.where(fund_id: capital_commitment.fund_id)  -> where(fund_id: @fund.id)
  #   ExchangeRate.where(entity_id: capital_commitment.entity_id)     -> where(entity_id: @fund.entity_id)
  #   CapitalDistributionPayment.where(capital_commitment_id: capital_commitment.id, …)
  #                                       -> where(fund_id: @fund.id, capital_commitment_id: capital_commitment.id, …)
  # Result-preserving in a fund formula: capital_commitment is always one of @fund's own commitments
  # (the engine sets it and no formula may reassign it), so each rewrite only restates a filter that
  # already held. Returns the text unchanged when nothing applies. Parse only, never evaluates.
  def rewrite_pins(text, profile: "fund_formula")
    source = text.to_s
    result = Prism.parse(source)
    return source if result.errors.any?

    pinned_roots = profile_config(profile)[:pinned_roots]
    edits = []
    # Collect one edit per offending key; offsets are byte offsets into the source
    stack = [result.value]
    until stack.empty?
      node = stack.pop
      stack.concat(node.compact_child_nodes)
      next unless node.is_a?(Prism::CallNode) && node.name == :where
      next unless node.receiver.is_a?(Prism::ConstantReadNode) && (pins = pinned_roots[node.receiver.name.to_s])

      hash = node.arguments&.arguments&.first
      next unless hash.is_a?(Prism::KeywordHashNode) || hash.is_a?(Prism::HashNode)

      edits.concat(pin_edits(hash, pins.fetch("keys")))
    end
    return source if edits.empty?

    # Apply from the end so earlier offsets stay valid
    bytes = source.b
    edits.sort_by { |offset, _length, _text| -offset }.each { |offset, length, replacement| bytes[offset, length] = replacement }
    bytes.force_encoding(source.encoding)
  end

  # The [offset, length, replacement] edits that pin one where(...) hash
  def pin_edits(hash, keys)
    pairs = hash.elements.grep(Prism::AssocNode).select { |assoc| assoc.key.is_a?(Prism::SymbolNode) }
    # Plain Ruby (no ActiveSupport index_by): this file runs without Rails for the offline check
    by_key = pairs.to_h { |assoc| [assoc.key.unescaped, assoc] } # rubocop:disable Rails/IndexBy
    edits = []
    pinned = false
    # fund_id: capital_commitment.fund_id / entity_id: capital_commitment.entity_id -> the fund's own
    { "fund_id" => "@fund.id", "entity_id" => "@fund.entity_id" }.each do |key, pin|
      next unless keys.key?(key) && (assoc = by_key[key])

      if assoc.value.slice.delete(" ") == "capital_commitment.#{key}"
        edits << [assoc.value.location.start_offset, assoc.value.location.length, pin]
        pinned = true
      elsif keys[key].include?(assoc.value.slice.delete(" "))
        pinned = true
      end
    end
    # capital_commitment_id: capital_commitment.id with no fund pin -> add fund_id: @fund.id in front
    commitment = by_key["capital_commitment_id"]
    edits << [hash.elements.first.location.start_offset, 0, "fund_id: @fund.id, "] if !pinned && keys.key?("fund_id") && commitment && commitment.value.slice.delete(" ") == "capital_commitment.id"
    edits
  end

  ##############################################################################
  # Profiles
  ##############################################################################

  # FundFormula rule types: which profile checks a formula, with which binding locals, and whether its
  # text is evaluated at all (Cumulate names, the literal field map, statements, percentages are not)
  def fund_formula_profile(rule_type)
    case rule_type.to_s
    when *fund_formula_locals_config.fetch("run_checks") then "run_check"
    when "GenerateCustomField" then "custom_field"
    else "fund_formula"
    end
  end

  def fund_formula_evaluated?(rule_type)
    fund_formula_locals_config.fetch("not_evaluated").none?(rule_type.to_s)
  end

  # The locals the rule type's operation binding carries (none for run checks: CheckContext has none)
  def fund_formula_locals(rule_type)
    return [] if fund_formula_profile(rule_type) == "run_check"

    locals = fund_formula_locals_config
    (Array(locals["shared"]) + Array(locals.fetch("by_rule_type")[rule_type.to_s])).map(&:to_sym)
  end

  def fund_formula_locals_config
    config.fetch("fund_formula_locals")
  end

  # The merged allowlist for a profile: the shared lists plus the profile's own additions
  def profile_config(name)
    @profile_configs ||= {}
    @profile_configs[name.to_s] ||= build_profile(name.to_s)
  end

  def build_profile(name)
    raw = config
    profile = raw.fetch("profiles").fetch(name) { raise ArgumentError, "unknown formula sandbox profile #{name.inspect}" }
    shared = raw.fetch("shared")
    sym_set = ->(list) { Array(list).to_set { |entry| entry.to_s.to_sym } }

    {
      name:,
      nodes: Array(shared["nodes"]).concat(Array(profile["nodes"])).to_set,
      hard_deny: sym_set.call(shared["hard_deny"]) - sym_set.call(profile["undeny"]),
      methods: sym_set.call(shared["operators"]) | sym_set.call(shared["methods"]) | sym_set.call(profile["methods"]),
      self_methods: sym_set.call(profile["self_methods"]),
      const_calls: merge_const_calls(shared["const_calls"], profile["const_calls"]),
      pinned_roots: (shared["pinned_roots"] || {}).merge(profile["pinned_roots"] || {}),
      pinned_only_methods: sym_set.call(shared["pinned_only_methods"]),
      raisable: Array(shared["raisable"]).to_set,
      type_constants: Array(shared["type_constants"]).to_set,
      reserved_writes: sym_set.call(shared["reserved_writes"]) | sym_set.call(profile["reserved_writes"]),
      sql_first_arg: sym_set.call(shared["sql_first_arg"]),
      sql_all_args: sym_set.call(shared["sql_all_args"]),
      sql_keywords: Regexp.new("\\b(#{Array(shared['sql_keywords']).join('|')})\\b", Regexp::IGNORECASE),
      sql_functions: Regexp.new("\\b(#{Array(shared['sql_functions']).join('|')})\\s*\\(", Regexp::IGNORECASE),
      join_sql: Regexp.new("\\A\\s*(INNER\\s+|LEFT\\s+(OUTER\\s+)?)?JOIN\\s+(#{Array(shared['joinable_tables']).join('|')})\\s+ON\\s+" \
                           "[a-z_]+\\.[a-z_]+\\s*=\\s*[a-z_]+\\.[a-z_]+\\s*\\z", Regexp::IGNORECASE),
      scoped_roots: sym_set.call(shared["scoped_roots"]),
      index_write_receivers: Array(profile["index_write_receivers"]).map { |pattern| Regexp.new(pattern) }
    }.freeze
  end

  def merge_const_calls(shared, own)
    merged = Hash.new { |hash, key| hash[key] = Set.new }
    [shared, own].compact.each do |calls|
      calls.each { |constant, names| merged[constant.to_s].merge(Array(names).map(&:to_sym)) }
    end
    merged.default_proc = nil
    merged.freeze
  end

  def config
    # aliases: the per-rule-type locals share lists through YAML anchors
    @config ||= YAML.safe_load_file(config_path, aliases: true)
  end

  def config_path
    return Rails.root.join("config/formula_sandbox.yml").to_s if defined?(Rails) && Rails.respond_to?(:root) && Rails.root

    File.expand_path("../../../../../config/formula_sandbox.yml", __dir__)
  end

  # Drops loaded profiles and cached results (tests that change the YAML or the profiles)
  def reset!
    CACHE_LOCK.synchronize do
      cache.clear
      @reported = nil
    end
    @profile_configs = nil
    @config = nil
  end

  def cache
    @cache ||= {}
  end

  def rejection_message(errors, context: nil)
    label = context ? " (#{context})" : ""
    "Refusing to evaluate a formula#{label}: #{errors.first(5).join('; ')}"
  end

  def truncate(text, length = 300)
    str = text.to_s.gsub(/\s+/, " ")
    str.length > length ? "#{str[0, length]}…" : str
  end

  def log(level, message)
    if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      Rails.logger.public_send(level, message)
    else
      warn message
    end
  end

  ##############################################################################
  # The walker: parse with the binding's locals, then visit every node
  ##############################################################################
  class Walker
    # A safe SQL fragment is only identifiers (optionally table.column), numbers, ? placeholders,
    # comparison/arithmetic operators and parentheses — no quotes, comments, semicolons or keywords
    # that read or write other tables.
    SQL_TOKEN = %r{\s*(?:[a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)?(?!\s*\()|\d+(?:\.\d+)?|\?|<=|>=|<>|!=|[<>=+\-*/(),])}i
    SQL_PUNCTUATION = %r{[;'"`#\\]|--|/\*}
    # A JSON path read on a json_fields column: investors.json_fields->>'$.master_fund'. Only word
    # characters inside the quotes, so the quote cannot be used to end the string early.
    SQL_JSON_PATH = /\b[a-z_]+(?:\.[a-z_]+)?\s*->>?\s*'\$\.[a-z0-9_]+'/i
    # A name CustomFieldsProxy answers from json_fields: a plain lower-case reader
    CUSTOM_FIELD_NAME = /\A[a-z_][a-z0-9_]*\??\z/

    def initialize(text, profile, locals)
      @text = text
      @profile = profile
      @locals = locals
      @errors = []
    end

    def violations
      # Parse with the binding's local names, so `fund` is a local read exactly when it is one at
      # eval time (C2-6: a formula that looks safe without its locals is checked as it will run)
      result = Prism.parse(@text, scopes: [@locals])
      # C2-X12 — a syntax error is not a sandbox violation: eval reports it with its usual message
      return [] if result.errors.any?

      visit(result.value, nil)
      @errors.uniq
    end

    private

    # Depth-first walk; each node is checked, then its children (except a constant path's parts)
    def visit(node, parent)
      type = node.class.name.split("::").last
      @errors << "node #{type}" unless @profile[:nodes].include?(type)

      descend = true
      case node
      when Prism::CallNode then check_call(node)
      when Prism::ConstantReadNode
        check_constant(node, parent)
      when Prism::ConstantPathNode
        # Foo::Bar is one name and its parts are not separate references; a dynamic path (expr::Foo)
        # is refused, and its expression is still walked
        if static_constant_path?(node)
          check_constant(node, parent)
          descend = false
        else
          @errors << "dynamic constant path #{node.slice[0, 40]}"
        end
      when Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode, Prism::LocalVariableOperatorWriteNode,
           Prism::LocalVariableAndWriteNode, Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode,
           Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableAndWriteNode,
           Prism::LocalVariableTargetNode, Prism::InstanceVariableTargetNode,
           Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::BlockLocalVariableNode
        # @fund / @start_date / @end_date / fund / capital_commitment are the engine's, never the formula's:
        # not as an assignment, a multiple-assignment target, nor a block parameter that would shadow them
        @errors << "write to reserved #{node.name}" if @profile[:reserved_writes].include?(node.name)
      when Prism::IndexOrWriteNode, Prism::IndexOperatorWriteNode, Prism::IndexAndWriteNode
        check_index_write(node.receiver)
      end

      node.compact_child_nodes.each { |child| visit(child, node) } if descend
    end

    # Foo::Bar::Baz with every part a constant name
    def static_constant_path?(node)
      node.full_name
      true
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError, Prism::ConstantPathNode::MissingNodesInConstantPathError
      false
    end

    def check_call(node)
      name = node.name

      # Reflection, eval, process, persistence, … are refused on any receiver (C2-1…C2-5)
      if @profile[:hard_deny].include?(name)
        @errors << "denied method #{name}"
      elsif node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)
        check_self_call(node)
      elsif constant?(node.receiver)
        check_constant_call(node)
      elsif custom_field_read?(node)
        # capital_commitment.custom_fields.code_b — a json_fields lookup, not a method
      elsif @profile[:pinned_only_methods].include?(name)
        # joins / left_joins only on a query already pinned to the fund
        @errors << "#{name} is only allowed on a pinned query root" unless pinned_chain?(node.receiver)
      elsif !@profile[:methods].member?(name)
        @errors << "method #{name}"
      end

      check_index_write(node.receiver) if name == :[]=
      check_sql_arguments(node)
      check_join_arguments(node)
      check_block_pass(node)
      check_inject_symbol(node)
      check_type_argument(node)
    end

    # A call with no receiver (or self.x) runs on the binding's own object. With the binding's locals
    # in the parse, a bare name here is never a local, so it must be one of the profile's self methods.
    def check_self_call(node)
      name = node.name
      unless @profile[:self_methods].include?(name)
        @errors << (node.variable_call? ? "unknown name #{name}" : "self method #{name}")
        return
      end
      return unless name == :raise

      # raise is allowed only for the engine's own control-flow errors (SkipRule, CheckFailed, CheckWarning)
      @errors << "raise of non-allowlisted error" unless raisable_argument?(node.arguments&.arguments&.first)
    end

    def raisable_argument?(arg)
      return true if arg.nil? # bare `raise` re-raises the current error

      if constant?(arg)
        @profile[:raisable].include?(constant_name(arg))
      elsif arg.is_a?(Prism::CallNode) && arg.name == :new && constant?(arg.receiver)
        @profile[:raisable].include?(constant_name(arg.receiver))
      else
        false
      end
    end

    # Calls on a constant: an allowed (constant, method) pair, or a pinned query root
    def check_constant_call(node)
      constant = constant_name(node.receiver)
      return if @profile[:const_calls][constant]&.include?(node.name)

      pins = @profile[:pinned_roots][constant]
      if pins
        # K.where(fund_id: @fund.id, …) — a query root must name the formula's own fund (or firm)
        return if node.name == :where && pinned_where?(node, pins)
        # AccountEntry.total_amount(relation, …) summarises a relation it is handed; it reads no rows itself
        return if Array(pins["unpinned_methods"]).map(&:to_sym).include?(node.name)

        @errors << "constant call #{constant}.#{node.name} (not pinned to #{pins.fetch('keys').keys.join(' / ')})"
      else
        @errors << "constant call #{constant}.#{node.name}"
      end
    end

    # where(fund_id: @fund.id) / where(entity_id: @fund.entity_id) with one of the profile's pin values
    def pinned_where?(call, pins)
      first = call.arguments&.arguments&.first
      return false unless first.is_a?(Prism::KeywordHashNode) || first.is_a?(Prism::HashNode)

      first.elements.any? do |assoc|
        next false unless assoc.is_a?(Prism::AssocNode) && assoc.key.is_a?(Prism::SymbolNode)

        allowed = pins.fetch("keys")[assoc.key.unescaped]
        allowed && pin_value?(assoc.value, allowed)
      end
    end

    # A pin value is one of the allowed expressions (@fund.id, fund.id, …) or an array made only of them
    def pin_value?(value, allowed)
      if value.is_a?(Prism::ArrayNode)
        value.elements.any? && value.elements.all? { |element| allowed.include?(element.slice.delete(" ")) }
      else
        allowed.include?(value.slice.delete(" "))
      end
    end

    # The receiver chain starts at a pinned K.where(…) call (AccountEntry.where(fund_id: @fund.id).joins(…))
    # or at one of the engine's own records (capital_commitment.account_entries.joins(…), @fund.…)
    def pinned_chain?(node)
      while node.is_a?(Prism::CallNode)
        if constant?(node.receiver)
          pins = @profile[:pinned_roots][constant_name(node.receiver)]
          return pins ? node.name == :where && pinned_where?(node, pins) : false
        end
        node = node.receiver
      end
      (node.is_a?(Prism::LocalVariableReadNode) || node.is_a?(Prism::InstanceVariableReadNode)) && @profile[:scoped_roots].include?(node.name)
    end

    # x.custom_fields.some_field — CustomFieldsProxy answers any name from json_fields. Any name Object
    # itself responds to is a real method there, so it must be on the allowlist like any other call.
    def custom_field_read?(node)
      receiver = node.receiver
      return false unless receiver.is_a?(Prism::CallNode) && receiver.name == :custom_fields
      return false unless node.name.to_s.match?(CUSTOM_FIELD_NAME) && (node.arguments.nil? || node.arguments.arguments.empty?) && node.block.nil?

      @profile[:methods].include?(node.name) || !object_method?(node.name)
    end

    def object_method?(name)
      Object.method_defined?(name) || Object.private_method_defined?(name)
    end

    # []= (and x[k] ||= v) only on a formula's own local, or on the receivers the profile names
    def check_index_write(receiver)
      return if receiver.is_a?(Prism::LocalVariableReadNode)
      return if receiver && @profile[:index_write_receivers].any? { |pattern| receiver.slice.match?(pattern) }

      @errors << "[]= outside a local"
    end

    # Raw SQL strings: where/not take SQL only as the first argument (the rest are bind values, e.g.
    # where("name LIKE ?", "%usd")); order/pluck/sum/… take SQL in every string argument
    def check_sql_arguments(node)
      args = node.arguments&.arguments
      return if args.to_a.empty?

      sql_args = if @profile[:sql_first_arg].include?(node.name)
                   first = args.first
                   # where(["a = ?", x]) — the array's first element is the SQL
                   first.is_a?(Prism::ArrayNode) ? [first.elements.first].compact : [first]
                 elsif @profile[:sql_all_args].include?(node.name)
                   args
                 else
                   []
                 end
      sql_args.each do |arg|
        next unless arg.is_a?(Prism::StringNode) || arg.is_a?(Prism::InterpolatedStringNode)

        @errors << "raw SQL #{node.name}(#{arg.slice[0, 40]})" unless arg.is_a?(Prism::StringNode) && safe_sql?(arg.unescaped)
      end
    end

    def safe_sql?(sql)
      # JSON path reads and allowed functions (ABS(…), COALESCE(…)) are reduced to plain tokens first
      reduced = sql.gsub(SQL_JSON_PATH, " json_path ").gsub(@profile[:sql_functions], " ( ")
      !reduced.match?(@profile[:sql_keywords]) && !reduced.match?(SQL_PUNCTUATION) && reduced.gsub(SQL_TOKEN, "").strip.empty?
    end

    # joins("INNER JOIN investors ON investors.id = account_entries.parent_id") — one join to an
    # allowed table on a column-to-column condition; symbol / hash joins name associations
    def check_join_arguments(node)
      return unless @profile[:pinned_only_methods].include?(node.name)

      node.arguments&.arguments&.each do |arg|
        next if arg.is_a?(Prism::SymbolNode) || arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::HashNode)
        next if arg.is_a?(Prism::StringNode) && arg.unescaped.match?(@profile[:join_sql])

        @errors << "#{node.name}(#{arg.slice[0, 40]}) is not an allowed join"
      end
    end

    # map(&:amount_cents) — only a symbol naming an allowed method; never &method(:x) or &some_proc
    def check_block_pass(node)
      return unless node.block.is_a?(Prism::BlockArgumentNode)

      expression = node.block.expression
      ok = expression.is_a?(Prism::SymbolNode) && @profile[:methods].include?(expression.unescaped.to_sym) &&
           !@profile[:hard_deny].member?(expression.unescaped.to_sym)
      @errors << "block-pass must be &:allowed_symbol" unless ok
    end

    # inject(:+) — the symbol must be an operator, or inject(:destroy) would call it
    def check_inject_symbol(node)
      return unless %i[inject reduce sum].include?(node.name) && node.arguments

      symbols = node.arguments.arguments.grep(Prism::SymbolNode)
      @errors << "#{node.name}(:sym) with non-operator" if node.name != :sum && symbols.any? { |sym| !operator?(sym.unescaped.to_sym) }
    end

    # x.is_a?(String) — a value-class constant as the argument of a type test. The constant is then
    # visited as a child; it is marked here so check_constant knows it was already approved.
    def check_type_argument(node)
      return unless %i[is_a? kind_of? instance_of?].include?(node.name)

      node.arguments&.arguments&.each do |arg|
        if constant?(arg) && @profile[:type_constants].include?(constant_name(arg))
          approved_constants << arg
        else
          @errors << "type test against #{arg.slice[0, 40]}"
        end
      end
    end

    def approved_constants
      @approved_constants ||= Set.new.compare_by_identity
    end

    def operator?(name)
      %i[+ - * / % == != < > <= >= <=> & |].include?(name)
    end

    # A constant is allowed only as a call receiver (checked in check_constant_call), a raisable error
    # (raise SkipRule) or an approved type-test argument. Anywhere else it is a value a formula could
    # call anything on (x = AccountEntry; x.where(...) would skip the fund pin).
    def check_constant(node, parent)
      return if parent.is_a?(Prism::CallNode) && parent.receiver.equal?(node)
      return if @profile[:raisable].include?(constant_name(node))
      return if approved_constants.include?(node)

      @errors << "bare constant #{constant_name(node)}"
    end

    def constant?(node)
      node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
    end

    def constant_name(node)
      node.is_a?(Prism::ConstantReadNode) ? node.name.to_s : (node.full_name rescue node.slice) # rubocop:disable Style/RescueModifier
    end
  end
end
