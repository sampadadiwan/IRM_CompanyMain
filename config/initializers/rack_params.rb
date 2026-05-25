# FormType edit forms with 200+ custom fields generate ~6,000+ POST params,
# exceeding Rack 3.2's default limit of 4096. When the limit is hit, Rack fails
# to parse the entire body, so _method=patch is dropped and Rails routes it as
# POST /form_types/:id (no matching route) → 404.
#
# With 206 FCFs × ~31 fields each = ~6,386 params; raise limit to 65536.
Rack::Utils.default_query_parser = Rack::QueryParser.make_default(
  Rack::Utils.param_depth_limit,  # keep default depth limit (32)
  params_limit: 65_536
)
