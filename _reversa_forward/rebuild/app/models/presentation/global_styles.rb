# frozen_string_literal: true

module Presentation
  # T-09 closed: the Rails-backed implementation of the `styling` pack's persistence seam.
  #
  # The pack declares zero dependencies (topology_decision.md option 3), so it may not
  # touch Active Record; it expresses storage as `Styling::GlobalStylesStore` and the
  # application supplies this. BR-MIGRATE-208: ONE record per theme — which is why it is a
  # column on `themes` rather than a table with a uniqueness validation hoping to hold.
  #
  # ⚠️ The oracle's only `wp_global_styles` row is `wp-global-styles-oracle`, i.e. it
  # belongs to a theme called `oracle`, NOT to the active `twentytwentyfive`. So the
  # 'custom' origin is EMPTY for every one of the 18 screens, and the golden files' global
  # styles are default + blocks + theme with no user layer. Asked, not assumed.
  class GlobalStyles < Styling::GlobalStylesStore
    def find_for_theme(stylesheet)
      theme = Theme.find_by(slug: stylesheet)
      return nil if theme.nil? || theme.user_styles.nil?

      record_for(theme)
    end

    def create_for_theme(stylesheet)
      theme = Theme.find_by(slug: stylesheet)
      return nil if theme.nil?

      if theme.user_styles.nil?
        theme.update!(user_styles: JSON.parse(Styling::GlobalStylesStore.initial_content))
      end
      record_for(theme)
    end

    private

    def record_for(theme)
      {
        "id" => theme.id,
        "content" => JSON.generate(theme.user_styles),
        "title" => Styling::GlobalStylesStore::INITIAL_TITLE,
        "name" => "wp-global-styles-#{Styling::GlobalStylesStore.urlencode(theme.slug)}",
      }
    end
  end
end
