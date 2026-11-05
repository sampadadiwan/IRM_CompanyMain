# frozen_string_literal: true

# Route Rails JSON encoding (render json:, to_json, as_json, jbuilder) through Oj's C encoder.
# Oj.optimize_rails keeps ActiveSupport's as_json semantics (time formats, BigDecimal as string,
# escape_html_entities_in_json) while replacing the pure-Ruby encoder underneath.
require "oj"
Oj.optimize_rails
