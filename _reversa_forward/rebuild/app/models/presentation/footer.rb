# frozen_string_literal: true

module Presentation
  # `wp_footer()`, and the actions default-filters.php registers on it.
  #
  # AD-01: an action, and gone. What remains is the fixed sequence core itself prints.
  class Footer
    def initialize(site_url:, theme_slug:, enqueued_script_modules: [], enqueued_scripts: [])
      @site = site_url.to_s.chomp("/")
      @enqueued_script_modules = enqueued_script_modules
      @enqueued_scripts = enqueued_scripts
      @theme = theme_slug
    end

    def to_html
      [speculation_rules, *script_module_tags, *script_tags, emoji_settings,
       emoji_loader].compact.join("\n")
    end

    # ⚠️ Public: the embed template (Presentation::EmbedPage) prints these same two
    # elements — `_print_emoji_detection_script()` runs on `embed_head` as well as
    # `wp_head` (default-filters.php:741) — and reimplementing them there would be a
    # second definition of the same legacy output.

    # `_print_emoji_detection_script()`, wp-includes/formatting.php:6030.
    def emoji_settings
      settings = Assets["wp-emoji-settings"]["settings"].merge(
        "source" => { "concatemoji" => "#{@site}/wp-includes/js/wp-emoji-release.min.js?ver=#{Head::GENERATOR_VERSION}" }
      )
      %(<script id="wp-emoji-settings" type="application/json">\n#{JSON.generate(settings)}\n</script>)
    end

    def emoji_loader
      asset = Assets["wp-emoji-loader"]
      url = asset["source_url"].sub("{site}", @site)
      %(<script type="module">\n#{asset["js"]}\n//# sourceURL=#{url}\n</script>)
    end

    private

    # `print_enqueued_script_modules()`, class-wp-script-modules.php:533. One `<script
    # type="module">` per enqueued module, in dependency order.
    #
    # The attribute set is built at :559 — `type`, `src`, `id` (the module id plus
    # `-js-module`), then `fetchpriority` when it is not 'auto'. `data-wp-router-options`
    # is added for every `@wordpress/block-library/*` module, because script-modules.php:209
    # marks all core blocks as compatible with client-side navigation and the Interactivity
    # API attaches the attribute to those tags
    # (class-wp-interactivity-api.php:422). ⚠️ That attachment is a `wp_script_attributes`
    # filter in the legacy, but it is CORE's own and always runs, so AD-01 makes its result
    # the permanent default rather than removing it — the value is written directly here
    # and there is no way to change it.
    #
    # Attributes are printed in ascending name order, as `wp_sanitize_script_attributes()`
    # produces them.
    def script_module_tags
      queue = Array(@enqueued_script_modules)
      return [] if queue.empty?

      catalogue = Assets.script_modules
      Assets.script_module_dependencies(queue).select { |id| queue.include?(id) }.map do |id|
        entry = catalogue[id]
        next if entry.nil?

        attributes = {
          "id" => "#{id}-js-module",
          "src" => "#{@site}#{entry["src"]}?ver=#{entry["version"]}",
          "type" => "module",
        }
        attributes["fetchpriority"] = entry["fetchpriority"] if entry["fetchpriority"] != "auto"
        if entry["client_navigation"]
          attributes["data-wp-router-options"] =
            JSON.generate({ "loadOnClientNavigation" => true })
        end
        rendered = attributes.sort.map { |k, v| %(#{k}="#{ERB::Util.html_escape(v)}") }.join(" ")
        %(<script #{rendered}></script>)
      end.compact
    end

    # `wp_footer()` → `wp_print_footer_scripts()` — the CLASSIC `$wp_scripts` queue, which
    # prints after the script modules. Exactly one classic script is reachable from a
    # rendered block in this corpus: 'comment-reply', enqueued by
    # `core/post-comments-form` (wp-includes/blocks/post-comments-form.php:52).
    #
    # The tag's shape is fixed by core's own registration (wp-includes/script-loader.php:
    # `$scripts->add( 'comment-reply', "/wp-includes/js/comment-reply$suffix.js" …
    # array( 'strategy' => 'async' ) )`): the async strategy prints `async
    # data-wp-strategy="async"`, the fetchpriority feature adds `fetchpriority="low"`,
    # and `ver` falls back to the WordPress version. Attributes in ascending name order,
    # as `wp_sanitize_script_attributes()` emits them. AD-01: `script_loader_tag` is a
    # filter and is gone — this shape cannot be changed.
    SCRIPT_TAGS = {
      "comment-reply" => %(<script async data-wp-strategy="async" fetchpriority="low" ) +
                         %(id="comment-reply-js" src="%{site}/wp-includes/js/comment-reply.min.js) +
                         %(?ver=#{Head::GENERATOR_VERSION}"></script>),
    }.freeze

    def script_tags
      Array(@enqueued_scripts).filter_map { |handle| SCRIPT_TAGS[handle]&.gsub("%{site}", @site) }
    end

    # `wp_print_speculation_rules()`, wp-includes/speculative-loading.php. The default
    # configuration is `conservative` prefetch of documents, with core's exclusion list —
    # which names the ACTIVE THEME's directory, so it is not a constant.
    def speculation_rules
      rules = {
        "prefetch" => [{
          "source" => "document",
          "where" => { "and" => [
            { "href_matches" => "/*" },
            { "not" => { "href_matches" => ["/wp-*.php", "/wp-admin/*", "/wp-content/uploads/*",
                                            "/wp-content/*", "/wp-content/plugins/*",
                                            "/wp-content/themes/#{@theme}/*", "/*\\?(.+)"] } },
            { "not" => { "selector_matches" => 'a[rel~="nofollow"]' } },
            { "not" => { "selector_matches" => ".no-prefetch, .no-prefetch a" } },
          ] },
          "eagerness" => "conservative",
        }],
      }
      %(<script type="speculationrules">\n#{JSON.generate(rules)}\n</script>)
    end

  end
end
