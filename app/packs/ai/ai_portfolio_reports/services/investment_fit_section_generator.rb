class InvestmentFitSectionGenerator
  def initialize(report:, section:, template:, pitch_deck_content:)
    @report = report
    @section = section
    @template = template
    @pitch_deck_content = pitch_deck_content
    @portfolio_company = report.portfolio_company
  end

  def h(text)
    ERB::Util.html_escape(text.to_s)
  end

  def generate
    # 1. Snapshot the criteria
    criteria_snapshot = @template.criteria.deep_dup

    # 2. Build prompt and call LLM
    prompt = build_prompt(criteria_snapshot)
    llm_response = call_llm(prompt)

    # 3. Parse response and build HTML
    parsed = parse_llm_response(llm_response)
    # 4. Optionally save evaluation record for tracking
    save_evaluation_record(criteria_snapshot, parsed)

    # 5. Build and return HTML content
    html_content = build_html_content(parsed, criteria_snapshot)
    Rails.logger.info "[InvestmentFitSectionGenerator] === FINAL HTML OUTPUT ==="
    Rails.logger.info html_content
    html_content
  end

  private

  # rubocop:disable Metrics/MethodLength
  def build_prompt(criteria)
    criteria_text = criteria.map do |c|
      "- **#{c['name']}:** #{c['value']}"
    end.join("\n")

    <<~PROMPT
      You are an investment analyst evaluating a company for potential investment at an internal IC/partner discussion.

      ## Investment Criteria
      #{criteria_text}

      ## Company Pitch Deck / Document Content
      #{@pitch_deck_content}

      ## Instructions

      Evaluate this company against ONLY the #{criteria.count} criterion/criteria listed above.#{' '}
      Do NOT add, infer, or evaluate any other criteria beyond what is explicitly provided.


      For each criterion, assess:
      - Does it Fit? (Yes / Partial / No)
      - Fit Rating: Strong (meets or exceeds), Medium (partially meets), or Low (does not meet)
      - Brief Reasoning (1-2 lines, evidence-based with specific data points where available)

      Then provide a summary recommendation.

      ## Guidelines
      - Be factual and evidence-driven; cite specific numbers/metrics from the pitch deck
      - Categorize criteria with "Strong" rating under Strong Points
      - Categorize criteria with "Low" rating under Weak Points
      - Categorize criteria with "Medium" rating under Areas of Moderate Fit
      - Write in a tone suitable for an internal IC or partner discussion
      - Be concise but decisive

      Return as JSON with this exact structure:
      {
        "strong_points": [
          {
            "criterion": "...",
            "requirement": "...",
            "does_it_fit": "Yes",
            "reasoning": "..."
          }
        ],
        "moderate_fit": [
          {
            "criterion": "...",
            "requirement": "...",
            "does_it_fit": "Partial",
            "reasoning": "..."
          }
        ],
        "weak_points": [
          {
            "criterion": "...",
            "requirement": "...",
            "does_it_fit": "No|Partial",
            "reasoning": "..."
          }
        ],
        "recommendation": "Proceed to deeper evaluation|Do not proceed",
        "recommendation_rationale": "..."
      }
    PROMPT
  end

  # rubocop:enable Metrics/MethodLength

  def call_llm(prompt)
    chat = LlmService.ruby_llm_chat(entity: @portfolio_company.entity) # Pass entity for potential API key access
    response = chat.ask(prompt)
    response.content.strip
  end

  def parse_llm_response(response)
    cleaned = response.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")

    Rails.logger.info "[InvestmentFitSectionGenerator] === CLEANED JSON ==="
    Rails.logger.info cleaned

    parsed = JSON.parse(cleaned)

    Rails.logger.info "[InvestmentFitSectionGenerator] === PARSED CLEAN JSON ==="
    Rails.logger.info parsed

    {
      strong_points: parsed['strong_points'] || [],
      moderate_fit: parsed['moderate_fit'] || [],
      weak_points: parsed['weak_points'] || [],
      recommendation: parsed['recommendation'] || '',
      recommendation_rationale: parsed['recommendation_rationale'] || ''
    }
  rescue JSON::ParserError => e
    Rails.logger.error "[InvestmentFitSectionGenerator] JSON parse error: #{e.message}"
    { strong_points: [], moderate_fit: [], weak_points: [], recommendation: '', recommendation_rationale: '', raw_response: response }
  end

  def save_evaluation_record(criteria_snapshot, parsed)
    AiInvestmentFitEvaluation.create!(
      portfolio_company: @portfolio_company,
      criteria_template: @template,
      criteria_snapshot: criteria_snapshot,
      criteria_evaluation: {
        strong_points: parsed[:strong_points],
        moderate_fit: parsed[:moderate_fit],
        weak_points: parsed[:weak_points]
      }.to_json,
      recommendation: parsed[:recommendation],
      key_positives: parsed[:strong_points].pluck('reasoning').to_json,
      key_watchouts: parsed[:weak_points].pluck('reasoning').to_json,
      conclusion: parsed[:recommendation_rationale]
    )
  rescue StandardError => e
    Rails.logger.warn "[InvestmentFitSectionGenerator] Could not save evaluation: #{e.message}"
  end

  def build_html_content(parsed, criteria_snapshot)
    <<~HTML
      <div class="investment-fit-section">
        <h2 style="color: #2563eb; border-bottom: 2px solid #60a5fa; padding-bottom: 0.5rem;">
          Investment Fit Evaluation
        </h2>

        <div class="template-info" style="background: #f0f7ff; padding: 1rem; border-radius: 6px; margin-bottom: 1.5rem;">
          <p style="margin: 0; color: #1e40af;">
            <strong>Evaluation Template:</strong> #{h(@template.name)}
          </p>
          <p style="margin: 0.5rem 0 0 0; color: #6b7280; font-size: 0.9rem;">
            #{criteria_snapshot.count} criteria evaluated
          </p>
        </div>

        #{build_section_table('Strong Points', parsed[:strong_points], '#166534', '#dcfce7')}
        #{build_section_table('Areas of Moderate Fit', parsed[:moderate_fit], '#ca8a04', '#fef9c3')}
        #{build_section_table('Weak Points / Gaps', parsed[:weak_points], '#991b1b', '#fee2e2')}
        #{build_recommendation_html(parsed)}
      </div>
    HTML
  end

  def build_section_table(title, criteria_list, title_color, header_bg)
    Rails.logger.info "[InvestmentFitSectionGenerator] build_section_table called with title: #{title}, criteria_list: #{criteria_list.inspect}"

    return "" if criteria_list.empty?

    rows = criteria_list.map do |eval|
      fit_color = case eval['does_it_fit']
                  when 'Yes' then '#166534'
                  when 'Partial' then '#ca8a04'
                  when 'No' then '#991b1b'
                  else '#374151'
                  end

      <<~ROW
        <tr>
          <td style="padding: 0.75rem; border: 1px solid #e5e7eb; font-weight: 600;">#{h(eval['criterion'])}</td>
          <td style="padding: 0.75rem; border: 1px solid #e5e7eb;">#{h(eval['requirement'])}</td>
          <td style="padding: 0.75rem; border: 1px solid #e5e7eb; text-align: center; color: #{fit_color}; font-weight: 600;">#{h(eval['does_it_fit'])}</td>
          <td style="padding: 0.75rem; border: 1px solid #e5e7eb; font-size: 0.9rem; color: #4b5563;">#{h(eval['reasoning'])}</td>
        </tr>
      ROW
    end.join("\n")

    html_content = <<~HTML
      <div class="criteria-section" style="margin-bottom: 1.5rem;">
        <h3 style="color: #{title_color}; margin-bottom: 0.75rem; padding: 0.5rem; background: #{header_bg}; border-radius: 4px;">
          #{title}
        </h3>
        <table style="width: 100%; border-collapse: collapse; font-size: 0.95rem;">
          <thead>
            <tr style="background: #f3f4f6;">
              <th style="padding: 0.75rem; border: 1px solid #e5e7eb; text-align: left; width: 18%;">Criteria</th>
              <th style="padding: 0.75rem; border: 1px solid #e5e7eb; text-align: left; width: 25%;">Requirement</th>
              <th style="padding: 0.75rem; border: 1px solid #e5e7eb; text-align: center; width: 12%;">Fit Status</th>
              <th style="padding: 0.75rem; border: 1px solid #e5e7eb; text-align: left; width: 45%;">Reasoning</th>
            </tr>
          </thead>
          <tbody>
            #{rows}
          </tbody>
        </table>
      </div>
    HTML

    Rails.logger.info "[InvestmentFitSectionGenerator] === FINAL HTML OUTPUT ==="
    Rails.logger.info html_content

    html_content
  end

  def build_recommendation_html(parsed)
    recommendation_color = parsed[:recommendation]&.include?('Proceed') ? '#166534' : '#991b1b'
    recommendation_bg = parsed[:recommendation]&.include?('Proceed') ? '#dcfce7' : '#fee2e2'

    <<~HTML
      <div class="recommendation-section" style="background: #fafafa; border: 1px solid #e5e7eb; border-radius: 8px; padding: 1.5rem; margin-top: 1.5rem;">
        <h3 style="color: #1f2937; margin-top: 0; margin-bottom: 1rem;">Investment Recommendation</h3>

        <div class="recommendation" style="background: #{recommendation_bg}; color: #{recommendation_color}; padding: 1rem; border-radius: 6px; margin-bottom: 1rem; font-weight: 600; font-size: 1.1rem;">
          #{h(parsed[:recommendation])}
        </div>

        <div class="rationale" style="color: #4b5563; line-height: 1.6;">
          <strong>Rationale:</strong> #{h(parsed[:recommendation_rationale])}
        </div>
      </div>
    HTML
  end
end
