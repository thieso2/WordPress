# frozen_string_literal: true

module Presentation
  class Theme < ApplicationRecord
    self.table_name = "themes"
    validates :slug, presence: true, uniqueness: true
    validates :version, presence: true
    scope :active, -> { where(active: true) }

    # The active theme's stylesheet slug — `get_stylesheet()`. Memoized per request by
    # the caller, never by a class variable: paradigm_decision.md implication 1.
    def self.active_slug = active.pick(:slug)

    # The 'theme' origin of the four-origin cascade (BR-MIGRATE-206), loaded by
    # `rake theme:load` so that a request never reads the theme directory.
    def resolver(store: GlobalStyles.new, core_data: {}, block_data: {})
      Styling::ThemeJsonResolver.new(
        store: store, stylesheet: slug, core_data: core_data,
        block_data: block_data, theme_data: theme_json || {}
      )
    end

    # BR-MIGRATE-001…006 carry the child-theme load order into Presentation::Theme.
    def parent = self.class.find_by(slug: parent_slug)

    def ancestry
      chain = [self]
      seen = Set.new([slug])
      node = parent
      while node && !seen.include?(node.slug)
        seen << node.slug
        chain << node
        node = node.parent
      end
      chain
    end

    # ── Lifecycle (Wave 4, console.themes) ───────────────────────────────────────────
    # A theme is DATA plus template files, never code — DEV-011: activating one does not
    # register any hooks, it swaps which row is active and lets the render path (which
    # already resolves templates by Theme.active, TemplateResolver#initialize) follow.

    # The display name. The themes table carries no `name` column (T-?? kept only what the
    # cascade needs); the human name lives in theme.json under `name` — written there by
    # `theme:load` from the style.css header, and by Egress install from the package's
    # header. Falls back to a WordPress-style humanisation of the slug, exactly as
    # WP_Theme does when the Name header is absent (class-wp-theme.php).
    def name
      value = theme_json.is_a?(Hash) ? theme_json["name"].to_s : ""
      value.presence || slug.to_s.tr("-_", "  ").split.map(&:capitalize).join(" ")
    end

    # `wp-content/themes/<slug>/screenshot.png` — the card image on themes.php. Served
    # out of the theme's stored assets when present; nil renders the empty frame the
    # legacy shows for a theme with no screenshot.
    def screenshot_url
      value = theme_json.is_a?(Hash) ? theme_json["screenshot"].to_s : ""
      value.presence
    end

    # themes.php:739 / delete_theme(): the ACTIVE theme cannot be deleted — the legacy
    # simply omits the Delete link for it, and delete_theme() refuses. Reproduced as a
    # guard so a hand-crafted request cannot delete the active row and leave the site
    # with no template to resolve (TemplateResolver::ThemeNotLoaded).
    def deletable? = !active?

    # switch_theme(), theme.php: exactly one theme is active (BR-MIGRATE-001…006). The
    # swap is atomic so a concurrent request never sees zero or two active themes.
    def activate!
      self.class.transaction do
        self.class.where(active: true).where.not(id: id).update_all(active: false)
        update!(active: true)
      end
      self
    end

    # delete_theme(): remove the theme and the documents that belong to it. Composition
    # rows are keyed by `theme_slug`, so the theme's templates, parts and patterns go with
    # it; the FK-less legacy needed a cron sweep for this (BR-MENU-05's cousin), the model
    # does it in one transaction.
    def delete!
      raise ActiveRecord::RecordNotDestroyed, "the active theme cannot be deleted" unless deletable?

      self.class.transaction do
        Composition::Template.where(theme_slug: slug).delete_all
        destroy!
      end
    end

  end
end
