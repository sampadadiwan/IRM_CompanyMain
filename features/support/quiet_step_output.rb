# Silences debug printing from step definitions on parallel runs.
#
# Steps carry ~800 puts/ap/pp/print calls ("Setting name=... on Deal", "####Entity####" JSON dumps,
# awesome_print'ed records) that are useful when stepping through one scenario but, across a pcuc
# run, add up to ~300 lines per scenario - about a million lines of four workers interleaved that no
# one reads, all pushed through parallel_tests' output prefixing.
#
# bin/pcuc sets PCUC_QUIET=1 (VERBOSE=1 keeps the output); `cuc` and plain cucumber are unaffected.
# The overrides live on the World, so they catch calls made from step definitions and World helpers
# (key_values, TablePrinter) only - Cucumber's formatters and app code write elsewhere.
module QuietStepOutput
  %i[puts print pp ap].each do |name|
    define_method(name) { |*_args, **_opts| nil }
  end
end

World(QuietStepOutput) if ENV["PCUC_QUIET"] == "1" && ENV["VERBOSE"] != "1"
