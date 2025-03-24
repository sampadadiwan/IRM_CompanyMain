# Only apply patch if Rails 8
if Rails::VERSION::MAJOR >= 8
  ActiveSupport::Deprecation.singleton_class.class_eval do
    public :warn
  end
end
