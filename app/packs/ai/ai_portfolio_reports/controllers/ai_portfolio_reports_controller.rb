class AiPortfolioReportsController < ApplicationController
  skip_after_action :verify_authorized
  before_action :set_report, only: %i[show edit update destroy collated_report save_collated_report export_pdf export_docx toggle_master_web_search]

  def index
    @reports = policy_scope(AiPortfolioReport).order(created_at: :desc)
  end

  def new
    @report = AiPortfolioReport.new
    authorize @report
  end

  def create
    @report = AiPortfolioReport.new(report_params)
    @report.analyst_id = current_user.id
    authorize @report

    if @report.save
      @report.ai_chat_sessions.create!(analyst_id: current_user.id)
      GenerateSectionContentJob.perform_later(@report.id)
      redirect_to @report, flash: { ai_notice: 'Report created! AI is generating content for all sections (this may take a minute)...' }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @report
    @current_section = @report.ai_report_sections.find_by(id: params[:section_id]) ||
                       @report.ai_report_sections.order(:order_index).first
    @chat_session = @report.ai_chat_sessions.first || @report.ai_chat_sessions.create!(analyst_id: current_user.id)

    # Checkbox should only be checked if web search content actually exists and is being displayed
    # This ensures the checkbox accurately reflects what the user is seeing
    @show_web_search_version = @current_section.show_web_search_version? && @current_section.web_search_content_exists?
  end

  def edit
    authorize @report
    # Redirect to show page - the show page IS the editing interface
    redirect_to @report
  end

  def collated_report
    authorize @report

    # ALWAYS regenerate fresh with only reviewed sections
    @collated_content = generate_collated_content
    @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)
  end

  def save_collated_report
    authorize @report

    @report.collated_report_html = params[:content]
    @report.status = 'finalized' # ADD THIS LINE

    if @report.save
      render json: { success: true, message: 'Report saved successfully' }
    else
      render json: { success: false, error: 'Failed to save report' }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  def export_pdf
    authorize @report

    @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)
    company_name = @report.portfolio_company&.name&.parameterize || "portfolio-company"

    render pdf: "#{company_name}-report-#{Date.today}",
           template: 'ai_portfolio_reports/export_pdf',
           layout: false,
           page_size: 'A4',
           margin: { top: 20, bottom: 20, left: 20, right: 20 },
           encoding: 'UTF-8',
           print_media_type: true,
           disposition: 'attachment'
  end

  def export_docx
    authorize @report

    require 'htmltoword'

    @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)
    company_name = @report.portfolio_company&.name&.parameterize || "portfolio-company"

    # Render the Word template to get properly formatted HTML
    html_content = render_to_string(
      template: 'ai_portfolio_reports/export_docx',
      layout: false
    )

    # Convert HTML to DOCX
    file = Htmltoword::Document.create(html_content)

    # Send file
    send_data file,
              filename: "#{company_name}-report-#{Date.today}.docx",
              type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              disposition: 'attachment'
  end

  def destroy
    authorize @report
    @report.destroy
    redirect_to ai_portfolio_reports_path, notice: 'Report deleted.'
  end

  def toggle_master_web_search
    authorize @report

    # Convert string to boolean properly
    enabled = [true, "true"].include?(params[:enabled])

    Rails.logger.info "=== TOGGLE MASTER WEB SEARCH ==="
    Rails.logger.info "Report ID: #{@report.id}"
    Rails.logger.info "Enabled param: #{params[:enabled]} (#{params[:enabled].class})"
    Rails.logger.info "Converted to: #{enabled}"
    Rails.logger.info "Before: #{@report.web_search_enabled}"

    @report.web_search_enabled = enabled

    if @report.save
      Rails.logger.info "After: #{@report.web_search_enabled}"

      # If disabling, also disable all section-level toggles
      @report.ai_report_sections.update_all(web_search_enabled: false) unless enabled

      render json: {
        success: true,
        enabled: @report.web_search_enabled,
        message: enabled ? 'Web search enabled' : 'Web search disabled'
      }
    else
      render json: { success: false, error: 'Failed to update' }, status: :unprocessable_entity
    end
  end

  private

  def set_report
    @report = AiPortfolioReport.find(params[:id])
  end

  def report_params
    params.require(:ai_portfolio_report).permit(:portfolio_company_id, :report_date)
  end

  def generate_collated_content
    company_name = @report.portfolio_company&.name || "Portfolio Company"
    content = ""

    # Cover page
    content += <<-HTML
    <div style="text-align: center; padding: 3rem; margin-bottom: 2rem;">
      <h1 style="color: #1e40af; font-size: 2.5rem; margin-bottom: 1rem;">#{company_name}</h1>
      <h2 style="color: #3b82f6; font-size: 1.8rem; margin-bottom: 1rem;">Portfolio Company Report</h2>
      <p style="color: #6b7280; font-size: 1.1rem;">Generated on: #{@report.report_date&.strftime('%B %d, %Y') || Date.today.strftime('%B %d, %Y')}</p>
      <p style="color: #6b7280; font-size: 1.1rem;">Analyst: #{@report.analyst&.name || current_user.name}</p>
    </div>
    <hr style="border: 2px solid #3b82f6; margin-bottom: 3rem;">
    HTML

    # Add only REVIEWED sections (sections where analyst clicked "Save Section")
    reviewed_sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)

    Rails.logger.info "=== Generating Collated Report ==="
    Rails.logger.info "Total sections: #{@report.ai_report_sections.count}"
    Rails.logger.info "Reviewed sections: #{reviewed_sections.count}"

    reviewed_sections.each do |section|
      # Use the appropriate content based on timestamp comparison
      section_content = section.current_content

      content += <<-HTML
      <div id="section-#{section.id}" style="margin-top: 2rem; margin-bottom: 2rem;">
        <!--<h2 style="color: #2563eb; border-bottom: 2px solid #60a5fa; padding-bottom: 0.5rem; margin-bottom: 1rem;">
          #{section.section_type}
        </h2>-->
        #{section_content}
      </div>
      HTML
    end

    content
  end
end
