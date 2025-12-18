# app/packs/ai/ai_portfolio_reports/services/section_content_generator.rb
class SectionContentGenerator
  def initialize(report:, section:)
    @report = report
    @section = section
    @portfolio_company = report.portfolio_company
  end

  # Main method: Generate section content HTML
  def generate_content_html(user_prompt: nil)
    # Find relevant documents
    document_paths = find_documents
    document_context = load_documents_content(document_paths)

    Rails.logger.info "=== Generating Section: #{@section.section_type} ==="
    Rails.logger.info "Documents found: #{document_paths.count}"
    Rails.logger.info "User prompt: #{user_prompt}" if user_prompt.present?

    # Build prompt for AI
    prompt = build_section_prompt(document_context, user_prompt)

    # Call AI to generate content
    content = call_ai_for_content(prompt)

    # Convert markdown to HTML
    html_content = convert_to_html(content)

    Rails.logger.info "Generated content length: #{html_content.length}"

    html_content
  end

  private

  def find_documents
    document_paths = []
    docs_path = Pathname.new('/tmp/test_documents')

    if docs_path.exist?
      supported_extensions = ['.csv', '.txt', '.md', '.pdf', '.docx']

      supported_extensions.each do |ext|
        Dir.glob(docs_path.join("*#{ext}")).each do |file_path|
          document_paths << file_path
        end
      end
    end

    document_paths
  end

  def load_documents_content(document_paths)
    context = ""

    document_paths.each do |path|
      content = File.read(path)
      context += "\n\n=== #{File.basename(path)} ===\n#{content[0..5000]}\n" # Limit to 5000 chars per doc
    rescue StandardError => e
      Rails.logger.warn "Failed to read #{path}: #{e.message}"
    end

    context
  end

  def build_section_prompt(document_context, user_prompt)
    company_name = @portfolio_company&.name || "Portfolio Company"
    section_type = @section.section_type

    # Section-specific instructions
    section_guidance = SECTION_GUIDANCE[section_type] || "Provide detailed analysis for this section."

    base_prompt = <<~PROMPT
      You are a professional investment analyst creating a portfolio company report.

      Company: #{company_name}
      Section: #{section_type}

      Task: #{section_guidance}

      Available Documents:
      #{document_context.presence || 'No documents available. Provide general framework.'}

      Requirements:
      - Return content as properly formatted HTML (use <h3>, <p>, <strong>, <ul>, <li> tags)
      - Do NOT use markdown. Return HTML directly.
      - Be thorough but concise
      - Structure content with clear headings and bullet points where appropriate
      - If documents are provided, extract specific data and metrics
      - If no documents, provide professional framework and key considerations
    PROMPT

    base_prompt += "\n\nUser Request: #{user_prompt}\n" if user_prompt.present?

    base_prompt
  end

  def call_ai_for_content(prompt)
    # Use RubyLLM (same as ChartAgentService)
    chat = RubyLLM.chat(model: 'gpt-4o-mini') # Fast model

    response = chat.ask(prompt)

    # Extract text from response
    case response
    when String
      response
    when RubyLLM::Message
      response.content.is_a?(RubyLLM::Content) ? response.content.text : response.content
    else
      response.to_s
    end
  end

  def convert_to_html(content)
    # Remove markdown code blocks if present
    content = content.gsub(/```html\n?/, '').gsub(/```\n?/, '')

    # If content is already HTML, return as-is
    return content if content.include?('<h3>') || content.include?('<p>')

    # Otherwise convert markdown to HTML
    require 'redcarpet'
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(content)
  rescue StandardError
    # Fallback: simple paragraph wrapping
    "<p>#{content}</p>"
  end

  # Section-specific guidance
  SECTION_GUIDANCE = {
    "Company Overview" => "Provide a comprehensive overview including business model, value proposition, and key differentiators.",
    "Key Products & Services" => "Detail the main products/services, features, target customers, and competitive advantages.",
    "Financial Snapshot" => "Summarize key financial metrics, revenue trends, profitability, and growth indicators.",
    "Market Size & Target" => "Analyze total addressable market, target segments, and market opportunity.",
    "Recent Updates & Developments" => "Highlight recent news, product launches, partnerships, or significant milestones.",
    "Founders & Shareholders" => "Provide background on founders, key shareholders, and ownership structure.",
    "SWOT Analysis - Blitz" => "Conduct a SWOT analysis covering Strengths, Weaknesses, Opportunities, and Threats.",
    "Competition Analysis" => "Analyze key competitors, market positioning, and competitive dynamics.",
    "Key Risks" => "Identify and assess major risks including market, operational, financial, and regulatory.",
    "Operational Red Flags" => "Highlight operational concerns or warning signs that merit attention.",
    "Negative News" => "Summarize any negative press, controversies, or concerns about the company.",
    "AML/KYB Check" => "Provide AML/KYB compliance status and relevant regulatory findings.",
    "Investment Ask" => "Detail the investment opportunity, terms, and expected returns."
  }.freeze
end

# Add this new method after generate_content_html
def refine_content_html(current_content:, user_prompt:)
  # Find relevant documents
  document_paths = find_documents
  document_context = load_documents_content(document_paths)

  Rails.logger.info "=== Refining Section: #{@section.section_type} ==="
  Rails.logger.info "Current content length: #{current_content.length}"
  Rails.logger.info "User prompt: #{user_prompt}"

  # Build refinement prompt
  prompt = build_refinement_prompt(current_content, user_prompt, document_context)

  # Call AI to refine content
  refined_content = call_ai_for_content(prompt)

  # Convert to HTML
  html_content = convert_to_html(refined_content)

  Rails.logger.info "Refined content length: #{html_content.length}"

  html_content
end

# Add this new method
def build_refinement_prompt(current_content, user_prompt, document_context)
  company_name = @portfolio_company&.name || "Portfolio Company"
  section_type = @section.section_type

  <<~PROMPT
    You are a professional investment analyst refining a portfolio company report section.

    Company: #{company_name}
    Section: #{section_type}

    Current Content (HTML):
    #{current_content}

    User Request: #{user_prompt}

    #{"Available Documents for Reference:\n#{document_context}\n" if document_context.present?}

    Task: Refine the current content according to the user's request while:
    - Maintaining professional quality and HTML formatting
    - Preserving important information unless asked to remove it
    - Adding new information if requested
    - Making it more concise/detailed as requested
    - Using data from documents if relevant

    Requirements:
    - Return content as properly formatted HTML (use <h3>, <p>, <strong>, <ul>, <li> tags)
    - Do NOT use markdown. Return HTML directly without code blocks.
    - Maintain the structure and style of the original content
    - Apply the specific changes requested by the user
  PROMPT
end
