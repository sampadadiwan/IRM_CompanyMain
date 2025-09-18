class FundFormula < ApplicationRecord
  include ForInvestor
  include Trackable.new

  # Make all models searchable
  update_index('fund_formula') { self if index_record? }

  TYPES = %w[AllocateMasterFundAccountEntry-Name AllocateMasterFundAccountEntryIndividual-Name AllocateMasterFundAccountEntry-EntryType AllocateMasterFundAccountEntryIndividual-EntryType AllocateAccountEntry-Name AllocateAccountEntryIndividual-Name AllocateAccountEntry-EntryType AllocateAccountEntryIndividual-EntryType AllocateAggregatePortfolios AllocatePortfolioInvestment AllocatePortfolioInvestment-Proforma AllocateMasterFundPortfolioInvestment AllocateMasterFundPortfolioInvestment-Proforma GenerateAccountEntry CumulateAccountEntry GenerateCustomField Percentage GeneratePortfolioNumbersForFund AllocateForPortfolioCompany AllocateForPortfolioCompany-Folio].sort.freeze

  STANDARD_COLUMNS = { "Sequence" => "sequence",
                       "Name" => "name",
                       "For" => "formula_for",
                       "Formula" => "formula",
                       "Entry Type" => "entry_type",
                       "Roll Up" => "roll_up",
                       "Enabled" => "enabled" }.freeze

  DEBUG_COLUMNS = { "Sequence" => "sequence",
                    "Name" => "name",
                    "For" => "formula_for",
                    "Template" => "template_field_name",
                    "Execution (ms)" => "execution_time",
                    "Entry Type" => "entry_type",
                    "Roll Up" => "roll_up",
                    "Enabled" => "enabled" }.freeze

  belongs_to :fund, optional: true, touch: true
  belongs_to :entity, optional: true
  acts_as_list scope: %i[fund_id], column: :sequence

  enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :accounting, -> { where(rule_for: "Accounting") }
  scope :reporting, -> { where(rule_for: "Reporting") }
  scope :without_ai_description, -> { where(ai_description: [nil, ""]) }

  validates :rule_type, :entry_type, length: { maximum: 50 }
  validates :name, length: { maximum: 125 }
  validates :formula, :entry_type, :name, :rule_type, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }

  validates :tag_list, length: { maximum: 255 }

  scope :with_tags, ->(tags) { where(tags.map { |_tag| "fund_formulas.tag_list LIKE ?" }.join(" OR "), *tags.map { |tag| "%#{tag}%" }) }
  scope :templates, -> { where(is_template: true) }

  delegate :to_s, to: :name

  validate :formula_kosher?
  def formula_kosher?
    errors.add(:formula, "You cannot do CRUD operations in a formula") if formula.downcase.match?(SAFE_EVAL_REGEX)
  end

  def tag_list=(tags)
    self[:tag_list] = if tags.is_a?(Array)
                        tags.join(",")
                      else
                        tags
                      end
  end

  def tag_list
    self[:tag_list].split(",").map(&:strip) if self[:tag_list].present?
  end

  # Sometimes we just want to sample the commitments to check if all the formulas are ok
  def commitments(end_date, sample)
    cc = if fund.custom_fields[:sample_commitment_ids_for_allocation].present?
           fund.capital_commitments.where(id: fund.custom_fields[:sample_commitment_ids_for_allocation].split(",").map(&:strip))
         else
           fund.capital_commitments.where(commitment_date: ..end_date)
         end
    logger.debug "Sampling 1 commitment" if sample
    sample ? cc.limit(3) : cc
  end

  def template_field_name
    name.titleize.delete(' :,;').underscore
  end

  def interpolate_formula(eval_string: nil)
    # Regular expression to match variable names

    statement = eval_string || formula

    # Define a regular expression to match different types of variables
    # variable_regex = /[@$]?[a-z_][a-zA-Z_0-9]*\b/
    # Define a regex to match only instance variables (starting with @)
    variable_regex = /@[\w_]+\b/

    # Extract all potential variables from the statement
    potential_variables = statement.scan(variable_regex)

    # Filter out method calls by checking if they are followed by an opening parenthesis
    variables = potential_variables.select { |var| statement.scan(/#{Regexp.escape(var)}\s*\(/).empty? }

    # Remove any potential duplicates
    variables.uniq
  end

  def parse_statement(binding, external_formula: nil)
    statement = external_formula || formula
    buffer = Parser::Source::Buffer.new('(string)')
    buffer.source = statement
    ast = Parser::CurrentRuby.new.parse(buffer)

    expressions = []
    find_expressions(ast, expressions)
    expression_map = {}
    expressions.each do |exp|
      unless exp.include?("SkipRule")
        val = eval(exp, binding)
        expression_map[exp] = val unless skip_statement(exp, val)
      end
    end
    expression_map
  end

  def skip_statement(exp, val)
    val.is_a?(ApplicationRecord) || val.is_a?(OpenStruct) ||
      val.is_a?(ActiveRecord::Relation) || val.is_a?(ActiveRecord::QueryMethods::WhereChain) ||
      val.is_a?(Array) || exp.delete("\"").strip == val
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

  def meta_data_hash
    @mdh ||= meta_data.split(";").to_h { |pair| pair.split("=") } if meta_data
    @mdh
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name description formula rule_type entry_type rule_for tag_list meta_data ai_description sequence enabled roll_up].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund].sort
  end
end
