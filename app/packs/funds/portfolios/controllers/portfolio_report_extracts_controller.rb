# app/controllers/portfolio_report_extracts_controller.rb
class PortfolioReportExtractsController < ApplicationController
  before_action :set_portfolio_report_extract, only: %i[show edit update generate_tear_sheet update_slides_content]

  def index
    @portfolio_report_extracts = policy_scope(PortfolioReportExtract).order(id: :desc)
    @portfolio_report_extracts = @portfolio_report_extracts.where(portfolio_report_id: params[:portfolio_report_id]) if params[:portfolio_report_id].present?
    @portfolio_report_extracts = @portfolio_report_extracts.where(portfolio_company_id: params[:portfolio_company_id]) if params[:portfolio_company_id].present?
    @portfolio_report_extracts = @portfolio_report_extracts.includes(:portfolio_company, :portfolio_report_section)
  end

  def show
    @presentation = @portfolio_report_extract.tear_sheet_presentation
  end

  def generate_tear_sheet
    @presentation = @portfolio_report_extract.tear_sheet_presentation
    @palette = params[:palette] || @presentation&.blueprint&.dig("palette") || "serene_blue"
    @print_pdf = params[:print_pdf] == "true"
    @slides_user = current_user

    force_generate = params[:generate] == 'true'

    if force_generate || @presentation.nil?
      GenerateTearSheetJob.perform_later(current_user.id, @portfolio_report_extract.id, force_generate: true, palette: @palette)
      @slides_html = nil
    else
      @slides_html = @presentation.content_html
    end

    respond_to do |format|
      format.html { render layout: "presentation", template: "portfolio_report_extracts/generate_tear_sheet" }
      format.json do
        if @slides_html
          render json: { html: @slides_html, status: "ready" }
        else
          render json: { status: "queued" }, status: :accepted
        end
      end
    end
  end

  def update_slides_content
    @presentation = @portfolio_report_extract.tear_sheet_presentation

    if @presentation.nil?
      render json: { error: "Presentation not found" }, status: :not_found
      return
    end

    if @presentation.update(content_html: params[:content_html])
      render json: { status: "success" }
    else
      render json: { error: @presentation.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # GET /portfolio_report_extracts/:id/edit
  def edit
    @sections = normalized_sections(@portfolio_report_extract.data)
  end

  # PATCH/PUT /portfolio_report_extracts/:id
  def update
    @sections = build_sections_from_params(sections_params)

    @portfolio_report_extract.data = @sections

    if @portfolio_report_extract.save
      redirect_to portfolio_report_path(@portfolio_report_extract.portfolio_report),
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
