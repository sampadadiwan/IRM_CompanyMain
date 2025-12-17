class SectionContentCache
  CACHE_TTL = 1.hour.to_i

  class << self
    def cache_key(section_id, session_id)
      "section_cache:#{section_id}:#{session_id}"
    end

    # Store both document and web content for a section
    def store(section_id, session_id, document_content: nil, web_content: nil)
      key = cache_key(section_id, session_id)

      data = redis.hgetall(key)
      data = {} if data.blank?

      data["document_content"] = document_content if document_content.present?
      data["web_content"] = web_content if web_content.present?

      redis.hset(key, data) if data.present?
      redis.expire(key, CACHE_TTL)
    end

    # Get cached document content
    def get_document_content(section_id, session_id)
      redis.hget(cache_key(section_id, session_id), "document_content")
    end

    # Get cached web content
    def get_web_content(section_id, session_id)
      redis.hget(cache_key(section_id, session_id), "web_content")
    end

    # Get all cached content for a section
    def get_all(section_id, session_id)
      data = redis.hgetall(cache_key(section_id, session_id))
      return nil if data.blank?

      {
        document_content: data["document_content"],
        web_content: data["web_content"]
      }
    end

    # Clear cache for a section
    def clear(section_id, session_id)
      redis.del(cache_key(section_id, session_id))
    end

    private

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" })
    end
  end
end
