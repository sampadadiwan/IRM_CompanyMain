# This class is responsible for managing the data that is used in the compliance AI.
class AiDataManager
  extend Langchain::ToolDefinition
  include Langchain::DependencyHelper

  attr_accessor :record, :audit_log

  def initialize(record)
    @record = record
    @audit_log = {}
  end

  define_function :get_record_details, description: "Get the details of the record" do
    property :record, type: "string", description: "Unused", required: false
  end

  define_function :current_date, description: "Get the current date" do
    property :date, type: "string", description: "The date", required: false
  end

  define_function :validate_document, description: "validate the document by answering the questions about it" do
    property :question, type: "string", description: "The validation question that needs to be answered", required: true
  end

  define_function :extract_info, description: "extract information from the document" do
    property :question, type: "string", description: "The information to be extracted", required: true
  end

  define_function :get_document, description: "Get a named document from the record, may return nil" do
    property :document_name, type: "string", description: "name of the document", required: true
  end

  define_function :get_data, description: "Get a associated data  from the record, may return nil" do
    property :associated_data, type: "string", description: "associated data such as aggregate_portfolio_investment, fund, valuation etc required from 'from_name'", required: false
    property :where, type: "string", description: "The where clause", required: false
    property :sum_field, type: "string", description: "The sum field", required: false
    property :count, type: "boolean", description: "The count of the associated data", required: false
  end

  define_function :get_latest_data, description: "Get a latest associated data from the record, may return nil" do
    property :associated_data, type: "string", description: "associated data such as aggregate_portfolio_investment, fund, valuation etc required from 'from_name'", required: true
    property :where, type: "string", description: "The where clause", required: false
    property :order_by, type: "string", description: "The order by field", required: false
  end

  define_function :date_difference_in_days, description: "Get the days between start date and end date" do
    property :start_date, type: "string", description: "The start date", required: true
    property :end_date, type: "string", description: "The end date", required: true
  end

  def get_record_details(_record: nil)
    response = @record.to_json
    @audit_log["#{@record.class.name} Details"] = JSON.parse(response)
    response
  end

  def validate_document(question:)
    msg = "CDM: validate_document called with document: #{@document.name} and question: #{question}"
    @audit_log[:validate_document] = msg
    Rails.logger.debug { msg }
    document = @document
    doc_question = DocQuestion.new(question:)
    result = DocLlmValidator.call(model: document.owner, document:, doc_questions: [doc_question], save_check_results: false)

    validation_results = result.success? ? result[:doc_question_answers] : "Error in validation"
    msg = "CDM: Validation results: #{validation_results}"
    Rails.logger.debug { msg }
    @audit_log[question] = validation_results
    validation_results
  end

  def extract_info(question:)
    msg = "CDM: extract_info called with document: #{@document.name} and question: #{question}"
    @audit_log[:extract_info] = msg
    Rails.logger.debug { msg }
    document = @document
    DocQuestion.new(question:)
    result = DocLlmExtractor.call(model: document.owner, document:, save_check_results: false)

    extracted_info = result.success? ? result[:extracted_info] : "Error in validation"
    msg = "CDM: extract_info results: #{extracted_info}"
    Rails.logger.debug { msg }
    @audit_log[question] = extract_info
    extracted_info
  end

  def get_document(document_name:)
    msg = "CDM: get_document called with document_name: #{document_name}"
    Rails.logger.debug { msg }
    @document = @record.documents.where(name: document_name).last
    response = @document.to_json
    @audit_log[:get_document] = response
    response
  end

  # Tokens with no legitimate place in a single-table filter expression, and the building
  # blocks of every injection through it: statement terminators, comments, subqueries and DML.
  FORBIDDEN_IN_WHERE = %r{;|--|/\*|\bselect\b|\bunion\b|\binsert\b|\bupdate\b|\bdelete\b|
                          \bdrop\b|\btruncate\b|\binto\b|\bsleep\b|\bbenchmark\b|\bload_file\b}xi

  # SQL words a filter may legitimately contain that are not column references: boolean and
  # comparison operators, plus the date/string functions compliance rules actually use.
  # Everything else in a clause must be a column on the target model itself.
  WHERE_KEYWORDS = %w[
    and or not null is in like ilike between true false asc desc distinct
    now curdate current_date current_timestamp date year month day days interval
    coalesce ifnull lower upper trim length abs round cast as case when then else end
  ].freeze

  # Rows returned when a call asks for records rather than a count or a sum. Some of these
  # associations are very large (a commitment's account_entries is the ledger), and the
  # response is serialised twice -- once as the tool result, once into the audit log.
  MAX_ROWS = 500

  def get_data(associated_data: nil, where: nil, sum_field: nil, count: false)
    msg = "CDM: get_data called with associated_data: #{associated_data}, where: #{where}, sum_field: #{sum_field}, count: #{count}"
    Rails.logger.debug { msg }

    return tool_error("associated_data is required.") if associated_data.blank?

    reflection = association_for(associated_data)
    return tool_error(unknown_association_message(associated_data)) unless reflection
    if reflection.polymorphic?
      return tool_error("'#{associated_data}' is polymorphic — its target model is only known per row, " \
                        "so it cannot be filtered or aggregated here.")
    end

    return single_record_response(reflection, where, sum_field, count) unless reflection.collection?

    al = []
    al << "associated_data: #{associated_data}"
    al << "where: #{where}" if where.present?
    al << "sum_field: #{sum_field}" if sum_field.present?
    al << "count: #{count}" if count

    model = reflection.klass
    if (problem = where_clause_error(model, where) || aggregate_field_error(model, sum_field))
      return tool_error(problem)
    end

    @associated_data = @record.public_send(reflection.name)

    @associated_data = @associated_data.where(where) if where.present?

    # Bounded before the audit log is written, so the logged SQL is the query that actually
    # ran. An unbounded to_json here would materialise the whole association -- a
    # commitment's account_entries is the ledger -- and then again into the audit log below.
    @associated_data = @associated_data.limit(MAX_ROWS) if sum_field.blank? && !count
    @audit_log["#{al.join(', ')} Query"] = @associated_data.respond_to?(:to_sql) ? @associated_data.to_sql : @associated_data
    @associated_data = @associated_data.sum(storage_column(model, sum_field).to_sym) if sum_field.present?
    @associated_data = @associated_data.count if count

    response = @associated_data.to_json
    Rails.logger.debug { "CDM: get_data response: #{response}" }
    @audit_log["#{al.join(', ')} Value"] = JSON.parse(response)

    response
  end

  def get_latest_data(associated_data:, where: nil, order_by: :id)
    msg = "CDM: get_latest_data called with associated_data: #{associated_data}, order_by: #{order_by}"
    Rails.logger.debug { msg }

    reflection = association_for(associated_data)
    return tool_error(unknown_association_message(associated_data)) unless reflection
    return tool_error("'#{associated_data}' is not a collection this tool can order and take the latest of.") if reflection.polymorphic? || !reflection.collection?

    model = reflection.klass
    order_column = order_by.to_s.underscore
    if (problem = where_clause_error(model, where) || column_error(model, order_column, "order_by"))
      return tool_error(problem)
    end

    latest = @record.public_send(reflection.name).order(storage_column(model, order_column).to_sym => :desc)
    latest = latest.where(where) if where.present?
    latest = latest.first
    response = latest.to_json
    @audit_log["get_latest_data: #{associated_data} order_by #{order_by}"] = JSON.parse(response)
    response
  end

  def date_difference_in_days(start_date:, end_date:)
    Rails.logger.debug { "CDM: date_difference called with start_date: #{start_date} and end_date: #{end_date}" }
    response = (Date.local_parse(end_date) - Date.local_parse(start_date)).to_i
    @audit_log[:date_difference_in_days] = response
    response
  end

  def current_date(_date: nil)
    response = Time.zone.today.to_s
    @audit_log[:current_date] = response
    response
  end

  def self.test
    # pi_queries = [
    #   "Get the associated data for Fund and the AggregatePortfolioInvestment from the record. Then calculate the aggregate models net bought amount divided by the fund's committed amount and check if this is > 25% or < 10%. ",
    #   "Get the latest associated data for Valuations from the record, order_by valuation_date, and check that its valuation_date is no more than 120 days before the current date #{Time.zone.today}. ",
    #   "Get the document with document name 'IC Approval Note WS' from the record, and check if it exists.  Validate whether it has all Approval Signatures at the bottom with real signatures"
    # ]

    # ComplianceAssistant.run_ai_checks(PortfolioInvestment.find(8), User.find(21), nil)

    # fund_queries = [
    #   # "Get the associated data for CapitalCommitments from the record. For each commitment check that the percentage < 20%.",
    #   "Get the associated data for CapitalRemittances from the record. For each remittance check that the status is 'Paid'"
    # ]

    # ComplianceAssistant.run_ai_checks(Fund.find(1), User.find(21), nil)

    # cc_queries = [
    #   "Get the record details. Then calculate the percentage < 10%. ",
    #   "Get the document with document name Directors From the record, and check if it exists. Validate whether it is signed by both directors."
    # ]

    # ComplianceAssistant.run_ai_checks(CapitalCommitment.find(1), User.find(21), nil)

    dm = AiDataManager.new(PortfolioInvestment.find(8))
    assistant = AiAssistant.new(dm, DocLlmExtractor::INSTRUCTIONS)
    assistant.query("Get the document called 'KPIs' from the record and extract key financial information from it, and return the raw json.")
  end

  private

  # Every argument below arrives from an LLM. Three of them used to reach a sink that
  # executes what it is given:
  #
  #   @record.send(associated_data.underscore.to_sym)  -> ANY zero-arg method on the record.
  #                                                       `destroy` has arity 0, so an
  #                                                       `associated_data` of "destroy"
  #                                                       deleted the record.
  #   .where(where)                                    -> raw SQL, verbatim.
  #   .sum(sum_field.to_sym)                           -> raw SQL; a subquery here executes
  #                                                       and its value is returned.
  #
  # This is the same class of hole already closed for `scope` in FundAssistantDataManager
  # and for aggregate fields in perform_aggregation -- an LLM-supplied string reaching a
  # method that trusts its caller. Each is now checked against the record's real
  # associations and the target model's real columns before anything runs.

  # @return [ActiveRecord::Reflection::AssociationReflection, nil]
  def association_for(name)
    return nil if name.blank?

    candidate = name.to_s.underscore
    @record.class.reflect_on_all_associations.find do |reflection|
      reflection.name.to_s == candidate || reflection.name.to_s == candidate.pluralize ||
        reflection.name.to_s == candidate.singularize
    end
  end

  def unknown_association_message(name)
    available = @record.class.reflect_on_all_associations.map(&:name).sort.join(", ")
    "'#{name}' is not an association of #{@record.class.name}. Available: #{available}."
  end

  # @return [String, nil] why this filter cannot be used, or nil when it is safe
  def where_clause_error(model, clause)
    return nil if clause.blank?

    # Quoted literals are stripped FIRST, then scanned. A value that legitimately contains a
    # forbidden word ("notes like '%update%'") must not read as an injection, and a column
    # name inside a literal must not read as a reference.
    stripped = strip_literals(clause.to_s)
    if stripped.match?(FORBIDDEN_IN_WHERE)
      return "The where clause may not contain subqueries, comments, statement separators " \
             "or data-modifying statements. Filter on #{model.name}'s own columns only."
    end

    unknown = identifiers_in(stripped) - permitted_identifiers(model)
    return nil if unknown.empty?

    "Unknown column#{'s' if unknown.size > 1} #{unknown.map { |u| "'#{u}'" }.join(', ')} " \
      "in the where clause. Filter on #{model.name}'s own columns: #{model.column_names.sort.join(', ')}."
  end

  def strip_literals(clause)
    clause.gsub(/'[^']*'/, "?").gsub(/"[^"]*"/, "?")
  end

  def identifiers_in(stripped)
    stripped.scan(/[A-Za-z_][A-Za-z0-9_.]*/).map(&:downcase).uniq - WHERE_KEYWORDS
  end

  # The target model's own columns, and those columns qualified with its own table name.
  #
  # Deliberately NOT the columns of associated tables. Permitting `other_table.column`
  # turned every ransackable association into a read channel: Document declares
  # `approved_by` (a User), so `where: "users.encrypted_password like '$2a$12$a%'"` with
  # `count: true` was a working binary oracle over password hashes -- the very class of hole
  # this guard exists to close, reintroduced by being generous about joins. Nothing is
  # joined now either, which also removes the column-ambiguity the old blanket join caused.
  def permitted_identifiers(model)
    table = model.table_name
    (model.column_names + model.column_names.map { |c| "#{table}.#{c}" } + [table]).map(&:downcase).uniq
  end

  # @return [String, nil] why this column cannot be used, or nil when it is a real column
  def column_error(model, name, argument)
    return nil if name.blank? || model.column_names.include?(name.to_s) ||
                  model.column_names.include?("#{name}_cents")

    "'#{name}' is not a column on #{model.name} and cannot be used as #{argument}. " \
      "Available: #{model.column_names.sort.join(', ')}."
  end

  def aggregate_field_error(model, sum_field)
    column_error(model, sum_field, "sum_field")
  end

  # Money is stored in `<name>_cents` and read as `<name>`. column_error accepts either, so
  # the sink has to translate -- otherwise a validated `sum_field: "call_amount"` reaches
  # `.sum(:call_amount)` and raises on an unknown column. Mirrors perform_aggregation.
  def storage_column(model, name)
    name = name.to_s
    return name if model.column_names.include?(name)

    model.column_names.include?("#{name}_cents") ? "#{name}_cents" : name
  end

  # A belongs_to/has_one yields a record, not a relation, so where/sum_field/count have
  # nothing to act on -- they used to reach .where/.sum/.count on a model instance and raise
  # NoMethodError after the guard had already reported the arguments valid.
  def single_record_response(reflection, where, sum_field, count)
    if where.present? || sum_field.present? || count
      return tool_error("'#{reflection.name}' is a single #{reflection.klass.name}, not a collection — " \
                        "where, sum_field and count do not apply. Call it on its own to get the record.")
    end

    record = @record.public_send(reflection.name)
    response = record.to_json
    @audit_log["associated_data: #{reflection.name} Value"] = JSON.parse(response)
    response
  end

  # Errors go back to the model as data so it can correct itself on the next call, the same
  # way the MCP tools report a rejected argument.
  def tool_error(message)
    Rails.logger.debug { "CDM: rejected — #{message}" }
    @audit_log[:error] = message
    { error: message }.to_json
  end
end
