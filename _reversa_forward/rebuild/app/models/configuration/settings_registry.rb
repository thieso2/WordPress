# frozen_string_literal: true

module Configuration
  # ── Deferred item D-6, decided ───────────────────────────────────────────────────
  #
  # THE DECISION. The ~130 option names an install seeds are NOT pushed wholesale into a
  # typed schema. `Configuration::Setting` stays the single store (raw jsonb keyed by
  # name, AD-06); the seeding pipeline is untouched, and every existing read
  # (`Configuration::Setting[...]`) keeps working byte for byte.
  #
  # What IS typed is only the SLICE the nine settings screens expose — roughly forty
  # names. For each, the registry declares its section, a TYPE (so a form's string
  # params are cast to the shape the option is stored and read in), a DEFAULT (so an
  # unset option renders sensibly), and — where the legacy's `sanitize_option()`
  # transforms the value on write — a SANITIZER. This is a fact about the product, like
  # Access::RoleCatalogue, so it is code, not a table: a typed schema in a settings row
  # is exactly what AD-06 removed.
  #
  # Why this scope and no more. A setting only needs a declared type where a HUMAN
  # writes it through a form (strings in, a specific shape out) or where an unset value
  # must render a default. The other ~90 names are internal machinery, arrays, ids and
  # structural flags that no screen edits; typing them would be schema for schema's sake
  # and a second place for their shape to drift from the code that actually reads them.
  # They remain raw jsonb, read through `Configuration::Setting[...]` as before.
  #
  # BR-MIGRATE-014 (BR-OPT-15): every option write passes through sanitize_option().
  # For `blogname`/`blogdescription` that means `esc_html`, which is why they are
  # already HTML-escaped at rest (Configuration::Setting::SANITIZED_ON_WRITE); the
  # registry reproduces that escaping on save so a value written HERE matches a value
  # the legacy wrote there.
  module SettingsRegistry
    Field = Struct.new(:name, :type, :default, :sanitizer, keyword_init: true) do
      # Cast a form parameter (always a string, or nil for an absent checkbox) to the
      # value the option is stored as.
      def cast(raw)
        value = case type
                when :boolean then checkbox(raw)
                when :integer then raw.to_s.strip.empty? ? default : raw.to_i
                else raw.to_s
                end
        sanitizer ? sanitizer.call(value) : value
      end

      # An unchecked checkbox submits nothing; the legacy stores '0' for the "off"
      # state of these flags (options.php's whitelist), and Discussion/Registration
      # read '0' and '' alike as false. '1' is the only "on" value.
      def checkbox(raw)
        raw.to_s == "1" ? "1" : "0"
      end
    end

    # esc_html( $value ), wp-includes/formatting.php:5006 — _wp_specialchars with
    # ENT_QUOTES and no double-encoding: & < > " ' become entities, an existing entity
    # is left alone. The narrow reproduction of the one sanitize_option arm the built
    # screens can trigger (BR-MIGRATE-014).
    ESC_HTML = lambda do |value|
      value.to_s
           .gsub("&", "&amp;")
           .gsub("<", "&lt;").gsub(">", "&gt;")
           .gsub('"', "&quot;").gsub("'", "&#039;")
           # do NOT double-encode: restore an entity the first gsub split.
           .gsub(/&amp;(#0*39|#x0*27|apos|quot|amp|lt|gt|#\d+|#x[0-9a-f]+);/i, '&\1;')
    end

    def self.f(name, type, default, sanitizer = nil)
      Field.new(name: name.to_s, type: type, default: default, sanitizer: sanitizer)
    end

    # section key => ordered fields. The section keys are this track's routes; the
    # option names and their shapes are the legacy's. The field SET per section is
    # exactly the settings target_screens.md § Settings screens (:533) records that
    # screen as owning — DEV-002's declared field list. The legacy screens carry a few
    # more controls (a Site Icon picker, the avatar block, Update Services, post-format
    # defaults); those are scoped out here deliberately, not overlooked, because the
    # spec assigns each screen a specific settings set and this registry is that set.
    SECTIONS = {
      "general" => [
        f("blogname", :string, "", ESC_HTML),
        f("blogdescription", :string, "", ESC_HTML),
        f("siteurl", :string, ""),
        f("home", :string, ""),
        f("timezone_string", :string, ""),
        f("date_format", :string, "F j, Y"),
        f("time_format", :string, "g:i a"),
        f("users_can_register", :boolean, "0"),
        f("default_role", :string, "subscriber"),
      ],
      "writing" => [
        f("default_category", :integer, 1),
        f("mailserver_url", :string, "mail.example.com"),
        f("mailserver_login", :string, "login@example.com"),
        f("mailserver_pass", :string, "password"),
        f("mailserver_port", :integer, 110),
        f("default_email_category", :integer, 1),
      ],
      "reading" => [
        f("show_on_front", :string, "posts"),
        f("page_on_front", :integer, 0),
        f("page_for_posts", :integer, 0),
        f("posts_per_page", :integer, 10),
        f("posts_per_rss", :integer, 10),
        f("blog_public", :boolean, "1"),
      ],
      # ⚠️ The whole comment-moderation policy (target_screens.md:538). The three
      # deviations BR-CMT-04/08/10 live in Discussion::ModerationPolicy already; this
      # screen only writes the option values that policy reads.
      "discussion" => [
        f("comment_moderation", :boolean, "0"),
        f("comment_previously_approved", :boolean, "1"),
        f("comment_max_links", :integer, 2),
        f("moderation_keys", :text, ""),
        f("disallowed_keys", :text, ""),
        f("close_comments_for_old_posts", :boolean, "0"),
        f("close_comments_days_old", :integer, 14),
      ],
      "media" => [
        f("thumbnail_size_w", :integer, 150),
        f("thumbnail_size_h", :integer, 150),
        f("thumbnail_crop", :boolean, "1"),
        f("medium_size_w", :integer, 300),
        f("medium_size_h", :integer, 300),
        f("large_size_w", :integer, 1024),
        f("large_size_h", :integer, 1024),
        f("uploads_use_yearmonth_folders", :boolean, "1"),
      ],
      # permalink_structure is written through Routing::PermalinkStructure.change_to,
      # not this registry's plain save — the registry types it so the form can read the
      # current value, but the controller routes the write through the aggregate that
      # recomputes the reserved-segment set (BR-POST-07, F-RW-06).
      "permalinks" => [
        # The default mirrors Routing::PermalinkStructure::DEFAULT_PATTERN, which is the
        # authority — but Configuration must not reference Routing (Routing depends on
        # Configuration, never the reverse; bin/check_cycles). The literal is inlined so
        # this low namespace stays a leaf. The controller writes this option through
        # Routing::PermalinkStructure.change_to, so the two never diverge in practice.
        f("permalink_structure", :string, "/%year%/%monthnum%/%postname%/"),
      ],
      # privacy page selection is written through the controller's own flow
      # (wp_page_for_privacy_policy is a post id; T-12 remapped it at seed).
      "privacy" => [
        f("wp_page_for_privacy_policy", :integer, 0),
      ],
    }.freeze

    module_function

    def section(key) = SECTIONS.fetch(key.to_s, [])

    def field(name)
      SECTIONS.each_value { |fields| fields.each { |fld| return fld if fld.name == name.to_s } }
      nil
    end

    def sections = SECTIONS.keys

    # The current stored value, or the declared default when the option is unset
    # (Configuration::Setting[] answers `false` for an absent name, BR-OPT).
    def current(name)
      fld = field(name)
      raw = Configuration::Setting[name]
      return fld ? fld.default : raw if raw == false || raw.nil?

      raw
    end

    # A section's current values as { name => value }, defaults filled in.
    def values_for(section_key)
      section(section_key).to_h { |fld| [fld.name, current(fld.name)] }
    end
  end
end
