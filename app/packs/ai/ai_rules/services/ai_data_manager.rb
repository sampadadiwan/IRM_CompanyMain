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
    property :record, type: "object", description: "The record to get the details of", required: false
  end

  define_function :current_date, description: "Get the current date" do
    property :date, type: "string", description: "The date", required: false
  end

  define_function :validate_document, description: "validate the document by answering the questions about it" do
    property :question, type: "string", description: "The validation question that needs to be answered", required: true
  end

  define_function :get_document, description: "Get a named document from the record, may return nil" do
    property :document_name, type: "string", description: "name of the document", required: true
  end

  define_function :get_data, description: "Get a associated data  from the record, may return nil" do
    property :associated_data, type: "string", description: "associated data such as aggregate_portfolio_investment, fund, valuation etc required from 'from_name'", required: false
  end

  define_function :get_latest_data, description: "Get a latest associated data from the record, may return nil" do
    property :associated_data, type: "string", description: "associated data such as aggregate_portfolio_investment, fund, valuation etc required from 'from_name'", required: true
    property :order_by, type: "string", description: "The order by field", required: false
  end

  define_function :date_difference_in_days, description: "Get the days between start date and end date" do
    property :start_date, type: "string", description: "The start date", required: true
    property :end_date, type: "string", description: "The end date", required: true
  end

  def get_record_details(_record: nil)
    @record.to_json
  end

  def validate_document(question:)
    msg = "CDM: validate_document called with document: #{@document.name} and question: #{question}"
    @audit_log[:validate_document] = msg
    Rails.logger.debug { msg }
    document = @document
    doc_question = DocQuestion.new(question:)
    result = DocLlmValidator.wtf?(model: document.owner, document:, doc_questions: [doc_question], save_check_results: false)

    validation_results = result.success? ? result[:doc_question_answers] : "Error in validation"
    msg = "CDM: Validation results: #{validation_results}"
    Rails.logger.debug { msg }
    @audit_log[:validate_document_result] = msg
    validation_results
  end

  def get_document(document_name:)
    msg = "CDM: get_document called with document_name: #{document_name}"
    Rails.logger.debug { msg }
    @audit_log[:get_document] = msg
    @document = @record.documents.where(name: document_name).last
    @document.to_json
  end

  def get_data(associated_data: nil)
    msg = "CDM: get_data called with associated_data: #{associated_data}"
    Rails.logger.debug { msg }
    @audit_log[:get_data] = msg
    if associated_data.present?
      response = @record.send(associated_data.underscore.to_sym).to_json
    else
      @record = from_name.constantize.where(id:).first
      response = @record.to_json
    end
    response
  end

  def get_latest_data(associated_data:, order_by: :id)
    msg = "CDM: get_latest_data called with associated_data: #{associated_data}, order_by: #{order_by}"
    Rails.logger.debug { msg }
    @audit_log[:get_latest_data] = msg
    @record.send(associated_data.underscore.to_sym).order(order_by.to_s => :desc).first.to_json
  end

  def date_difference_in_days(start_date:, end_date:)
    Rails.logger.debug { "CDM: date_difference called with start_date: #{start_date} and end_date: #{end_date}" }
    response = (Date.parse(end_date) - Date.parse(start_date)).to_i
    @audit_log[:date_difference_in_days] = response
    response
  end

  def current_date(_date: nil)
    Time.zone.today.to_s
  end

  def self.test
    # pi_queries = [
    #   "Get the associated data for Fund and the AggregatePortfolioInvestment from the record. Then calculate the aggregate models net bought amount divided by the fund's committed amount and check if this is > 25% or < 10%. ",
    #   "Get the latest associated data for Valuations from the record, order_by valuation_date, and check that its valuation_date is no more than 120 days before the current date #{Time.zone.today}. ",
    #   "Get the document with document name 'IC Approval Note WS' from the record, and check if it exists.  Validate whether it has all Approval Signatures at the bottom with real signatures"
    # ]

    ComplianceAssistant.run_ai_checks(PortfolioInvestment.find(8), User.find(21), nil)

    # fund_queries = [
    #   # "Get the associated data for CapitalCommitments from the record. For each commitment check that the percentage < 20%.",
    #   "Get the associated data for CapitalRemittances from the record. For each remittance check that the status is 'Paid'"
    # ]

    ComplianceAssistant.run_ai_checks(Fund.find(1), User.find(21), nil)

    # cc_queries = [
    #   "Get the record details. Then calculate the percentage < 10%. ",
    #   "Get the document with document name Directors From the record, and check if it exists. Validate whether it is signed by both directors."
    # ]

    ComplianceAssistant.run_ai_checks(CapitalCommitment.find(1), User.find(21), nil)
  end
end
