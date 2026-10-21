# frozen_string_literal: true

# # RubyLLM tool that wraps AgentTools::WebSearchTool for use in chat agents.
# Supports general web search and news search via SerpAPI.
# Returns formatted results including summary, related topics, and source links.
#
# @see AgentTools::WebSearchTool
# @see PortfolioChatProvider

class WebSearchTool < RubyLLM::Tool
  description "Searches the web for current information about companies, markets, " \
              "news, and recent developments. Use for any question requiring " \
              "up-to-date or external information."

  parameter :query, type: :string, description: "The search query"
  parameter :search_type,
            type: :string,
            description: "'web' (default) for general search, 'news' for recent news articles",
            required: false

  def execute(query:, search_type: "web")
    require Rails.root.join("lib/agent_tools/web_search_tool")

    results = if search_type == "news"
                AgentTools::WebSearchTool.news_search(query)
              else
                AgentTools::WebSearchTool.search(query)
              end
    format_results(results)
  end

  private

  def format_results(results)
    return "No results found." if results.blank? || results[:error]

    parts = []
    parts << "Summary: #{results[:abstract]}" if results[:abstract].present?
    if results[:related_topics].present?
      parts << "Related:"
      results[:related_topics].each { |t| parts << "- #{t}" }
    end
    if results[:sources].present?
      parts << "Sources:"
      results[:sources].each do |s|
        if s.is_a?(Hash)
          label = [s[:title], s[:source]].compact.join(" — ")
          parts << "- #{label}: #{s[:url]}"
        else
          parts << "- #{s}"
        end
      end
    end

    parts.join("\n")
  end
end
