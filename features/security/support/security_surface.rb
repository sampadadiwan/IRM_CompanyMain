# frozen_string_literal: true

# SecuritySurface — reads the app's real security surface from the running code, for the drift
# guards in features/security/security_surface_drift_guard.feature.
#
# WHY THIS EXISTS
# The October 2026 security review (docs/security/security_review_2026_10.md, "Recurring root
# causes") found that most of its findings came from a handful of repeated mistakes:
#
#   3. actions excluded from `verify_authorized`        (H1, H6, H7, H8, M12, M15, L10)
#   2. policy predicates that are just `true`           (C3, H14, H15, H16, M18–M21, M25)
#   7. endpoints that skip authentication / CSRF        (H2, M1, L10)
#
# Every one of those findings has its own scenario now, but those scenarios only prove the
# *fixed* places stay fixed. Nothing stopped the next new controller action, or the next
# `def destroy? = true`, from repeating the mistake. This module lists the surface as it is, so
# the feature can compare it with a reviewed allowlist and fail on anything new.
#
# HOW IT READS THE SURFACE
# It does not grep. `after_action :verify_authorized, except: %i[index search]` is declared once
# in WithAuthentication and then narrowed per controller with `skip_after_action`, re-declared
# `except:` lists, `only:` lists and `if:`/`unless:` procs. Grepping those is unreliable, so this
# instantiates each controller, sets `action_name`, and evaluates the callback's own conditions
# exactly as Rails would before running the action. Conditions it cannot evaluate without a real
# request (procs that read `params`, `request`, …) are reported as "conditional", never guessed.
#
# This file is plain Ruby with no Cucumber DSL, so it can also be run from `bin/rails runner` to
# regenerate an allowlist (see the header of each YAML file under features/security/allowlists/).
require "prism"
require "yaml"

module SecuritySurface
  module_function

  # Callback names this guard tracks, keyed by the label used in the allowlists.
  #   authorize    — Pundit's after_action that raises if the action never called `authorize`
  #                  (index actions use verify_policy_scoped instead, so either one counts)
  #   authenticate — Devise's before_action that requires a signed-in user
  #   csrf         — Rails' before_action that checks the authenticity token on non-GET requests
  #
  # Admin::* (Administrate) controllers do not inherit ApplicationController: their gate is
  # Admin::ApplicationController#authenticate_admin, which redirects anyone who is not a signed-in
  # :super or :support user, so it counts as both authentication and authorization there.
  CHECKS = {
    "authorize" => %i[verify_authorized verify_policy_scoped authenticate_admin],
    "authenticate" => %i[authenticate_user! authenticate_admin],
    "csrf" => %i[verify_authenticity_token]
  }.freeze

  # Controllers defined under app/ (not Devise, Doorkeeper, Blazer, Rails' own, …).
  def app_controllers
    # Load every controller file explicitly. `Rails.application.eager_load!` does not reach the
    # pack directories in the test environment (eager_load is off there and the packs are plain
    # autoload roots), so after it only ~14 of ~260 controllers were loaded and the guard would
    # have silently checked almost nothing.
    loader = Rails.autoloaders.main
    Rails.root.glob("app/**/*_controller.rb").each { |file| loader.cpath_expected_at(file.to_s)&.constantize }
    app_root = Rails.root.join("app").to_s
    (ActionController::Base.descendants + ActionController::API.descendants).uniq.select do |klass|
      next false if klass.name.blank? || klass.abstract?

      path = Object.const_source_location(klass.name)&.first
      path&.start_with?(app_root)
    end.sort_by(&:name)
  end

  # @return [Hash{String => Array<String>}] "authorize" / "authenticate" / "csrf" => sorted list of
  #   "Controller#action" entries where that protection does NOT run (or runs only conditionally,
  #   marked " (conditional)").
  def unprotected_actions
    result = CHECKS.keys.index_with { [] }
    routed_actions.each do |klass, actions|
      actions.each do |action|
        CHECKS.each do |label, filters|
          state = protection_state(klass, action, filters)
          next if state == :always

          entry = "#{klass.name}##{action}"
          entry += " (conditional)" if state == :conditional
          result[label] << entry
        end
      end
    end
    result.transform_values(&:sort)
  end

  # Only actions a route can reach. `action_methods` alone also lists public helper methods
  # (`dashboard_class`, `pagy_url_for`, …) that no request can call, which buried the real
  # entries under hundreds of false ones.
  # @return [Array<[Class, Array<String>]>]
  def routed_actions
    controllers = app_controllers.index_by(&:name)
    pairs = Rails.application.routes.routes.filter_map do |route|
      controller, action = route.defaults.values_at(:controller, :action)
      next if controller.blank? || action.blank?

      klass = controllers["#{controller}_controller".camelize]
      [klass, action.to_s] if klass&.action_methods&.include?(action.to_s)
    end
    pairs.uniq.group_by(&:first).transform_values { |list| list.map(&:last).sort }.sort_by { |klass, _| klass.name }
  end

  # :always      — at least one of `filters` runs unconditionally for this action
  # :conditional — one runs only when a condition we cannot evaluate statically holds
  # :never       — none of them runs (or the controller never declares them)
  def protection_state(klass, action, filters)
    controller = klass.new
    controller.action_name = action
    states = klass._process_action_callbacks.select { |cb| filters.include?(cb.filter) }.map do |cb|
      callback_state(controller, cb)
    end
    return :always if states.include?(:always)
    return :conditional if states.include?(:conditional)

    :never
  end

  # Evaluates a callback's `if:` / `unless:` conditions for this controller + action.
  def callback_state(controller, callback)
    ifs = callback.instance_variable_get(:@if).map { |c| condition_value(controller, c) }
    unlesses = callback.instance_variable_get(:@unless).map { |c| condition_value(controller, c) }
    return :never if ifs.include?(false) || unlesses.include?(true)
    return :conditional if ifs.include?(:unknown) || unlesses.include?(:unknown)

    :always
  end

  # true / false for conditions decidable from the class and action name alone; :unknown otherwise.
  def condition_value(controller, condition)
    case condition
    when AbstractController::Callbacks::ActionFilter
      condition.match?(controller)
    when :devise_controller?
      controller.devise_controller?
    else
      :unknown
    end
  rescue AbstractController::ActionNotFound
    # An `only:`/`except:` list naming an action the controller does not define: Rails raises at
    # request time. Treat as "does not match" — the action list here only has real actions.
    false
  end

  # @return [Array<String>] "PolicyClass#predicate?" for every predicate whose whole body is the
  #   literal `true` (both `def x?\n true\n end` and `def x? = true`). Parsed with Prism, so a
  #   comment or a multi-line body is never mistaken for one.
  def always_true_policy_predicates
    Rails.root.glob("app/**/*_policy.rb").flat_map do |path|
      found = []
      walk = lambda do |node, class_path|
        case node
        when Prism::ClassNode, Prism::ModuleNode
          class_path += [node.constant_path.slice]
        when Prism::DefNode
          body = node.body
          statements = body.is_a?(Prism::StatementsNode) ? body.body : [body].compact
          found << "#{class_path.join('::')}##{node.name}" if node.name.to_s.end_with?("?") && statements.size == 1 && statements.first.is_a?(Prism::TrueNode)
        end
        node.compact_child_nodes.each { |child| walk.call(child, class_path) }
      end
      walk.call(Prism.parse_file(path.to_s).value, [])
      found
    end.sort
  end

  # @return [Array<String>] "path | expression" for every place a view prints a NON-literal value
  #   raw, i.e. without Rails' HTML escaping:
  #     x.html_safe      (x is anything but a plain string literal)
  #     raw(x)
  #     <%== x %>
  #
  # Why: `.html_safe` on text a user typed was the XSS bug fixed on 2026-11-05 (notes, fund details,
  # help text, notification bodies, flash). RuboCop cannot see .erb files and this app has no ERB
  # linter, so nothing would stop the next `@record.notes.html_safe`. User-entered formatted text
  # should go through `safe_rich_text` (ApplicationHelper), which never appears in this list.
  #
  # How: each template is compiled exactly as Rails compiles it (ActionView's Erubi handler), then
  # parsed with Prism. Template text and `'<i class="ti ti-plus"></i>'.html_safe` are string literals
  # and pass. An interpolated string ("…#{value}…".html_safe) is listed: interpolation is where user
  # text gets in. Entries are keyed by expression, not line number, so moving code doesn't churn
  # the allowlist.
  def dynamic_raw_output
    Rails.root.glob("app/**/*.erb").flat_map do |path|
      relative = path.relative_path_from(Rails.root).to_s
      # Step 1: compile the template to the Ruby Rails would run. Rails wraps that code in a method,
      # so do the same: layouts and block partials `yield`, which only parses inside a method.
      ruby = ActionView::Template::Handlers::ERB::Erubi.new(path.read, trim: true).src
      parsed = Prism.parse("def __compiled_template\n#{ruby}\nend")
      # A template we cannot parse is listed too, so it can never hide an unreviewed raw output
      next ["#{relative} | (template could not be parsed)"] if parsed.failure?

      # Step 2: walk the tree for the three raw-output forms
      found = []
      walk = lambda do |node|
        if node.is_a?(Prism::CallNode)
          value = raw_output_value(node)
          found << "#{relative} | #{raw_output_label(node, value)}" if value && !plain_string_literal?(value)
        end
        node.compact_child_nodes.each { |child| walk.call(child) }
      end
      walk.call(parsed.value)
      found
    end.uniq.sort
  end

  # The value a call prints raw, or nil when the call is not a raw-output form.
  def raw_output_value(node)
    case node.name
    when :html_safe then node.receiver
    when :raw then node.receiver.nil? ? node.arguments&.arguments&.first : nil
    when :safe_expr_append= then node.arguments&.arguments&.first # what Rails compiles <%== x %> to
    end
  end

  def raw_output_label(node, value)
    source = value.slice.gsub(/\s+/, " ").strip
    case node.name
    when :html_safe then "#{source}.html_safe"
    when :raw then "raw(#{source})"
    else "<%== #{source} %>"
    end
  end

  def plain_string_literal?(node)
    node.is_a?(Prism::StringNode)
  end

  # Allowlist files live next to the feature. Each is a Hash of entry => reason.
  def allowlist_path(name)
    File.expand_path("../allowlists/#{name}.yml", __dir__)
  end

  def allowlist(name)
    YAML.safe_load_file(allowlist_path(name)) || {}
  end
end
