class AiReportSectionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:regenerate] # Skip CSRF for AJAX
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def update
    @report = AiPortfolioReport.find(params[:ai_portfolio_report_id])
    @section = @report.ai_report_sections.find(params[:id])

    # Handle content from contenteditable
    if params[:ai_report_section][:content].present?
      # Save to the appropriate column based on which version is currently displayed
      if @section.show_web_search_version?
        @section.content_html_with_web = params[:ai_report_section][:content]
        @section.updated_at_web_included = Time.current
      else
        @section.content_html = params[:ai_report_section][:content]
        @section.updated_at_document_only = Time.current
      end
    end

    @section.reviewed = true

    if @section.save
      redirect_to ai_portfolio_report_path(@report, section_id: @section.id), flash: { ai_notice: 'Section saved and marked as reviewed.' }
    else
      redirect_to ai_portfolio_report_path(@report, section_id: @section.id), alert: 'Failed to save section.'
    end
  end

  def toggle_web_search
    @report = AiPortfolioReport.find(params[:ai_portfolio_report_id])
    @section = @report.ai_report_sections.find(params[:id])

    # Get the desired state from params (if provided) or toggle
    desired_state = if params[:enable_web_search].present?
                      [true, 'true'].include?(params[:enable_web_search])
                    else
                      !@section.web_search_enabled
                    end

    # Only update flag if state is changing
    if @section.web_search_enabled != desired_state
      @section.web_search_enabled = desired_state

      # Only update timestamps when switching to a version that has content
      # This prevents the checkbox from appearing checked when no web content exists
      if @section.web_search_enabled && @section.content_html_with_web.present?
        @section.updated_at_web_included = Time.current
      elsif !@section.web_search_enabled && @section.content_html.present?
        @section.updated_at_document_only = Time.current
      end

      @section.save!
    end

    # Get content from cache or DB based on desired state
    session_id = session.id.to_s

    content_to_return = if desired_state
                          SectionContentCache.get_web_content(@section.id, session_id) ||
                            @section.content_html_with_web
                        else
                          SectionContentCache.get_document_content(@section.id, session_id) ||
                            @section.content_html
                        end

    render json: {
      success: true,
      web_search_enabled: @section.web_search_enabled,
      content: content_to_return,
      has_web_content: @section.content_html_with_web.present?,
      message: @section.web_search_enabled ? 'Web search enabled' : 'Web search disabled'
    }
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  def add_content
    @report = AiPortfolioReport.find(params[:ai_portfolio_report_id])
    @section = @report.ai_report_sections.find(params[:id])
    content_to_add = params[:content]

    # Add attribution with HTML formatting
    attributed_content = "#{content_to_add}<p><em>-- Added from AI at #{Time.current.strftime('%H:%M')} --</em></p>"

    # Append to section content (preserve HTML)
    current_content = @section.content_html || ""
    @section.content_html = current_content + attributed_content

    @section.save!

    render json: { success: true, content: @section.content_html }
  end

  # Add this to ai_report_sections_controller.rb

def toggle_reviewed
  @report = AiPortfolioReport.find(params[:ai_portfolio_report_id])
  @section = @report.ai_report_sections.find(params[:id])
  
  @section.reviewed = !@section.reviewed
  @section.save!
  
  render json: {
    success: true,
    reviewed: @section.reviewed,
    message: @section.reviewed ? 'Section included in report' : 'Section excluded from report'
  }
rescue StandardError => e
  render json: { success: false, error: e.message }, status: :unprocessable_entity
end


  # rubocop:disable Metrics/MethodLength
  def regenerate
    @report = AiPortfolioReport.find(params[:ai_portfolio_report_id])
    @section = @report.ai_report_sections.find(params[:id])

    user_prompt = params[:prompt]
    current_content = params[:current_content]
    section_type = params[:section_type]
    web_search_enabled = [true, 'true'].include?(params[:web_search_enabled])

    Rails.logger.info "=== Regenerate Request ==="
    Rails.logger.info "Section: #{section_type}"
    Rails.logger.info "Web search: #{web_search_enabled}"

    begin
      if section_type == "Custom Charts"
        # Charts logic (unchanged)
        generator = ChartSectionGenerator.new(report: @report, section: @section)

        if user_prompt.present?
          new_chart_html = generator.add_chart_from_prompt(user_prompt: user_prompt)
          refined_content = current_content + new_chart_html
        else
          @section.update(agent_chart_ids: [])
          refined_content = generator.generate_charts_html
        end

        @section.update(content_html: refined_content)

      else
        # Text sections
        agent = SupportAgent.find_or_create_by!(
          agent_type: 'PortfolioReportAgent',
          entity_id: @report.analyst.entity_id
        ) do |a|
          a.name = 'Portfolio Report Generator'
          a.enabled = true
        end

        action = user_prompt.present? ? 'refine' : 'generate'

        result = PortfolioReportAgent.call(
          support_agent_id: agent.id,
          target: @section,
          action: action,
          document_folder_path: "/tmp/test_documents",
          current_content: current_content,
          user_prompt: user_prompt,
          web_search_enabled: web_search_enabled
        )

        if result.success?
          refined_content = result[:generated_content]
          # NOTE: Saving is handled by PortfolioReportAgent.save_section step
          # Reload section to get updated timestamps
          @section.reload

          # Cache the content for quick toggling within session
          session_id = session.id.to_s
          if web_search_enabled
            SectionContentCache.store(@section.id, session_id, web_content: refined_content)
          else
            SectionContentCache.store(@section.id, session_id, document_content: refined_content)
          end

          Rails.logger.info "? Generated #{section_type} (web_search: #{web_search_enabled})"
        else
          Rails.logger.error "? Failed #{section_type}"
          render json: { success: false, error: "Generation failed" }, status: :unprocessable_entity
          return
        end
      end

      render json: {
        success: true,
        content: refined_content
      }
    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
  # rubocop:enable Metrics/MethodLength
end
