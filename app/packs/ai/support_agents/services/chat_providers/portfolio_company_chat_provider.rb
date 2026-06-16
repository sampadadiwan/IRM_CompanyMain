# frozen_string_literal: true

# Provides portfolio-company-specific context for the chat assistant.
# Pulls the latest PortfolioCompanyAgent run results from SupportAgentReport
# json_fields (KPI issues, document issues, valuation issues) and feeds them
# as context to the LLM.
class PortfolioCompanyChatProvider < BaseChatProvider
  # @return [String] system prompt for the portfolio company chat assistant
  def system_prompt
    Rails.logger.info "[PortfolioCompanyChatProvider] system_prompt called for agent ##{support_agent.id}"

    <<~PROMPT
      You are a portfolio company compliance tracking assistant for #{support_agent.entity&.name || 'the organization'}.
      Agent: #{support_agent.name}
      User: #{analyst&.name || 'Unknown'}
      Date: #{Date.current.strftime('%d %b %Y')}

      CRITICAL SCOPE RESTRICTIONS:
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      You ONLY have access to Portfolio Company Agent compliance check results.
      You can ONLY answer questions about:
      1. Which companies are missing KPI submissions (from the report data)
      2. Which companies have document compliance issues (from the report data)
      3. Which companies are missing valuations (from the report data)
      4. The status of specific companies listed in the reports
      5. Summary statistics from the latest agent run

      You MUST NOT:
      - Explain general business concepts or valuation methods
      - Provide advice about how to obtain valuations
      - Discuss legal requirements for private companies
      - Answer questions about companies not in your report data
      - Give general knowledge about corporate filings or regulations
      - Explain why valuations might be missing in general business context

      If asked about "why" valuations are missing or general concepts:
      → Respond: "I can only tell you which companies in our portfolio are missing
         valuations based on the latest compliance check. I cannot provide general
         business advice. Would you like me to list the companies with missing valuations?"

      If asked about a company not in your data:
      → Respond: "I don't have compliance data for that company. I can only report
         on the companies analyzed in the latest Portfolio Company Agent run."
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      RESPONSE GUIDELINES:
      - Always cite specific company names from the report data
      - Reference the dates from the actual compliance checks
      - Use the severity levels from reports (blocking/success)
      - Provide actionable next steps based on the report data
      - Be concise and focus on facts from the reports

      #{strict_scope_prompt}

      #{chart_rendering_prompt}
    PROMPT
  end

  # @return [String] context built from SupportAgentReport json_fields
  def build_context
    reports = SupportAgentReport.where(support_agent: support_agent)
                                .where(owner_type: "Investor")
                                .order(updated_at: :desc)
                                .limit(50) # Limit to most recent 50 companies

    Rails.logger.info "[PortfolioCompanyChatProvider] Found #{reports.count} portfolio company reports for agent ##{support_agent.id}"

    if reports.empty?
      Rails.logger.warn "[PortfolioCompanyChatProvider] No reports found. Falling back to no-context message."
      return <<~CONTEXT
        No portfolio company reports available. The agent has not been run yet.

        Please run the Portfolio Company Agent first to generate compliance data.
      CONTEXT
    end

    # Separate completed and failed reports
    completed_reports = reports.select { |r| r.status == "completed" }
    failed_reports = reports.select { |r| r.status == "failed" }

    sections = []

    # Data scope declaration
    sections << build_data_scope_declaration

    # Summary section
    sections << build_summary_section(reports, completed_reports, failed_reports)

    # Failed companies (blocking issues)
    sections << build_failed_companies_section(failed_reports) if failed_reports.any?

    # Completed companies (informational)
    if completed_reports.any?
      sections << build_completed_companies_section(completed_reports.first(10)) # Show top 10
    end

    # Example questions
    sections << build_example_questions_section

    context = sections.join("\n\n")

    Rails.logger.info "[PortfolioCompanyChatProvider] Context length: #{context.length} chars"
    context
  end

  # @return [Array] no tools for now
  def tools
    []
  end

  private

  def build_data_scope_declaration
    <<~SCOPE
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      DATA SCOPE: Portfolio Company Compliance Reports
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      This context contains ONLY the results from the Portfolio Company Agent's
      latest compliance checks. You can ONLY answer questions about:
      - KPI submission status for listed companies
      - Document compliance issues for listed companies
      - Valuation reporting status for listed companies
      - Summary statistics across the portfolio

      DO NOT answer questions about:
      - Companies not listed below
      - General business or legal concepts
      - How to fix compliance issues (only report what the data shows)
    SCOPE
  end

  def build_summary_section(reports, completed_reports, failed_reports)
    <<~SUMMARY
      # Portfolio Company Compliance Summary

      **Total Companies Analyzed:** #{reports.count}
      **Companies with All Compliance Met:** #{completed_reports.count}
      **Companies with Compliance Issues:** #{failed_reports.count}
      **Latest Run:** #{reports.first&.updated_at&.strftime('%d %b %Y %H:%M') || 'Unknown'}

      ---
    SUMMARY
  end

  def build_failed_companies_section(failed_reports)
    lines = ["# Companies with Compliance Issues", ""]

    failed_reports.each do |report|
      company = report.owner
      json_data = report.json_fields || {}

      lines << "## #{company.name}"
      lines << "**Status:** Failed Compliance"
      lines << "**Last Checked:** #{report.updated_at.strftime('%d %b %Y %H:%M')}"
      lines << ""

      # KPI Issues
      kpi_issues = json_data["kpi_issues"] || []
      if kpi_issues.any?
        lines << "### KPI Submission Issues:"
        kpi_issues.each do |issue|
          severity_icon = issue["severity"] == "blocking" ? "❌" : "ℹ️"
          lines << "#{severity_icon} #{issue['message']}"
        end
        lines << ""
      end

      # Document Issues
      doc_issues = json_data["document_issues"] || []
      if doc_issues.any?
        lines << "### Document Compliance Issues:"
        doc_issues.each do |issue|
          severity_icon = issue["severity"] == "blocking" ? "❌" : "ℹ️"
          lines << "#{severity_icon} #{issue['message']}"
        end
        lines << ""
      end

      # Valuation Issues
      val_issues = json_data["valuation_issues"] || []
      if val_issues.any?
        lines << "### Valuation Reporting Issues:"
        val_issues.each do |issue|
          severity_icon = issue["severity"] == "blocking" ? "❌" : "ℹ️"
          lines << "#{severity_icon} #{issue['message']}"
        end
        lines << ""
      end

      lines << "---"
      lines << ""
    end

    lines.join("\n")
  end

  def build_completed_companies_section(completed_reports)
    lines = ["# Companies Meeting All Compliance Requirements", ""]

    completed_reports.each do |report|
      company = report.owner
      json_data = report.json_fields || {}

      lines << "## #{company.name}"
      lines << "✅ **All compliance requirements met**"
      lines << "**Last Checked:** #{report.updated_at.strftime('%d %b %Y %H:%M')}"
      lines << ""

      # Show success messages if available
      kpi_issues = json_data["kpi_issues"] || []
      kpi_success = kpi_issues.find { |i| i["severity"] == "success" }
      lines << "- #{kpi_success['message']}" if kpi_success

      val_issues = json_data["valuation_issues"] || []
      val_success = val_issues.find { |i| i["severity"] == "success" }
      lines << "- #{val_success['message']}" if val_success

      lines << ""
      lines << "---"
      lines << ""
    end

    lines.join("\n")
  end

  def build_example_questions_section
    <<~EXAMPLES
      # Example Questions You Can Ask

      - "Which companies are missing KPI submissions?"
      - "Show me companies with document compliance issues"
      - "What's the overall compliance rate?"
      - "Which companies are missing valuations?"
      - "Tell me about [Company Name]'s compliance status"
      - "How many companies have blocking issues?"
      - "List all companies that passed compliance"
    EXAMPLES
  end
end
