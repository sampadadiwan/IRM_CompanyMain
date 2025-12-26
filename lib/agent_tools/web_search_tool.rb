module AgentTools
  class WebSearchTool
    def self.search(query, num_results: 5)
      start_time = Time.current
      Rails.logger.info "[WebSearchTool] Searching for: #{query}"

      api_key = Rails.application.credentials[:SERPAPI_KEY]
      if api_key.blank?
        Rails.logger.error "[WebSearchTool] SerpAPI key not configured in credentials"
        return { error: "SerpAPI key not configured" }
      end

      search = GoogleSearch.new(
        q: query,
        api_key: api_key,
        num: num_results
      )
      
      data = search.get_hash

      duration = (Time.current - start_time).round(2)
      Rails.logger.info "[WebSearchTool] Search completed for '#{query}' in #{duration}s"

      parse_serpapi_response(data)
    rescue StandardError => e
      Rails.logger.error "[WebSearchTool] Search failed: #{e.message}"
      { error: e.message }
    end

    private

    def self.parse_serpapi_response(data)
      return { error: data[:error] } if data[:error].present?

      results = []
      sources = []

      # Parse organic results
      (data[:organic_results] || []).each do |result|
        title = result[:title]
        snippet = result[:snippet]
        link = result[:link]

        results << "#{title}: #{snippet}" if snippet.present?
        sources << { title: title, url: link } if link.present?
      end

      # Include knowledge graph if available
      if data[:knowledge_graph].present?
        kg = data[:knowledge_graph]
        kg_text = "#{kg[:title]}: #{kg[:description]}" if kg[:description].present?
        results.unshift(kg_text) if kg_text.present?
      end

      Rails.logger.info "[WebSearchTool] Parsed #{results.count} results"

      {
        abstract_text: results.first,
        related_topics: results,
        sources: sources
      }
    end
  end
end
