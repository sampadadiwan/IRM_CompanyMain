# frozen_string_literal: true

# Loads the Dr:: modules for the DR rake tasks that run WITHOUT the Rails environment.
#
# aws:setup_infra and aws:dr_drill never invoke :environment: they run on the operator's machine
# against AWS, Pulumi and Capistrano, so Rails is defined (the Rakefile loads
# config/application) but not initialized, and the autoloader never resolves lib/dr. They
# failed with "uninitialized constant Dr" on the first drill after the DR changes
# (2026-11-08) - so every module those tasks reach is required here, explicitly, together with
# the ActiveSupport extensions the modules use.
#
# Tasks that DO load :environment (dr:verify, dr:reindex_search, db:restore_*_remote) also load
# this file through aws_utils.rb. That is safe: Zeitwerk does not set an autoload for a constant
# that is already defined - the same arrangement as lib/critical_error_whatsapp, which the
# exception-notification initializer requires by hand.
#
# Dr::SearchIndexes is deliberately NOT here: it needs Chewy and the app's index classes, and
# only runs inside :environment tasks, where the autoloader finds it.

require "erb"
require "json"
require "socket"
require "time"
require "active_support"
require "active_support/core_ext/enumerable"       # Array#pluck (Dr::ReportModel)
require "active_support/core_ext/object/blank"     # #presence / #present? (aws.rake, Dr::ReportModel)
require "active_support/core_ext/string/exclude"   # String#exclude? (Dr::DrillTeardown)
require "active_support/core_ext/string/output_safety" # ERB::Util.html_escape (Dr::ReportRender)

lib = File.expand_path("..", __dir__)
# Order matters only where one module names another at load time: none do (lookups happen at
# call time), but keep the dependency order readable.
%w[dr/backup_schedule dr/backup_lock dr/old_backup_jobs dr/pulumi_lock dr/drill_teardown
   dr/report_catalog dr/report_model dr/report_render drill_stack].each do |file|
  require File.join(lib, file)
end
