class FundFormula < ApplicationRecord
  include ForInvestor
  include Trackable.new

  belongs_to :fund, optional: true, touch: true
  belongs_to :entity, optional: true
  acts_as_list scope: %i[fund_id], column: :sequence

  enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :accounting, -> { where(rule_for: "Accounting") }
  scope :reporting, -> { where(rule_for: "Reporting") }

  validates :entry_type, length: { maximum: 50 }
  validates :name, length: { maximum: 125 }
  validates :rule_type, length: { maximum: 30 }
  validates :commitment_type, length: { maximum: 10 }
  validates :formula, :entry_type, :name, :rule_type, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }

  delegate :to_s, to: :name

  validate :formula_kosher?
  def formula_kosher?
    errors.add(:formula, "You cannot do CRUD operations in a formula") if formula.downcase.match?(SAFE_EVAL_REGEX)
  end

  # Sometimes we just want to sample the commitments to check if all the formulas are ok
  def commitments(sample)
    cc = fund.capital_commitments
    logger.debug "Sampling 1 commitment" if sample
    case commitment_type
    when "Pool"
      cc = sample ? cc.pool.limit(1) : cc.pool
    when "CoInvest"
      cc = sample ? cc.co_invest.limit(1) : cc.co_invest
    end
    cc
  end

  def template_field_name
    name.titleize.delete(' :,;').underscore
  end

  def interpolate_formula
    # Regular expression to match variable names

    statement = formula

    # Define a regular expression to match different types of variables
    variable_regex = /[@$]?[a-z_][a-zA-Z_0-9]*\b/

    # Extract all potential variables from the statement
    potential_variables = statement.scan(variable_regex)

    # Filter out method calls by checking if they are followed by an opening parenthesis
    variables = potential_variables.select { |var| statement.scan(/#{Regexp.escape(var)}\s*\(/).empty? }

    # Remove any potential duplicates
    variables.uniq
  end

  def parse_statement(binding)
    statement = formula
    buffer = Parser::Source::Buffer.new('(string)')
    buffer.source = statement
    ast = Parser::CurrentRuby.new.parse(buffer)

    expressions = []
    find_expressions(ast, expressions)
    expression_map = {}
    expressions.each do |exp|
      expression_map[exp] = eval(exp, binding)
    end
    expression_map
  end

  def find_expressions(node, expressions)
    case node.type
    when :send
      expressions << node.loc.expression.source
    when :lvar, :ivar, :const
      expressions << node.loc.name.source
    when :str
      expressions << node.loc.expression.source
    end

    node.children.each do |child|
      find_expressions(child, expressions) if child.is_a?(Parser::AST::Node)
    end
  end
end
