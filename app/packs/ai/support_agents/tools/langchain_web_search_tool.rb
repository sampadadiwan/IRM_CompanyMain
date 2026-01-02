# Langchain-compatible wrapper for WebSearchTool
# Used by PortfolioChatAgent to enable web search during conversations
class LangchainWebSearchTool
  extend Langchain::ToolDefinition

  define_function :web_search, description: "Search the web for current information about companies, markets, news, or any topic. Use this when you need up-to-date information not available in the provided documents." do
    property :query, type: "string", description: "The search query - be specific and include company names, topics, or keywords", required: true
  end

  define_function :news_search, description: "Search for recent news articles about a company or topic. Use this for finding recent developments, announcements, or press coverage." do
    property :query, type: "string", description: "The news search query - include company name and relevant keywords", required: true
    property :time_period, type: "string", description: "Time filter: 'd' for day, 'w' for week, 'm' for month, 'm3' for 3 months, 'y' for year. Default is 'm3'.", required: false
  end

  def web_search(query:)
    Rails.logger.info "[LangchainWebSearchTool] web_search called with: #{query}"
    results = AgentTools::WebSearchTool.search(query)
    format_results(results)
  end

  def news_search(query:, time_period: "m3")
    Rails.logger.info "[LangchainWebSearchTool] news_search called with: #{query}, period: #{time_period}"
    results = AgentTools::WebSearchTool.news_search(query, time_period: time_period)
    format_results(results)
  end

  private

  def format_results(results)
    return "No results found or search error occurred." if results[:error] || results.empty?

    output = []
    output << "Summary: #{results[:abstract_text]}" if results[:abstract_text].present?

    if results[:related_topics].present?
      output << "\nRelated Information:"
      results[:related_topics].first(5).each { |topic| output << "- #{topic}" }
    end

    if results[:sources].present?
      output << "\nSources:"
      results[:sources].first(5).each { |src| output << "- #{src[:title]}: #{src[:url]}" }
    end

    output.join("\n")
  end
end
