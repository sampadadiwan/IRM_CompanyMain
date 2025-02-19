class CrisilReportJob < ApplicationJob
  require 'spreadsheet'
  require 'fileutils'

  queue_as :low
  ALL_REPORTS = %w[CRISILReport].freeze
  ALL_REPORT_JOBS = %w[SchemeLevelDetails CashFlow HalfYearlyValuation].freeze

  REPORT_TO_SHEET = { "SchemeLevelDetails" => "Scheme Level Details",
                      "CashFlow" => "Cash flow",
                      "HalfYearlyValuation" => "Half-yearly valuation" }.freeze

  def perform(entity_id, fund_id, report_name, start_date, end_date, user_id, excel: false, single: false) # rubocop:disable Metrics/ParameterLists
    Chewy.strategy(:sidekiq) do
      fund_ids = fund_id.present? ? [fund_id] : Entity.find(entity_id).fund_ids
      fund_ids.each do |fid|
        GenerateCrisilReport.call(fund_id: fid, report_name:, start_date:, end_date:, user_id:, excel:, single:)
      end
    end
  end
end
