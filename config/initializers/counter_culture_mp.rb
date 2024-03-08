# Monkey patch for CounterCulture gem to support deferring counter updates
# Source: https://github.com/magnusvk/counter_culture/issues/299
module CounterCulture
  module Extensions
    ClassMethods.module_eval do
      def defer_counter_culture_updates
        counter_culture_updates_was = Thread.current[:defer_counter_culture_updates]
        Thread.current[:defer_counter_culture_updates] = Array(counter_culture_updates_was) + [self]
        yield
      ensure
        Thread.current[:defer_counter_culture_updates] = counter_culture_updates_was
      end
    end
  end

  module DeferredUpdate
    private

    def _update_counts_after_create
      super unless Array(Thread.current[:defer_counter_culture_updates]).include?(self.class)
    end

    # called by after_destroy callback
    def _update_counts_after_destroy
      super unless Array(Thread.current[:defer_counter_culture_updates]).include?(self.class)
    end

    # called by after_update callback
    def _update_counts_after_update
      super unless Array(Thread.current[:defer_counter_culture_updates]).include?(self.class)
    end
  end
end

ActiveSupport.on_load(:active_record) do
  include CounterCulture::DeferredUpdate
end
