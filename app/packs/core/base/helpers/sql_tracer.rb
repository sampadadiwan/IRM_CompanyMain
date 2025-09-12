module SqlTracer
  METHODS = %i[execute exec_query exec_cache select_all].freeze

  def self.start(pattern: /FROM `funds`.*`id`\s*=\s*317/)
    @tp&.disable
    @tp = TracePoint.new(:call) do |tp|
      next unless METHODS.include?(tp.method_id)
      next unless tp.defined_class.to_s.include?("ActiveRecord::ConnectionAdapters")

      sql = nil
      begin
        sql = tp.binding.local_variable_get(:sql) if tp.binding.local_variable_defined?(:sql)
      rescue NameError
      end
      next if sql && pattern && sql !~ pattern

      frame = caller_locations(2, 120).find do |loc|
        path = loc.absolute_path || loc.path
        path&.start_with?(Rails.root.to_s) && path.exclude?("/gems/")
      end

      Rails.logger.debug { "↳ #{frame ? "#{frame.path}:#{frame.lineno}" : '(no app frame)'}" }
      Rails.logger.debug { "SQL via #{tp.defined_class}##{tp.method_id}:" }
      Rails.logger.debug(sql || "(sql unavailable at this hook)")
      Rails.logger.debug
    end
    @tp.enable
    true
  end

  def self.stop
    @tp&.disable
    @tp = nil
  end
end
