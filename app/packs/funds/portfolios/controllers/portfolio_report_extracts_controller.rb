# app/controllers/portfolio_report_extracts_controller.rb
class PortfolioReportExtractsController < ApplicationController
  before_action :set_portfolio_report_extract, only: %i[edit update]

  def index
    @portfolio_report_extracts = policy_scope(PortfolioReportExtract).order(id: :desc)
    @portfolio_report_extracts = @portfolio_report_extracts.where(portfolio_report_id: params[:portfolio_report_id]) if params[:portfolio_report_id].present?
    @portfolio_report_extracts = @portfolio_report_extracts.where(portfolio_company_id: params[:portfolio_company_id]) if params[:portfolio_company_id].present?
    @portfolio_report_extracts = @portfolio_report_extracts.includes(:portfolio_company, :portfolio_report_section)
  end

  # GET /portfolio_report_extracts/:id/edit
  def edit
    @sections = normalized_sections(@portfolio_report_extract.data)
  end

  # PATCH/PUT /portfolio_report_extracts/:id
  def update
    @sections = build_sections_from_params(sections_params)

    @portfolio_report_extract.data = @sections.to_json

    if @portfolio_report_extract.save
      redirect_to edit_portfolio_report_extract_path(@portfolio_report_extract),
                  notice: "Portfolio report extract updated successfully."
    else
      flash.now[:alert] = "Could not save changes. Please review and try again."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_portfolio_report_extract
    @portfolio_report_extract = PortfolioReportExtract.find(params[:id])
    authorize @portfolio_report_extract
  end

  def sections_params
    params.require(:sections).values.map do |section|
      section.permit(:name, :body)
    end
  end

  # Safely parse the stored data into a Hash<String, Array<String>>
  def normalized_sections(raw_data)
    hash =
      case raw_data
      when String
        begin
          JSON.parse(raw_data.presence || "{}")
        rescue JSON::ParserError
          {}
        end
      when Hash
        raw_data
      else
        {}
      end

    hash.each_with_object({}) do |(key, value), result|
      # Ensure we always end up with an array of strings
      lines = Array(value).map(&:to_s)
      result[key.to_s] = lines
    end
  end

  # Build Hash<String, Array<String>> from the submitted textareas
  #
  # Expected params shape:
  # params[:sections] = [
  #   { name: "Quarterly Update", body: "line1\nline2\n..." },
  #   { name: "Financial Analysis", body: "..." }
  # ]
  def build_sections_from_params(sections_array)
    return {} unless sections_array.is_a?(Array)

    sections_array.each_with_object({}) do |section, result|
      key = section[:name].to_s
      body = section[:body].to_s

      # Split by line, strip whitespace, drop empty lines
      lines = body.split(/\r?\n/).map(&:strip).compact_blank
      result[key] = lines if key.present?
    end
  end
end
