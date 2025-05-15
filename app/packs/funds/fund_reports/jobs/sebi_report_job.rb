class SebiReportJob < ApplicationJob
  require 'spreadsheet'
  require 'fileutils'

  queue_as :low
  ALL_REPORTS = %w[CorpusDetails InformationOnInvestments InfoOnInvestors SEBIReport].freeze
  ALL_REPORT_JOBS = %w[CorpusDetails InformationOnInvestments InfoOnInvestors].freeze

  REPORT_TO_SHEET = { "CorpusDetails" => "Capital raised and invested",
                      "InformationOnInvestments" => "Investments",
                      "InfoOnInvestors" => "Commitment received (Nos)" }.freeze

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  # rubocop:disable Metrics/ParameterLists
  def perform(entity_id, fund_id, report_name, start_date, end_date, user_id, excel: false, single: false)
    Chewy.strategy(:sidekiq) do
      fund_ids = fund_id.present? ? [fund_id] : Entity.find(entity_id).fund_ids
      fund_ids.each do |fid|
        generate(fid, report_name, start_date, end_date, user_id, excel:, single:)
      end
    end

    notify(user_id)
  end

  def generate(fund_id, report_name, start_date, end_date, user_id, excel: false, single: false)
    if excel
      generate_partial_sebi_report(fund_id, report_name, start_date, end_date, user_id, single: single)
    elsif report_name.delete(" ").casecmp?("SEBIReport")
      generate_sebi_report(fund_id, start_date, end_date, user_id)
    else
      reporter = "#{report_name}Job".constantize.new
      reporter.generate_report(fund_id, start_date, end_date)
    end
  end
  # rubocop:enable Metrics/ParameterLists

  def report_folder(fund)
    fund.document_folder.children.private_folders.where(name: "Reports").first
  end

  def generate_sebi_report(fund_id, start_date, end_date, user_id)
    FileUtils.cp(Rails.public_path.join('sample_uploads/SEBI report.xls'), Rails.root.join("tmp/sebi_report.xls"))
    excel = Spreadsheet.open(Rails.root.join("tmp/sebi_report.xls").to_s)

    ALL_REPORT_JOBS.each do |report_name|
      reporter = "#{report_name}Job".constantize.new
      excel = reporter.generate_excel_report(fund_id, start_date, end_date, excel)
    end
    # save excel as a Document and attach it to the fund
    fund = Fund.find(fund_id)
    begin
      # Save the Excel file to disk
      excel.write(Rails.root.join("tmp/sebi_report.xls"))

      # Upload the file to Shrine
      file = Rails.root.join("tmp/sebi_report.xls").open
      report_name = "SEBI Report #{start_date} to #{end_date}"
      ActiveRecord::Base.transaction do
        Document.where(name: report_name, entity_id: fund.entity_id).destroy_all if Document.exists?(name: report_name, entity_id: fund.entity_id)
        Document.create!(entity_id: fund.entity_id, owner: fund, name: "SEBI Report #{start_date} to #{end_date}", file:, folder: report_folder(fund), user: User.find(user_id), orignal: true, download: true)
      end
    rescue StandardError => e
      UserAlert.new(message: "SEBI Report Generation Failed: #{e.message}", user_id:, level: "danger").broadcast if user_id.present?
    end
  end

  def generate_partial_sebi_report(fund_id, report_name, start_date, end_date, user_id, single: false)
    FileUtils.cp(Rails.root.join("public/sample_uploads/#{report_name}.xls"), Rails.root.join("tmp/#{report_name}.xls"))
    excel = Spreadsheet.open(Rails.root.join("tmp/#{report_name}.xls").to_s)
    reporter = "#{report_name}Job".constantize.new

    excel = reporter.generate_excel_report(fund_id, start_date, end_date, excel, single:)
    # save excel as a Document and attach it to the fund
    fund = Fund.find(fund_id)
    begin
      # Save the Excel file to disk
      excel.write(Rails.root.join("tmp/#{report_name}.xls"))

      # Upload the file to Shrine
      file = Rails.root.join("tmp/#{report_name}.xls").open
      report_name += "(All Funds)" unless single
      report_name = "#{report_name} #{start_date} to #{end_date}"
      ActiveRecord::Base.transaction do
        Document.where(name: report_name, entity_id: fund.entity_id).destroy_all if Document.exists?(name: report_name, entity_id: fund.entity_id)
        Document.create!(entity_id: fund.entity_id, owner: fund, name: report_name, file:, folder: report_folder(fund), user: User.find(user_id), orignal: true, download: true)
      end
    rescue StandardError => e
      UserAlert.new(message: "#{report_name} Excel Generation Failed: #{e.message}", user_id:, level: "danger").broadcast if user_id.present?
    end
  end

  def notify(user_id)
    UserAlert.new(user_id:, message: "Fund report generation completed. Please refresh the page.", level: "success").broadcast
  end
end
