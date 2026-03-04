require 'open3'

# Controller for AI portfolio report lifecycle and exports.
class AiPortfolioReportsController < ApplicationController
  before_action :set_report, only: %i[show edit update destroy collated_report save_collated_report export_pdf export_docx toggle_master_web_search]

  # List portfolio reports.
  #
  # @return [void]
  def index
    @reports = policy_scope(AiPortfolioReport).order(created_at: :desc)
  end

  # Render the new report form.
  #
  # @return [void]
  def new
    @report = AiPortfolioReport.new
    authorize @report

    # Load user's templates for selection
    @templates = current_user.entity.investment_criteria_templates.order(usage_count: :desc)
  end

  # Create a new portfolio report and enqueue generation.
  #
  # @return [void]
  def create
    @report = AiPortfolioReport.new(report_params)
    @report.analyst_id = current_user.id
    authorize @report

    # Handle template creation if "create new" was selected
    if params[:template_action] == 'create_new' && params[:new_template].present?
      template = create_template_from_params(params[:new_template])
      @report.investment_criteria_template = template
    elsif params[:template_action] == 'use_existing' && params[:investment_criteria_template_id].present?
      @report.investment_criteria_template_id = params[:investment_criteria_template_id]
    end

    # If 'skip' or no action, template remains nil

    # Link report to the Company Evaluation Agent folder
    if @report.portfolio_company_id.present?
      pc = Investor.find(@report.portfolio_company_id)
      eval_folder = find_or_create_evaluation_folder(pc)
      @report.folder_id = eval_folder.id
      Rails.logger.debug { "=== REPORT FOLDER SET: folder_id=#{eval_folder.id}, name=#{eval_folder.name}, docs=#{eval_folder.documents.count} ===" }
    end

    if @report.save
      GenerateSectionContentJob.perform_later(@report.id)
      redirect_to @report, flash: { ai_notice: 'Report created! AI is generating content for all sections (this may take a minute)...' }
    else
      @templates = current_user.entity.investment_criteria_templates.order(usage_count: :desc)
      render :new, status: :unprocessable_entity
    end
  end

  # Show a portfolio report and current section.
  #
  # @return [void]
  def show
    authorize @report
    @current_section = @report.ai_report_sections.find_by(id: params[:section_id]) ||
                       @report.ai_report_sections.order(:order_index).first

    @portfolio_chat_agent = SupportAgent.find_by(agent_type: 'PortfolioReportAgent', entity_id: current_user.entity_id)

    # Checkbox should only be checked if web search content actually exists and is being displayed
    # This ensures the checkbox accurately reflects what the user is seeing
    @show_web_search_version = @current_section.show_web_search_version? &&
                               @current_section.web_search_content_exists?
  end

  # Redirect to show page (editing happens in show).
  #
  # @return [void]
  def edit
    authorize @report
    # Redirect to show page - the show page IS the editing interface
    redirect_to @report
  end

  # Show collated report content.
  #
  # @return [void]
  def collated_report
    authorize @report

    # ALWAYS regenerate fresh with only reviewed sections
    @collated_content = generate_collated_content
    @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)
  end

  # Save collated report content.
  #
  # @return [void]
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

  # Export report content to PDF.
  #
  # @return [void]
  def export_pdf
    authorize @report

    company_name = @report.portfolio_company&.name&.parameterize || "portfolio-company"

    # Use collated report content if available, otherwise use section contents
    if @report.collated_report_html.present?
      @collated_content = @report.collated_report_html
    else
      @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)
    end

    render pdf: "#{company_name}-report-#{Time.zone.today}",
           template: 'ai_portfolio_reports/export_pdf',
           layout: false,
           page_size: 'A4',
           margin: { top: 20, bottom: 20, left: 20, right: 20 },
           encoding: 'UTF-8',
           print_media_type: true,
           disposition: 'attachment'
  end

  # def export_docx
  #   authorize @report

  #   require 'htmltoword'

  #   @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)
  #   company_name = @report.portfolio_company&.name&.parameterize || "portfolio-company"

  #   # Render the Word template to get properly formatted HTML
  #   html_content = render_to_string(
  #     template: 'ai_portfolio_reports/export_docx',
  #     layout: false
  #   )

  #   # Convert HTML to DOCX
  #   file = Htmltoword::Document.create(html_content)

  #   # Send file
  #   send_data file,
  #             filename: "#{company_name}-report-#{Time.zone.today}.docx",
  #             type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  #             disposition: 'attachment'
  # end

  # Export report content to DOCX using Pandoc.
  #
  # @return [void]
  def export_docx
    authorize @report

    company_name = @report.portfolio_company&.name&.parameterize || "portfolio-company"

    # Use collated report content if available, otherwise use section contents

    Rails.logger.info "=== Exporting DOCX ==="
    Rails.logger.info "Report ID: #{@report.id}"
    Rails.logger.info "Collated report present: #{@report.collated_report_html.present?}"

    @sections = @report.ai_report_sections.where(reviewed: true).order(:order_index)

    @collated_content = @report.collated_report_html if @report.collated_report_html.present?

    # Render the Word template to get properly formatted HTML
    html_content = render_to_string(
      template: 'ai_portfolio_reports/export_docx',
      layout: false
    )

    # Convert HTML to DOCX using Pandoc
    temp_html = Tempfile.new(['report', '.html'])
    temp_docx = Tempfile.new(['report', '.docx'])

    begin
      temp_html.write(html_content)
      temp_html.close

      stdout, stderr, status = Open3.capture3('pandoc', temp_html.path, '-o', temp_docx.path)
      Rails.logger.info "Pandoc stdout: #{stdout}" if stdout.present?
      Rails.logger.error "Pandoc stderr: #{stderr}" if stderr.present?

      if !status.success? || !File.exist?(temp_docx.path) || File.empty?(temp_docx.path)
        Rails.logger.error "Pandoc failed: status=#{status.exitstatus}, output_size=#{File.exist?(temp_docx.path) ? File.size(temp_docx.path) : 'missing'}"
        render json: { error: 'DOCX export failed. Please try again later.' }, status: :unprocessable_entity
        return
      end

      send_file temp_docx.path,
                filename: "#{company_name}-report-#{Time.zone.today}.docx",
                type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                disposition: 'attachment'
    ensure
      temp_html.unlink
      # NOTE: temp_docx will be cleaned up after send_file completes
    end
  end

  # Create a report from a document folder.
  #
  # @return [void]
  def create_from_folder
    folder = Folder.find(params[:folder_id])
    authorize folder, :show? # ← Pundit checks if user can access this folder

    portfolio_company = folder.owner

    @report = AiPortfolioReport.new(
      portfolio_company: portfolio_company,
      folder_id: folder.id,
      report_date: Time.zone.today,
      analyst_id: current_user.id
    )
    authorize @report, :create?

    if @report.save
      GenerateSectionContentJob.perform_later(@report.id)
      redirect_to @report, flash: { ai_notice: 'Report created! AI is generating content for all sections (this may take a minute)...' }
    else
      redirect_back_or_to(folder_documents_path(folder_id: folder.id), alert: @report.errors.full_messages.join(', '))
    end
  end

  # Delete a report.
  #
  # @return [void]
  def destroy
    authorize @report
    @report.destroy
    redirect_to ai_portfolio_reports_path, notice: 'Report deleted.'
  end

  # Toggle report-level web search setting.
  #
  # @return [void]
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
      # rubocop:disable Rails/SkipsModelValidations
      @report.ai_report_sections.update_all(web_search_enabled: false) unless enabled
      # rubocop:enable Rails/SkipsModelValidations

      render json: {
        success: true,
        enabled: @report.web_search_enabled,
        message: enabled ? 'Web search enabled' : 'Web search disabled'
      }
    else
      render json: { success: false, error: 'Failed to update' }, status: :unprocessable_entity
    end
  end

  # GET /ai_portfolio_reports/evaluation_folder_documents
  # Returns JSON list of documents in the Company Evaluation Agent folder for a given portfolio company.
  # Creates the folder if it doesn't exist. Called via AJAX from the documents modal.
  #
  # @param portfolio_company_id [Integer] the investor ID
  # @return [JSON] { folder_id, entity_id, documents: [{ id, name, file_url, created_at }] }
  def evaluation_folder_documents
    portfolio_company = Investor.find(params[:portfolio_company_id])
    authorize AiPortfolioReport.new, :new?

    folder = find_or_create_evaluation_folder(portfolio_company)
    render json: { folder_id: folder.id, entity_id: portfolio_company.entity_id, documents: serialize_documents(folder) }
  end

  # POST /ai_portfolio_reports/upload_evaluation_documents
  # Creates multiple documents in the Company Evaluation Agent folder from Uppy-uploaded file data.
  # Called via AJAX from the documents modal after files are uploaded to cache.
  #
  # @param portfolio_company_id [Integer] the investor ID
  # @param documents [Array<Hash>] array of { name, file } where file is Shrine cached file JSON
  # @return [JSON] { folder_id, documents: [{ id, name, file_url, created_at }] }
  def upload_evaluation_documents
    portfolio_company = Investor.find(params[:portfolio_company_id])
    authorize AiPortfolioReport.new, :create?

    folder = find_or_create_evaluation_folder(portfolio_company)

    ActiveRecord::Base.connected_to(role: :writing) do
      params[:documents].each do |doc_params|
        folder.documents.create!(
          name: doc_params[:name],
          file: doc_params[:file],
          entity_id: portfolio_company.entity_id,
          user_id: current_user.id
        )
      end
    end

    render json: { folder_id: folder.id, documents: serialize_documents(folder) }
  end

  private

  # Load report for actions.
  #
  # @return [void]
  def set_report
    @report = AiPortfolioReport.find(params[:id])
  end

  # Strong parameters for report.
  #
  # @return [ActionController::Parameters] permitted params
  def report_params
    params.require(:ai_portfolio_report).permit(:portfolio_company_id, :report_date, :investment_criteria_template_id)
  end

  # Find or create the Company Evaluation Agent folder for a portfolio company.
  #
  # @param portfolio_company [Investor] the portfolio company investor
  # @return [Folder] the evaluation folder
  def find_or_create_evaluation_folder(portfolio_company)
    ActiveRecord::Base.connected_to(role: :writing) do
      unless portfolio_company.document_folder
        portfolio_company.setup_document_folder
        portfolio_company.reload
      end

      portfolio_company.document_folder.children.find_or_create_by(
        name: 'Company Evaluation Agent',
        entity_id: portfolio_company.entity_id
      )
    end
  end

  # Serialize a folder's documents to JSON-ready hashes.
  #
  # @param folder [Folder] the folder containing documents
  # @return [Array<Hash>] serialized documents
  def serialize_documents(folder)
    folder.documents.order(created_at: :desc).map do |doc|
      { id: doc.id, name: doc.name, file_url: doc.file_url, created_at: doc.created_at.strftime('%b %d, %Y') }
    end
  end

  def create_template_from_params(template_params)
    service = InvestmentCriteriaTemplateService.new(current_user)
    criteria = template_params[:criteria]&.values&.reject { |c| c[:name].blank? } || []

    service.create(
      name: template_params[:name],
      criteria: criteria
    )
  end

  # Build collated report content from reviewed sections.
  #
  # @return [String] HTML content
  def generate_collated_content
    company_name = @report.portfolio_company&.name || "Portfolio Company"
    content = ""

    # Cover page
    content += <<-HTML
    <div style="text-align: center; padding: 3rem; margin-bottom: 2rem;">
      <h1 style="color: #1e40af; font-size: 2.5rem; margin-bottom: 1rem;">#{company_name}</h1>
      <h2 style="color: #3b82f6; font-size: 1.8rem; margin-bottom: 1rem;">Portfolio Company Report</h2>
      <p style="color: #6b7280; font-size: 1.1rem;">Generated on: #{@report.report_date&.strftime('%B %d, %Y') || Time.zone.today.strftime('%B %d, %Y')}</p>
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
