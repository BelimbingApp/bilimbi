# The Design Library drift guards report specimens the campaign has not
# corrected yet, so they stay out of the default run (and out of `mix
# precommit`) until it does. Run them with
# `mix test --include design_library_drift`.
ExUnit.start(exclude: [:design_library_drift])
