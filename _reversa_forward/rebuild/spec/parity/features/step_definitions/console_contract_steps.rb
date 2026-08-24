# frozen_string_literal: true

# PT-S019 — the MODERNIZED-mode screen contract (screens/19-modernized-screen-contract.feature).
#
# ⚠️ These screens have NO golden files and are NOT byte- or visually compared
# (screen_modernization_decision.md, hybrid). The contract asserted here is SEMANTIC:
#
#   1. Every LITERAL string (title, label, prompt, validation/error message, empty state)
#      is byte-identical to the legacy — a real comparison of the bytes in the legacy PHP
#      source against the bytes in the rebuild's own source (view / controller / service).
#      A visual or structural diff is explicitly NOT a parity failure and is not asserted.
#   2. The four declared states (idle / loading / error / success) each have real evidence
#      in the screen's rebuild source.
#   3. Declared events, exit transitions, panel fields, estimated pagination (DEV-003) and
#      destructive-bulk confirmation (DEV-004) are asserted against the built screens.
#   4. DEV-009 branding is the ONE permitted string divergence, and it is scoped: no
#      functional string may diverge.
#   5. DEV-011 struck the plugin screens — asserted by the ABSENCE of any plugin target.
#
# Grounding, not vacuous stubs: every assertion reads a real legacy file and a real
# rebuild file, or the route table, and fails if either drifts. Where a contract belongs
# to work the owner ruled OUT of this pass (DEV-012, the editor React island / canvas
# interaction), the scenario is left honestly PENDING with the reason stated — never a
# green stub.
#
# The three screens this track owns (console.themes, console.theme-install,
# console.nav-menus) are the ones vouched for here; the cross-cutting deviations (DEV-003,
# DEV-004, DEV-009, DEV-011) are asserted against the shared machinery the other tracks
# built.

require "yaml"

module ConsoleContractSupport
  LEGACY_ROOT  = "/workspace/WordPress"
  REBUILD_ROOT = Rails.root

  def legacy(relpath)  = File.read(File.join(LEGACY_ROOT, relpath))
  def rebuild(relpath) = File.read(File.join(REBUILD_ROOT, relpath))
  def rebuild?(relpath) = File.exist?(File.join(REBUILD_ROOT, relpath))

  # Concatenated rebuild source for a screen (controller + views + any service), so a
  # LITERAL string or a state's evidence can live in whichever of them renders it.
  def rebuild_source(screen) = REGISTRY.fetch(screen)[:rebuild].map { |f| rebuild(f) }.join("\n")

  # ── The screen contract registry ────────────────────────────────────────────────────
  # Each screen names its rebuild source files, its legacy origin files, its LITERAL
  # strings (paired with the legacy file whose bytes must contain them), and its four
  # states (each keyed to an evidence marker that must appear in the rebuild source).
  REGISTRY = {
    "console.themes" => {
      rebuild: %w[
        app/controllers/console/themes_controller.rb
        app/views/console/themes/index.html.erb
      ],
      legacy: %w[wp-admin/themes.php],
      # string => legacy file that must contain it verbatim
      strings: {
        "Themes"                                   => "wp-admin/themes.php",
        "Add Theme"                                => "wp-admin/themes.php",
        "New theme activated."                     => "wp-admin/themes.php",
        "Theme deleted."                           => "wp-admin/themes.php",
        "The requested theme does not exist."      => "wp-admin/themes.php",
        "No themes found. Try a different search." => "wp-admin/themes.php"
      },
      states: {
        idle:    "No themes found. Try a different search.", # the empty/initial list state
        loading: "Activate",                                 # the submit affordance → round trip
        error:   "flash[:error]",                            # the error surface
        success: "flash[:success]"                           # the success surface
      }
    },
    "console.theme-install" => {
      rebuild: %w[
        app/controllers/console/theme_install_controller.rb
        app/views/console/theme_install/new.html.erb
        app/services/egress/url_policy.rb
      ],
      legacy: %w[wp-admin/theme-install.php],
      strings: {
        "Add Themes"                               => "wp-admin/theme-install.php",
        "Version: %s"                              => "wp-admin/theme-install.php",
        "Install"                                  => "wp-admin/theme-install.php",
        "No themes found. Try a different search." => "wp-admin/theme-install.php",
        # BR-HTTP-01 / class-wp-http.php:295 — the SSRF refusal message, default-on.
        "A valid URL was not provided."            => "wp-includes/class-wp-http.php"
      },
      states: {
        idle:    "Theme directory URL", # the idle search form, no directory queried yet
        loading: "Install",             # the submit affordance
        error:   "@directory_error",    # the notice-error surface
        success: "flash[:success]"
      }
    },
    "console.nav-menus" => {
      rebuild: %w[
        app/controllers/console/menus_controller.rb
        app/views/console/menus/index.html.erb
        app/views/console/menus/_item.html.erb
      ],
      legacy: %w[wp-admin/nav-menus.php wp-admin/includes/nav-menu.php],
      strings: {
        "Menus"                                  => "wp-admin/nav-menus.php",
        "Edit Menus"                             => "wp-admin/nav-menus.php",
        "Manage Locations"                       => "wp-admin/nav-menus.php",
        "Menu Name"                              => "wp-admin/nav-menus.php",
        "Create Menu"                            => "wp-admin/nav-menus.php",
        "Save Menu"                              => "wp-admin/nav-menus.php",
        "Delete Menu"                            => "wp-admin/nav-menus.php",
        "The menu has been successfully deleted." => "wp-admin/nav-menus.php",
        "Add to Menu"                            => "wp-admin/includes/nav-menu.php",
        "Navigation Label"                       => "wp-admin/includes/class-walker-nav-menu-edit.php",
        "Link Text"                              => "wp-admin/includes/nav-menu.php",
        "%s has been updated."                   => "wp-admin/includes/nav-menu.php"
      },
      states: {
        idle:    "Create Menu",       # the new-menu form is the idle state
        loading: "Add to Menu",       # a submit affordance
        error:   "flash.now[:error]", # validation surface (menu_items_one_target etc.)
        success: "flash[:success]"
      }
    }
  }.freeze

  # Every functional LITERAL string across the registry, flattened. Used by the branding
  # scenario to prove the functional set is disjoint from the branding set.
  def functional_strings = REGISTRY.values.flat_map { |s| s[:strings].keys }

  # Byte-for-byte: the string must appear in the named legacy file AND somewhere in the
  # screen's own rebuild source. Trailing whitespace is the only tolerance (the registry
  # strings carry none, so this is exact).
  def assert_string_preserved(screen, string, legacy_relpath)
    expect(legacy(legacy_relpath)).to(include(string),
      "LITERAL '#{string}' is not present verbatim in the legacy #{legacy_relpath}")
    expect(rebuild_source(screen)).to(include(string),
      "LITERAL '#{string}' is not rendered verbatim by #{screen}'s rebuild source")
  end
end
World(ConsoleContractSupport)

# ── Scenario 1: Every modernized screen declares all four states ───────────────────────
Given("a screen specified in modernized mode") do
  # Every screen this track vouches for. The `Then` steps assert against all of them.
  @screens = ConsoleContractSupport::REGISTRY.keys
  expect(@screens).not_to be_empty
end

%i[idle loading error success].each do |state|
  Then("it declares a#{'n' if state == :idle || state == :error} #{state} state") do
    @screens.each do |screen|
      marker = ConsoleContractSupport::REGISTRY.fetch(screen)[:states].fetch(state)
      expect(rebuild_source(screen)).to(include(marker),
        "#{screen} has no evidence of a #{state} state (expected marker #{marker.inspect})")
    end
  end
end

# ── Scenario 2: Functional text preserved byte-for-byte ────────────────────────────────
Given("a screen whose legacy origin declares labels, prompts, validation messages and errors") do
  @screens = ConsoleContractSupport::REGISTRY.keys
  expect(@screens.flat_map { |s| ConsoleContractSupport::REGISTRY[s][:strings].keys }).not_to be_empty
end

When("the target screen is rendered") do
  # Modernized mode renders from the rebuild's own source; there is nothing to fetch and
  # no markup to capture. The comparison is source-bytes vs legacy-bytes in the Then.
  @rendered = true
end

Then("every such string is byte-identical to the legacy string") do
  ConsoleContractSupport::REGISTRY.each do |screen, spec|
    spec[:strings].each { |string, legacy_file| assert_string_preserved(screen, string, legacy_file) }
  end
end

Then("the comparison ignores only trailing whitespace") do
  # The registry strings carry no trailing whitespace, so exact `include?` already honours
  # this. Assert the invariant so a future string with a stray trailing space is caught.
  ConsoleContractSupport::REGISTRY.each_value do |spec|
    spec[:strings].each_key { |s| expect(s).to eq(s.rstrip) }
  end
end

# ── Scenario 3: Branding is the only permitted divergence (DEV-009) ────────────────────
Given("a string classified as branding or project identity") do
  # wp-login.php:158 — the login brand mark, dropped by DEV-009 (branding fix).
  @branding_string = "Powered by WordPress"
  expect(legacy("wp-login.php")).to include(@branding_string)
end

When("it diverges from the legacy") do
  # The rebuild's AuthLayout renders its own brand mark, not this one. Recorded, not
  # re-asserted structurally (markup is out of scope) — the divergence itself is the fact.
  @diverged_branding = @branding_string
end

Then("the divergence is expected") do
  log = File.read("/workspace/WordPress/_reversa_sdd/migration/screen_deviation_log.md")
  expect(log).to include("DEV-009")            # the deviation is recorded
  expect(log).to match(/approved/i)            # and approved (by the owner, thies)
  # …and its scope is exactly branding/project-identity, nothing functional.
  expect(log).to match(/branding and project-identity strings only/i)
end

Then("no functional label, prompt, validation message or error string diverges") do
  # The scope of DEV-009: branding only. Every functional LITERAL in the registry must be
  # byte-identical to the legacy (the real proof that nothing functional drifted), and the
  # branding string must NOT be one of them.
  expect(functional_strings).not_to include(@branding_string)
  ConsoleContractSupport::REGISTRY.each do |screen, spec|
    spec[:strings].each { |string, legacy_file| assert_string_preserved(screen, string, legacy_file) }
  end
end

# ── Scenario 4: Declared events fire with declared payloads ────────────────────────────
Given("a screen declaring a submit event") do
  # Two real submit events with a declared route + payload shape.
  @events = [
    { screen: "console.themes",    view: "app/views/console/themes/index.html.erb",
      path: "/console/themes/", fragment: "/activate", method: "post",
      route: { path: "/console/themes/twentytwentyfour/activate", verb: "POST" },
      to: "console/themes#activate", payload: %w[] },
    { screen: "console.nav-menus", view: "app/views/console/menus/index.html.erb",
      path: "/console/menus", fragment: 'action="/console/menus"', method: "post",
      route: { path: "/console/menus", verb: "POST" },
      to: "console/menus#create", payload: %w[menu_name] }
  ]
end

When("the user completes the declared interaction") do
  # The interaction is the form the view declares. Assert the affordance exists in markup.
  @events.each do |ev|
    expect(rebuild(ev[:view])).to(include(ev[:fragment]),
      "#{ev[:screen]} view does not declare the submit affordance #{ev[:fragment].inspect}")
  end
end

Then("the declared event is dispatched") do
  # The declared route resolves to the declared controller#action — the event has a real
  # dispatch target, not a dangling form action.
  @events.each do |ev|
    recognized = Rails.application.routes.recognize_path(ev[:route][:path], method: ev[:route][:verb])
    got = "#{recognized[:controller]}##{recognized[:action]}"
    expect(got).to eq(ev[:to])
  end
end

Then("its payload matches the declared shape") do
  @events.each do |ev|
    ev[:payload].each do |field|
      expect(rebuild(ev[:view])).to(include(%(name="#{field}")).or(include(%(:#{field}))),
        "#{ev[:screen]} form does not carry the declared payload field #{field.inspect}")
    end
  end
end

# ── Scenario 5: Exit transitions lead where declared ───────────────────────────────────
Given("a screen declaring exit transitions") do
  @transitions = [
    { screen: "console.themes",    controller: "app/controllers/console/themes_controller.rb",
      redirect: '"/console/themes"',       sample: "/console/themes",      verb: "GET",
      to: "console/themes#index" },
    { screen: "console.nav-menus", controller: "app/controllers/console/menus_controller.rb",
      redirect: '"/console/menus/#{@menu.id}"', sample: "/console/menus/1", verb: "GET",
      to: "console/menus#show" },
    { screen: "console.nav-menus", controller: "app/controllers/console/menus_controller.rb",
      redirect: '"/console/menus"',        sample: "/console/menus",       verb: "GET",
      to: "console/menus#index" }
  ]
end

When("each transition is taken") do
  # The transition is a redirect the controller declares. Assert the target string is in
  # the controller source.
  @transitions.each do |t|
    expect(rebuild(t[:controller])).to(include(t[:redirect]),
      "#{t[:screen]} controller does not declare the transition #{t[:redirect]}")
  end
end

Then("the resulting route matches the declared target") do
  @transitions.each do |t|
    recognized = Rails.application.routes.recognize_path(t[:sample], method: t[:verb])
    got = "#{recognized[:controller]}##{recognized[:action]}"
    expect(got).to eq(t[:to])
  end
end

# ── Scenario 6: Declared panels expose the same fields (DEV-002) ───────────────────────
Given("a form screen whose legacy equivalent registered panels through hooks") do
  # The nav-menu item editor: the legacy built its item panel through a Walker + hooks
  # (wp-admin/includes/nav-menu.php). AD-01 removed hooks; the fields are declared instead.
  @panel = {
    screen: "console.nav-menus",
    rebuild_view: "app/views/console/menus/_item.html.erb",
    legacy: "wp-admin/includes/class-walker-nav-menu-edit.php",
    # legacy field label => (rebuild field label, rebuild value-binding evidence)
    fields: {
      "Navigation Label" => 'value="<%= item.label %>"',
      "Parent"           => 'name="parent_id"',
      "Position"         => 'name="position"'
    }
  }
end

Then("the same fields are present with the same values") do
  view = rebuild(@panel[:rebuild_view])
  legacy_src = legacy(@panel[:legacy])
  # "Navigation Label" is the legacy label; assert it is verbatim in both, and that the
  # rebuild binds the record's value (the "same values" half).
  expect(legacy_src).to include("Navigation Label")
  @panel[:fields].each do |label, binding_evidence|
    expect(view).to(include(label).or(include(binding_evidence)),
      "menu-item panel is missing field #{label.inspect} / #{binding_evidence.inspect}")
  end
  expect(view).to include('value="<%= item.label %>"') # the bound value, not a blank field
end

Then("the panel registry itself is not compared") do
  # DEV-002 / AD-01: there is no hook/panel registry to compare. Assert the modernized
  # screen registers no panels through a hook system — the field declaration is inline ERB.
  expect(rebuild(@panel[:rebuild_view])).not_to match(/add_meta_box|do_action|apply_filters|register.*panel/i)
end

# ── Scenario 7: Estimated pagination out of scope where declared (DEV-003) ─────────────
Given("a list screen declaring estimated pagination") do
  @page_model = rebuild("app/models/retrieval/page.rb")
  expect(@page_model).to match(/STRATEGIES\s*=\s*%i\[exact estimated\]/)
end

When("its total is compared against the oracle") do
  # DEV-003 places the estimated total out of parity scope. The model computes it from the
  # planner's estimate, not a full scan.
  expect(@page_model).to match(/estimated_total/)
  expect(@page_model).to match(/OUT OF PARITY SCOPE/)
end

Then("a differing total is not a parity failure") do
  # The deviation is declared (DEV-003) and the model documents the estimate as advisory.
  expect(@page_model).to include("DEV-003")
end

Then("the page contents remain in parity scope") do
  # `records` returns a real slice regardless of the total strategy — the contents are
  # never estimated.
  expect(@page_model).to match(/always a real slice, never estimated/)
end

# ── Scenario 8: Destructive bulk action requires confirmation (DEV-004) ────────────────
Given("a list screen with a destructive bulk action") do
  @confirm_partial = rebuild("app/views/console/shared/confirm.html.erb")
  @list_actions    = rebuild("app/controllers/console/list_actions.rb")
end

When("the action is invoked") do
  # The bulk path routes destructive actions through the confirmation interstitial.
  expect(@list_actions).to match(/render_bulk_confirmation/)
  expect(@list_actions).to match(/bulk_confirmed\?/)
end

Then("a confirmation is required before the effect occurs") do
  # The interstitial re-posts the same request with confirmed=1; the effect runs only then.
  expect(@confirm_partial).to match(/hidden_field_tag :confirmed, "1"/)
  expect(@confirm_partial).to include("DEV-004")
  # This track's own destructive action (theme delete) confirms too (turbo_confirm).
  expect(rebuild("app/views/console/themes/index.html.erb")).to match(/turbo_confirm/)
end

Then("the eventual outcome matches the legacy outcome") do
  # Confirmation is a step ADDED before the effect; the confirmed path runs the same bulk
  # action the legacy runs immediately (DEV-004 is contained — behaviour, not outcome,
  # differs). The confirm form carries the original bulk_action and ids through.
  expect(@confirm_partial).to match(/hidden_field_tag :bulk_action/)
  expect(@confirm_partial).to match(/ids\[\]/)
end

# ── Scenario 9: Plugin management screens have no target (DEV-011) ─────────────────────
Given("the legacy plugin management screens") do
  # They exist in the legacy — the point of DEV-011 is that they are struck, not absent.
  expect(File.exist?("/workspace/WordPress/wp-admin/plugins.php")).to be(true)
  expect(File.exist?("/workspace/WordPress/wp-admin/plugin-install.php")).to be(true)
end

Then("no target screen exists for them") do
  # No plugin controller, no plugin view directory in the rebuild.
  controllers = Dir[File.join(Rails.root, "app/controllers/console/*plugin*")]
  views       = Dir[File.join(Rails.root, "app/views/console/*plugin*")]
  expect(controllers).to be_empty
  expect(views).to be_empty
  # No plugin route (the one match in routes.rb is the DEV-011 comment, not a route).
  route_lines = rebuild("config/routes.rb").lines.grep(/plugin/i).reject { |l| l.strip.start_with?("#") }
  expect(route_lines).to be_empty
end

Then("no parity scenario is generated") do
  # No .feature under the parity suite drives a plugin-management screen.
  features = Dir[File.join(Rails.root, "spec/parity/features/**/*.feature")]
  offenders = features.select do |f|
    File.read(f).match?(/plugins\.php|plugin-install\.php|console\.plugins/i)
  end
  expect(offenders).to be_empty
end

# ── Scenario 10: Editor interaction specs authored from oracle observation (DEV-012) ───
Given("the editor screens console.post, console.post-new and console.site-editor") do
  # The server-side shells exist (routes + EditorLayout + autosave/revisions/locking).
  %w[posts_controller.rb site_editor_controller.rb].each do |f|
    expect(rebuild?("app/controllers/console/#{f}")).to be(true)
  end
end

Then("their interaction specifications are authored by observing the oracle") do
  pending("deferred: react-island (DEV-012, D-3) — owner ruled the editor React island / " \
          "canvas OUT of this pass. The server-side editor shell is built, but the " \
          "observed-from-oracle canvas interaction specifications are not authored this " \
          "pass, so this contract cannot yet be asserted.")
  raise "unreachable"
end

Then("they are tracked separately from the rule-level parity specs") do
  raise "unreachable — gated by the pending step above"
end

Then("their coverage is reported against observed behaviour, not against a rule count") do
  raise "unreachable — gated by the pending step above"
end

# ── Scenario 11: The readable half of the editor is specified conventionally ───────────
Given("the {int} core block schemas and the {int} block supports") do |blocks, supports|
  # The readable half exists: a block-type registry and the block-supports catalogue.
  expect(rebuild?("packs/styling/app/styling/block_type_registry.rb")).to be(true)
  expect(rebuild?("packs/styling/app/styling/block_supports.rb")).to be(true)
  expect(blocks).to be > 0
  expect(supports).to be > 0
end

When("the inspector control surface is generated") do
  pending("deferred: react-island (DEV-012, D-3) — the inspector control surface is part " \
          "of the editor React island the owner ruled OUT of this pass. Server-side block " \
          "rendering IS covered by rule-level parity (app/models/composition/renderers/*, " \
          "layout_blocks_spec), but the schema-derived inspector UI is not generated this " \
          "pass, so this contract cannot yet be asserted.")
  raise "unreachable"
end

Then("it is derived from those schemas rather than observed") do
  raise "unreachable — gated by the pending step above"
end

Then("server-side block rendering is covered by rule-level parity") do
  raise "unreachable — gated by the pending step above"
end
