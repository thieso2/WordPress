# frozen_string_literal: true

# Block renderers register themselves by name when their class body runs
# (`Renderers::Base.handles`). Under Zeitwerk that body only runs when something
# references the constant, so in any environment with `eager_load = false` — development
# and test — `Renderers.for("core/navigation")` would answer nil and every dynamic block
# would silently fall back to its saved markup. Silently: no error, just wrong bytes.
#
# Touching each constant once per boot (and once per reload) is what makes the registry
# complete. It is a load-order fix, not a hook: nothing here decides WHICH renderer
# handles a block, and there is no way to substitute one afterwards (AD-01).
Rails.application.config.to_prepare do
  Dir[Rails.root.join("app/models/composition/renderers/*.rb")].sort.each do |path|
    name = File.basename(path, ".rb")
    next if name == "base"

    Composition::Renderers.const_get(name.camelize)
  end
end
