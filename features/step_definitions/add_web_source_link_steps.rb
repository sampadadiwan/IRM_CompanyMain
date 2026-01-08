Given('the report has a section {string} with document content') do |section_type|
  @section = FactoryBot.create(:ai_report_section,
    ai_portfolio_report: @report,
    section_type: section_type,
    content_html: '<h2>Market Size & Target</h2><p>TAM: $50B, SAM: $10B, SOM: $1B based on documents.</p>',
    order_index: 1
  )
end

When('I enable web search for the section') do
  # Mock web search to avoid real API calls
  allow(AgentTools::WebSearchTool).to receive(:search).and_return({
    abstract_text: 'AURAA market is growing rapidly',
    sources: [{ title: 'Market Report', url: 'https://example.com/market' }]
  })

  # Mock LLM response
  mock_chat = double('chat')
  allow(RubyLLM).to receive(:chat).and_return(mock_chat)
  allow(mock_chat).to receive(:ask).and_return(
    double(content: '<p>Recent market analysis shows growth.</p><p><strong>Sources:</strong></p><ul><li><a href="https://example.com">Source</a></li></ul>')
  )

  # Find or create support agent
  agent = SupportAgent.find_or_create_by!(
    agent_type: 'PortfolioReportAgent',
    entity_id: @report.analyst.entity_id
  ) do |a|
    a.name = 'Portfolio Report Generator'
    a.enabled = true
  end

  # Call the agent with web search enabled
  PortfolioReportAgent.call(
    support_agent_id: agent.id,
    target: @section,
    action: 'generate',
    web_search_enabled: true
  )

  @section.reload
end

Then('the section should preserve the original document content') do
  expect(@section.content_html_with_web).to include('TAM: $50B')
end

Then('the section should contain {string}') do |text|
  expect(@section.content_html_with_web).to include(text)
end

Then('the section content should be saved to content_html_with_web') do
  expect(@section.content_html_with_web).to be_present
  expect(@section.content_html_with_web.length).to be > @section.content_html.length
end

Then('the section should contain clickable source links') do
  expect(@section.content_html_with_web).to match(/<a\s+href=/)
end

Then('each source link should have a valid URL') do
  doc = Nokogiri::HTML(@section.content_html_with_web)
  links = doc.css('a[href]')
  
  expect(links).not_to be_empty
  links.each do |link|
    url = link['href']
    expect(url).to match(/\Ahttps?:\/\//)
  end
end
