# Maps check keys (stored on workflow steps and frozen into snapshots) to check classes.
#
# Keys are permanent: a key is never removed or renamed while any snapshot uses it, and a changed
# meaning gets a new key (design Decision 19). Checks are registered at boot from
# config/initializers/workflow_checks.rb — never constantized from user input.
module WorkflowChecks
  module Registry
    @checks = {}

    class << self
      # Register a check class under its key; re-registering the same key replaces it (code reload)
      def register(klass)
        raise ArgumentError, "#{klass.name} has no key" if klass.key.blank?

        @checks[klass.key] = klass
      end

      # Instance of the check for a key; raises KeyError for an unknown key
      def fetch(key)
        @checks.fetch(key.to_s).new
      end

      def registered?(key)
        @checks.key?(key.to_s)
      end

      # Keys usable on a template for the given workflowable type (type-agnostic checks included)
      def keys_for(workflowable_type)
        @checks.select { |_key, klass| klass.workflowable_type.nil? || klass.workflowable_type == workflowable_type.to_s }.keys.sort
      end

      # [label, key] pairs for the step editor's Check / Skip selects
      def options_for(workflowable_type)
        keys_for(workflowable_type).map { |key| [@checks[key].label.presence || key, key] }
      end

      def label_for(key)
        @checks[key.to_s]&.label.presence || key.to_s
      end

      # Used by the initializer on each code reload so removed classes don't linger
      def reset!
        @checks = {}
      end
    end
  end
end
