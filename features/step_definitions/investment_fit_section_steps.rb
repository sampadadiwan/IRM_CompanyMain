# Step definitions for investment_fit_section.feature

Given('an investment criteria template {string} exists with criteria:') do |template_name, table|
  criteria = table.hashes.map { |row| { 'name' => row['name'], 'value' => row['value'] } }
  @template = InvestmentCriteriaTemplate.create!(
    name: template_name,
    criteria: criteria,
    created_by_user: @user
  )
end

When('I generate an investment fit section using template {string}') do |template_name|
  # Mock RubyLLM to avoid real API calls in tests
  mock_chat = double('chat')
  allow(RubyLLM).to receive(:chat).and_return(mock_chat)

  mock_llm_response = {
    'strong_points' => [
      {
        'criterion' => 'Revenue',
        'requirement' => 'Minimum $10M ARR',
        'does_it_fit' => 'Yes',
        'reasoning' => 'Company has $15M ARR based on pitch deck data.'
      }
    ],
    'moderate_fit' => [],
    'weak_points' => [
      {
        'criterion' => 'Growth Rate',
        'requirement' => 'At least 50% YoY',
        'does_it_fit' => 'Partial',
        'reasoning' => 'Current growth rate is 35% YoY, below target.'
      }
    ],
    'recommendation' => 'Proceed to deeper evaluation',
    'recommendation_rationale' => 'Strong revenue base with room for growth improvement.'
  }.to_json

  allow(mock_chat).to receive(:ask).and_return(double(content: mock_llm_response))

  template = InvestmentCriteriaTemplate.find_by!(name: template_name)
  section = @report.ai_report_sections.find_by(section_type: 'Investment Fit Evaluation')

  generator = InvestmentFitSectionGenerator.new(
    report: @report,
    section: section,
    template: template,
    pitch_deck_content: 'Sample pitch deck content for testing'
  )

  @generated_content = generator.generate
  section.update!(content_html: @generated_content)
end

Then('the section should contain an investment fit evaluation') do
  section = @report.ai_report_sections.find_by(section_type: 'Investment Fit Evaluation')
  expect(section.content_html).to include('investment-fit-section')
  expect(section.content_html).to include('Investment Fit Evaluation')
end

Then('the section should display the template name {string}') do |template_name|
  section = @report.ai_report_sections.find_by(section_type: 'Investment Fit Evaluation')
  expect(section.content_html).to include(template_name)
end
