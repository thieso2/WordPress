# frozen_string_literal: true

module Composition
  module Renderers
    # Layout + text blocks, and the block supports they depend on.
    #
    # ── What is here and why ──────────────────────────────────────────────────────────
    # Twelve of the thirteen blocks in this family are STATIC: their saved markup already
    # carries everything the editor serialized (`has-base-background-color`, `alignwide`,
    # `style="padding-top:…"`). `Base` emits that markup unchanged and is the right answer
    # for them, exactly as the brief says.
    #
    # What the legacy adds ON TOP of the saved markup, at render time, is not a renderer at
    # all — it is the `render_block` filter chain in `wp-includes/block-supports/`. That
    # chain is what produces `is-layout-flex`, `wp-block-group-is-layout-flex` and
    # `wp-container-core-group-is-layout-2ab8c7fb`, and those three families of class name
    # are directly observable in the golden files. AD-01 removes the filter mechanism, so
    # the chain is implemented here as an explicit, ordered pass over the rendered markup
    # (`Supported#render`), with no way to add to it.
    #
    # ── Ports in this file, with the legacy source each came from ─────────────────────
    #   Php                 wp-includes/formatting.php:2282   sanitize_title (save context)
    #                       wp-includes/functions.php:8229    wp_unique_id_from_values
    #   GlobalStyles        wp-includes/global-styles-and-settings.php:53/111
    #   LayoutSupport       wp-includes/block-supports/layout.php:48…1482
    #   TypographySupport   wp-includes/block-supports/typography.php
    #   Group…Cover         wp-includes/blocks/<name>.php where one exists
    #
    # ⚠️ BOUNDARY. `Composition::Renderer.render_block` is a shared contract this agent may
    # not change, so the support pass runs only for the blocks registered below. In the
    # legacy it runs for EVERY block. `LayoutBlocks.apply_supports` is public precisely so
    # that the shared renderer, or another block family, can call it; see the report.
    module LayoutBlocks
      LEGACY_ROOT = ENV.fetch("LEGACY_ROOT", "/workspace/WordPress")

      # ────────────────────────────────────────────────────────────────────────────────
      # PHP primitives this file needs and the `styling` pack does not carry.
      # ────────────────────────────────────────────────────────────────────────────────
      module Php
        module_function

        # wp-includes/formatting.php:2237 `sanitize_title()` — note the DEFAULT CONTEXT IS
        # 'save', which is what layout.php relies on: `sanitize_title('core/group')` is
        # 'core-group', not 'coregroup', because the save branch converts `/` to `-`
        # BEFORE the `[^%a-z0-9 _-]` strip removes it (formatting.php:2306).
        #
        # ⚠️ REDUCED PORT. `remove_accents()`, `utf8_uri_encode()`, the HTML-entity pass and
        # the ~60 percent-encoded punctuation replacements are not implemented. Every value
        # this file passes in is ASCII — a block name, or a layout enum such as
        # `space-between` — and the reduction is asserted in the spec. A non-ASCII input
        # would diverge.
        def sanitize_title(title)
          t = title.to_s.downcase
          t = t.tr("/", "-").tr(".", "-")
          t = t.gsub(/[^%a-z0-9 _\-]/, "")
          t = t.gsub(/\s+/, "-")
          t = t.gsub(/-+/, "-")
          t.gsub(/\A-+|-+\z/, "")
        end

        # PHP's `json_encode($value)` with options 0, which is what `wp_json_encode()`
        # passes. Three differences from Ruby's `JSON.generate` and every one of them
        # changes the md5 below:
        #   * `/` is escaped as `\/`;
        #   * every non-ASCII character is escaped as `\uXXXX`, astral ones as a surrogate
        #     pair;
        #   * a PHP array with no elements encodes as `[]`, never `{}` — see `empty_list`.
        def json_encode(value)
          case value
          when nil then "null"
          when true then "true"
          when false then "false"
          when Integer then value.to_s
          when Float then float_repr(value)
          when String then json_string(value)
          when Symbol then json_string(value.to_s)
          when Array then "[#{value.map { |v| json_encode(v) }.join(",")}]"
          when Hash
            return "[]" if value.empty?

            "{#{value.map { |k, v| "#{json_string(k.to_s)}:#{json_encode(v)}" }.join(",")}}"
          else json_string(value.to_s)
          end
        end

        # PHP renders a float that is integral as `1.0`, not `1`, inside json_encode
        # (serialize_precision=-1 gives the shortest round-trip form, same as Ruby).
        def float_repr(value)
          return value.to_i.to_s if value.finite? && value == value.to_i && value.abs < 1e15

          value.to_s
        end

        def json_string(str)
          out = +'"'
          str.to_s.each_char do |ch|
            cp = ch.ord
            out << case ch
                   when '"' then '\\"'
                   when "\\" then "\\\\"
                   when "/" then "\\/"
                   when "\b" then '\b'
                   when "\f" then '\f'
                   when "\n" then '\n'
                   when "\r" then '\r'
                   when "\t" then '\t'
                   else
                     if cp < 0x20
                       format('\u%04x', cp)
                     elsif cp < 0x80
                       ch
                     elsif cp > 0xFFFF
                       v = cp - 0x10000
                       format('\u%04x\u%04x', 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                     else
                       format('\u%04x', cp)
                     end
                   end
          end
          out << '"'
        end

        # wp-includes/functions.php:8229 `wp_unique_id_from_values()`.
        def unique_id_from_values(data, prefix = "")
          "#{prefix}#{Digest::MD5.hexdigest(json_encode(data))[0, 8]}"
        end

        # PHP `empty()` over the shapes this file handles.
        def empty?(value)
          Styling::PhpCompat.php_empty?(value)
        end

        # PHP's `$a['x']['y'] ?? null` yields null when an intermediate level is a scalar;
        # Ruby's `Hash#dig` raises `TypeError` instead. `supports.spacing.blockGap` really
        # is `true` for core/group, so this is reached on the first real block.
        def dig(value, *path)
          path.each do |key|
            return nil unless value.is_a?(Hash)

            value = value[key]
          end
          value
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # The handful of resolved theme.json values the layout support reads.
      # ────────────────────────────────────────────────────────────────────────────────
      #
      # `wp_get_global_settings()` / `wp_get_global_styles()` are the whole theme.json
      # cascade (BR-MIGRATE-206…215). The `styling` pack ports the cascade's RULES but not
      # `WP_Theme_JSON::sanitize()` nor `do_opt_in_into_settings()`, so a faithful
      # `wp_get_global_settings()` does not exist yet in this rebuild.
      #
      # What the layout support actually reads is six values, so this module derives those
      # six — from the two theme.json files in the legacy tree, which are ASSETS the way
      # `style.min.css` is an asset, not behaviour to reinvent. Each derived value is
      # asserted against the live oracle in the spec.
      module GlobalStyles
        # wp-includes/class-wp-theme-json.php:1063 APPEARANCE_TOOLS_OPT_INS, the entries
        # that matter here: `settings.appearanceTools: true` opts the theme into
        # `spacing.blockGap`, which is what makes `$has_block_gap_support` true for a theme
        # whose own theme.json never mentions blockGap.
        APPEARANCE_TOOLS_OPT_INS = [
          %w[border color], %w[border radius], %w[border style], %w[border width],
          %w[color link], %w[color heading], %w[color button], %w[color caption],
          %w[dimensions aspectRatio], %w[dimensions minHeight], %w[position sticky],
          %w[spacing blockGap], %w[spacing margin], %w[spacing padding],
          %w[typography lineHeight]
        ].freeze

        class << self
          def core_theme_json
            @core_theme_json ||= read_json(File.join(LEGACY_ROOT, "wp-includes", "theme.json"))
          end

          def theme_theme_json
            @theme_theme_json ||=
              read_json(File.join(LEGACY_ROOT, "wp-content", "themes", "twentytwentyfive", "theme.json"))
          end

          # `settings`, merged core-then-theme and then opted in, which is the subset of
          # WP_Theme_JSON_Resolver::get_merged_data()->get_settings() this file reads.
          # ⚠️ ORDER IS LOAD-BEARING. `maybe_opt_in_into_settings()` runs on ONE ORIGIN'S
          # data at construction time (class-wp-theme-json.php:1220), i.e. on the theme's
          # own theme.json, and only then does the cascade merge origins. Core's
          # theme.json declares `settings.spacing.blockGap: null`; the theme's does not
          # declare it at all, so the opt-in writes `true` into the theme origin and the
          # merge lets it win. Opting in AFTER the merge would see core's explicit null,
          # leave it alone, and silently turn `$has_block_gap_support` off — which deletes
          # every `gap:` declaration from the block-supports stylesheet.
          def settings
            @settings ||= Styling::PhpCompat.array_replace_recursive(
              core_theme_json["settings"] || {},
              apply_appearance_tools(theme_theme_json["settings"] || {})
            )
          end

          # `styles`, merged and with the internal `var:preset|…` form already converted —
          # `WP_Theme_JSON::sanitize()` does that conversion (class-wp-theme-json.php:5788,
          # `resolve_custom_css_format`), and every consumer downstream sees the CSS form.
          def styles
            @styles ||= resolve_custom_css_format(
              Styling::PhpCompat.array_replace_recursive(
                core_theme_json["styles"] || {}, theme_theme_json["styles"] || {}
              )
            )
          end

          def use_root_padding_aware_alignments? = settings["useRootPaddingAwareAlignments"] == true

          # layout.php:1207 — `isset($block_gap)`, so a `false` here still counts.
          def has_block_gap_support? = !Styling::PhpCompat.array_get(settings, %w[spacing blockGap]).nil?

          def root_block_gap = Styling::PhpCompat.array_get(styles, %w[spacing blockGap])

          def block_gap_for(block_name)
            Styling::PhpCompat.array_get(styles, ["blocks", block_name.to_s, "spacing", "blockGap"])
          end

          # `WP_Theme_JSON::get_viewport_media_queries()` — the pack already ports it
          # (BR-MIGRATE-213); `settings.viewport` is absent for this theme, so the defaults
          # apply and the desktop query is excluded, exactly as layout.php calls it.
          def viewport_media_queries
            @viewport_media_queries ||= Styling::ThemeJson.viewport_media_queries(settings["viewport"])
          end

          def reset!
            @core_theme_json = @theme_theme_json = @settings = @styles = @viewport_media_queries = nil
          end

          private

          def read_json(path)
            File.exist?(path) ? JSON.parse(File.read(path)) : {}
          end

          # class-wp-theme-json.php:1224 `do_opt_in_into_settings()`, top level only.
          def apply_appearance_tools(settings)
            return settings unless settings["appearanceTools"] == true

            out = Styling::PhpCompat.deep_dup(settings)
            marker = Object.new
            APPEARANCE_TOOLS_OPT_INS.each do |path|
              # The legacy uses the sentinel string 'unset prop' rather than null here,
              # "because null can be a valid value for some props (e.g. blockGap)"
              # (class-wp-theme-json.php:1252). Same reason, same shape.
              next unless Styling::PhpCompat.array_get(out, path, marker).equal?(marker)

              Styling::PhpCompat.array_set(out, path, true)
            end
            out.delete("appearanceTools")
            out
          end

          # class-wp-theme-json.php:5600 `resolve_custom_css_format()`.
          def resolve_custom_css_format(tree)
            case tree
            when Hash then tree.transform_values { |v| resolve_custom_css_format(v) }
            when Array then tree.map { |v| resolve_custom_css_format(v) }
            when String
              tree.start_with?("var:") ? "var(--wp--#{tree[4..].gsub("|", "--")})" : tree
            else tree
            end
          end
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # The layout support — wp-includes/block-supports/layout.php.
      # ────────────────────────────────────────────────────────────────────────────────
      #
      # This is the support that produces ~all of the class-name delta between a block's
      # saved markup and the golden files: `is-layout-flex`, `is-content-justification-*`,
      # `wp-block-group-is-layout-flex`, `wp-container-core-group-is-layout-<hash>` and
      # `wp-container-content-<hash>`, plus the rules behind
      # `<style id="core-block-supports-inline-css">`.
      module LayoutSupport
        CHILD_LAYOUT_KEYS = %w[selfStretch flexSize columnStart columnSpan rowStart rowSpan].freeze

        # layout.php:284 `wp_get_layout_definitions()`. Only the two fields this file reads
        # are transcribed: `className`, which becomes a class name, and the `displayMode`
        # / `baseStyles` / `spacingStyles` trees, which 7.2-alpha uses only from
        # `WP_Theme_JSON::get_layout_styles()` — global styles, not this support. Adding
        # them here would be dead data, so the reduction is deliberate and noted.
        DEFINITIONS = {
          "default" => { "name" => "default", "slug" => "flow", "className" => "is-layout-flow" },
          "constrained" => { "name" => "constrained", "slug" => "constrained",
                             "className" => "is-layout-constrained" },
          "flex" => { "name" => "flex", "slug" => "flex", "className" => "is-layout-flex" },
          "grid" => { "name" => "grid", "slug" => "grid", "className" => "is-layout-grid" }
        }.freeze

        # layout.php:86 `wp_sanitize_block_gap_value()`. The character class is transcribed
        # BY VALUE, not by source text: PHP's single-quoted `'%[\\\(&=}]|/\*%'` collapses to
        # the class {\ ( & = }} plus the literal `/*`.
        UNSAFE_GAP = Regexp.new("[\\\\(&=}]|/\\*")

        class << self
          # layout.php:984 `wp_render_layout_support_flag()`.
          def render(block_content, block, ctx)
            block_type = Registry[block.block_name]
            supports_layout = block_has_support?(block_type, "layout") ||
                              block_has_support?(block_type, "__experimentalLayout")
            attrs = block.attrs || {}
            style_attr = attrs["style"].is_a?(Hash) ? attrs["style"] : {}

            # layout.php:997 — the early return exists in the legacy to break a recursion
            # through `the_posts`; here it is simply the cheapest correct answer.
            return block_content if !supports_layout && Php.empty?(style_attr)

            media_queries = GlobalStyles.viewport_media_queries
            child_layout = style_attr["layout"]

            viewport_child_layouts = {}
            media_queries.each do |breakpoint, media_query|
              viewport_child = layout_child_values(Php.dig(style_attr, breakpoint, "layout"))
              next if Php.empty?(viewport_child)

              viewport_child_layouts[breakpoint] =
                { "media_query" => media_query, "child_layout" => viewport_child }
            end

            if !supports_layout && Php.empty?(child_layout) && viewport_child_layouts.empty?
              return block_content
            end

            store = LayoutBlocks.block_supports_store(ctx)
            outer_class_names = []

            # ── child layout ────────────────────────────────────────────────────────
            if !Php.empty?(child_layout) || !viewport_child_layouts.empty?
              base_child_layout = layout_child_values(child_layout)
              parent_layout = ctx.context["layout.parentLayout"] || {}

              hash_input = {
                "layout" => base_child_layout,
                "parentLayout" => parent_layout.select { |k, _| %w[minimumColumnWidth columnCount].include?(k) }
              }
              viewport_child_layouts.each { |bp, data| hash_input[bp] = data["child_layout"] }

              container_content_class = Php.unique_id_from_values(hash_input, "wp-container-content-")

              child_styles = child_layout_style_rules(".#{container_content_class}",
                                                      base_child_layout, parent_layout)
              viewport_child_layouts.each_value do |data|
                extra = child_layout_style_rules(".#{container_content_class}", base_child_layout,
                                                 parent_layout, data["child_layout"])
                extra.each { |rule| rule["rules_group"] = data["media_query"] }
                child_styles += extra
              end

              child_css = Styling::StyleEngine.get_stylesheet_from_css_rules(
                child_styles, store: store, prettify: false
              )
              outer_class_names << container_content_class unless Php.empty?(child_css)
            end

            processor = Markup::TagProcessor.new(block_content)
            return block_content unless processor.next_tag

            if !supports_layout && !outer_class_names.empty?
              outer_class_names.each { |name| processor.add_class(name) }
              return processor.get_updated_html
            elsif !supports_layout
              return block_content
            end

            supports = block_type&.supports || {}
            fallback_layout = Php.dig(supports, "layout", "default")
            fallback_layout = Php.dig(supports, "__experimentalLayout", "default") if Php.empty?(fallback_layout)
            fallback_layout = {} if Php.empty?(fallback_layout)
            used_layout = attrs["layout"].is_a?(Hash) ? attrs["layout"].dup : fallback_layout.dup

            class_names = []

            if truthy(used_layout["inherit"]) || truthy(used_layout["contentSize"])
              used_layout["type"] = "constrained"
            end

            if GlobalStyles.use_root_padding_aware_alignments? && used_layout["type"] == "constrained"
              class_names << "has-global-padding"
            end

            # layout.php:1152 — "reintroduce a small set of layout classnames that were
            # removed in the 5.9 release". These read `attrs.layout`, NOT `used_layout`.
            orientation = Php.dig(attrs, "layout", "orientation")
            class_names << "is-#{Php.sanitize_title(orientation)}" if !Php.empty?(orientation) && orientation.is_a?(String)

            justify = Php.dig(attrs, "layout", "justifyContent")
            class_names << "is-content-justification-#{Php.sanitize_title(justify)}" if !Php.empty?(justify) && justify.is_a?(String)

            flex_wrap = Php.dig(attrs, "layout", "flexWrap")
            class_names << "is-nowrap" if !Php.empty?(flex_wrap) && flex_wrap == "nowrap"

            layout_classname =
              if used_layout["type"].is_a?(String)
                DEFINITIONS.dig(used_layout["type"], "className") || ""
              else
                DEFINITIONS.dig("default", "className") || ""
              end
            class_names << Php.sanitize_title(layout_classname) if layout_classname.is_a?(String) && !layout_classname.empty?

            # `current_theme_supports('disable-layout-styles')` is false for this theme, so
            # the branch is always taken. AD-01: there is no way to opt out.
            gap_value = sanitize_block_gap_value(Php.dig(style_attr, "spacing", "blockGap"))
            fallback_gap_value = Php.dig(supports, "spacing", "blockGap", "__experimentalDefault") || "0.5em"
            block_spacing = style_attr["spacing"]
            should_skip_gap = skip_serialization?(block_type, "spacing", "blockGap")
            has_block_gap_support = GlobalStyles.has_block_gap_support?

            # layout.php:1214 — the style-variation lookup above this is skipped: it needs
            # WP_Block_Styles_Registry, and no block in this family carries a variation
            # whose global styles declare a blockGap. Documented in the report.
            global_block_gap = GlobalStyles.block_gap_for(block.block_name) || GlobalStyles.root_block_gap
            fallback_gap_value = global_block_gap unless global_block_gap.nil?

            hash_input = [used_layout, has_block_gap_support, gap_value, should_skip_gap,
                          fallback_gap_value, block_spacing]

            media_queries.each_key do |breakpoint|
              viewport_style = style_attr[breakpoint]
              next unless viewport_style.is_a?(Hash)

              viewport_container_layout = layout_container_values(viewport_style["layout"])
              unless Php.empty?(viewport_container_layout)
                hash_input << { "breakpoint" => breakpoint, "layout" => viewport_container_layout }
              end
              next unless Php.dig(viewport_style, "spacing", "blockGap")

              hash_input << { "breakpoint" => breakpoint,
                              "blockGap" => sanitize_block_gap_value(Php.dig(viewport_style, "spacing", "blockGap")) }
            end

            container_class = Php.unique_id_from_values(
              hash_input, "wp-container-#{Php.sanitize_title(block.block_name)}-is-layout-"
            )

            style = layout_style(".#{container_class}", used_layout, has_block_gap_support, gap_value,
                                 should_skip_gap, fallback_gap_value, block_spacing, {}, store)

            media_queries.each do |breakpoint, media_query|
              viewport_style = style_attr[breakpoint]
              next unless viewport_style.is_a?(Hash)

              viewport_container_layout = layout_container_values(viewport_style["layout"])
              has_viewport_layout = !Php.empty?(viewport_container_layout)
              has_viewport_block_gap = !Php.dig(viewport_style, "spacing", "blockGap").nil?
              next if !has_viewport_layout && !has_viewport_block_gap

              viewport_gap_value = has_viewport_block_gap ? sanitize_block_gap_value(Php.dig(viewport_style, "spacing", "blockGap")) : gap_value
              viewport_block_spacing =
                if viewport_style["spacing"].is_a?(Hash)
                  (block_spacing.is_a?(Hash) ? block_spacing : {}).merge(viewport_style["spacing"])
                else
                  block_spacing
                end

              viewport_styles = layout_style(".#{container_class}", used_layout, has_block_gap_support,
                                             viewport_gap_value, should_skip_gap, fallback_gap_value,
                                             viewport_block_spacing,
                                             { "rules_group" => media_query,
                                               "viewport_overrides" => viewport_container_layout,
                                               "has_block_gap_override" => has_viewport_block_gap },
                                             store)
              class_names << container_class if !Php.empty?(viewport_styles) && !class_names.include?(container_class)
            end

            class_names << container_class unless Php.empty?(style)

            split = block.block_name.to_s.split("/")
            full_block_name = split[0] == "core" ? split.last : split.join("-")
            class_names << "wp-block-#{full_block_name}-#{layout_classname}"

            outer_class_names.each { |name| processor.add_class(name) }

            inner_block_wrapper_classes = inner_wrapper_classes(block)

            # layout.php:1434 — advance to the tag whose class attribute CONTAINS the saved
            # inner-wrapper classes, so the layout classes land on the element that wraps
            # the inner blocks rather than on the outer wrapper.
            loop do
              break if inner_block_wrapper_classes.nil? || inner_block_wrapper_classes.empty?

              class_attribute = processor.get_attribute("class")
              break if class_attribute.is_a?(String) && class_attribute.include?(inner_block_wrapper_classes)
              break unless processor.next_tag
            end

            class_names.each { |name| processor.add_class(name) }
            processor.get_updated_html
          end

          # layout.php:48 `wp_get_layout_child_values()`.
          def layout_child_values(layout)
            return {} unless layout.is_a?(Hash)

            layout.select { |k, _| CHILD_LAYOUT_KEYS.include?(k) }
          end

          # layout.php:67 `wp_get_layout_container_values()`.
          def layout_container_values(layout)
            return {} unless layout.is_a?(Hash)

            layout.reject { |k, _| CHILD_LAYOUT_KEYS.include?(k) }
          end

          # layout.php:86 `wp_sanitize_block_gap_value()`.
          def sanitize_block_gap_value(gap_value)
            if gap_value.is_a?(Hash)
              return gap_value.transform_values do |value|
                if !Styling::PhpCompat.php_scalar?(value) ||
                   (truthy(value) && Styling::PhpCompat.to_php_string(value).match?(UNSAFE_GAP))
                  nil
                else
                  value
                end
              end
            end

            truthy(gap_value) && gap_value.to_s.match?(UNSAFE_GAP) ? nil : gap_value
          end

          # blocks.php:2732 `block_has_support()`, single-key form.
          def block_has_support?(block_type, feature, default_value = false)
            support = default_value
            support = block_type.supports[feature] if block_type && block_type.supports.key?(feature)
            support == true || support.is_a?(Hash) || support.is_a?(Array)
          end

          # block-supports/utils.php:22 `wp_should_skip_block_supports_serialization()`.
          def skip_serialization?(block_type, feature_set, feature = nil)
            return false if block_type.nil? || Php.empty?(feature_set)

            skip = Styling::PhpCompat.array_get(block_type.supports, [feature_set, "__experimentalSkipSerialization"], false)
            return skip.include?(feature) if skip.is_a?(Array)

            skip == true
          end

          # PHP truthiness for the scalars that reach these branches.
          def truthy(value)
            !(value.nil? || value == false || value == "" || value == 0 || value == "0" ||
              (value.respond_to?(:empty?) && value.empty?))
          end

          # layout.php:511 `wp_get_layout_style()`. Returns the compiled stylesheet for
          # THIS block's container class and, as a side effect, stores the rules in the
          # `block-supports` store so the page can print them once.
          def layout_style(selector, layout, has_block_gap_support, gap_value, should_skip_gap,
                           fallback_gap_value, block_spacing, options, store)
            base_layout = layout.is_a?(Hash) ? layout : {}
            # PHP's `$options['viewport_overrides'] ?? null`: an EMPTY array is still an
            # array, so `null === $viewport_overrides` stays false and every
            # `$should_output_*` below flips to the viewport branch. `{}` must therefore
            # NOT be collapsed to nil here.
            viewport_overrides = options["viewport_overrides"]
            layout_for_styles = viewport_overrides.nil? ? base_layout : base_layout.merge(viewport_overrides)
            layout_type = base_layout["type"] || "default"
            rules_group = options["rules_group"]
            has_block_gap_override = truthy(options["has_block_gap_override"])
            should_output_block_gap = viewport_overrides.nil? || has_block_gap_override
            override = ->(property) { viewport_overrides.key?(property) }

            layout_styles = []

            case layout_type
            when "default"
              layout_styles.concat(flow_gap_rules(selector, gap_value, has_block_gap_support,
                                                  should_output_block_gap, should_skip_gap))
            when "constrained"
              content_size = layout_for_styles["contentSize"].is_a?(String) ? layout_for_styles["contentSize"] : ""
              wide_size = layout_for_styles["wideSize"].is_a?(String) ? layout_for_styles["wideSize"] : ""
              justify_content = layout_for_styles["justifyContent"].is_a?(String) ? layout_for_styles["justifyContent"] : "center"

              has_justify_override = !viewport_overrides.nil? && override.call("justifyContent")
              has_content_size_override = !viewport_overrides.nil? && override.call("contentSize")
              has_wide_size_override = !viewport_overrides.nil? && override.call("wideSize")

              should_output_constrained_sizes = viewport_overrides.nil? || has_content_size_override || has_wide_size_override
              is_resetting = !viewport_overrides.nil? &&
                             ((has_content_size_override && !truthy(content_size)) ||
                              (has_wide_size_override && !truthy(wide_size)))

              all_max_width = if truthy(content_size)
                                content_size
                              elsif truthy(wide_size) && !has_content_size_override
                                wide_size
                              else
                                "var(--wp--style--global--content-size, none)"
                              end
              wide_max_width = if truthy(wide_size)
                                 wide_size
                               elsif truthy(content_size) && !has_wide_size_override
                                 content_size
                               else
                                 "var(--wp--style--global--wide-size, none)"
                               end
              all_max_width = Styling::CssSafety.safecss_filter_attr(all_max_width.split(";", -1).first.to_s)
              wide_max_width = Styling::CssSafety.safecss_filter_attr(wide_max_width.split(";", -1).first.to_s)

              margin_left = justify_content == "left" ? "0 !important" : "auto !important"
              margin_right = justify_content == "right" ? "0 !important" : "auto !important"

              if should_output_constrained_sizes && (truthy(content_size) || truthy(wide_size) || is_resetting)
                declarations = { "max-width" => all_max_width }
                if viewport_overrides.nil? || has_justify_override
                  declarations["margin-left"] = margin_left
                  declarations["margin-right"] = margin_right
                end
                layout_styles << { "selector" => "#{selector} > :where(:not(.alignleft):not(.alignright):not(.alignfull))",
                                   "declarations" => declarations }
                layout_styles << { "selector" => "#{selector} > .alignwide",
                                   "declarations" => { "max-width" => wide_max_width } }
                layout_styles << { "selector" => "#{selector} .alignfull",
                                   "declarations" => { "max-width" => "none" } }
              end

              if viewport_overrides.nil? && !block_spacing.nil?
                spacing_values = Styling::StyleEngine.get_styles({ "spacing" => block_spacing })
                padding_right = Php.dig(spacing_values, "declarations", "padding-right")
                unless padding_right.nil?
                  padding_right = "0px" if padding_right == "0"
                  layout_styles << { "selector" => "#{selector} > .alignfull",
                                     "declarations" => { "margin-right" => "calc(#{padding_right} * -1)" } }
                end
                padding_left = Php.dig(spacing_values, "declarations", "padding-left")
                unless padding_left.nil?
                  padding_left = "0px" if padding_left == "0"
                  layout_styles << { "selector" => "#{selector} > .alignfull",
                                     "declarations" => { "margin-left" => "calc(#{padding_left} * -1)" } }
                end
              end

              if has_justify_override && !should_output_constrained_sizes
                layout_styles << { "selector" => "#{selector} > :where(:not(.alignleft):not(.alignright):not(.alignfull))",
                                   "declarations" => { "margin-left" => margin_left, "margin-right" => margin_right } }
              elsif viewport_overrides.nil?
                if justify_content == "left"
                  layout_styles << { "selector" => "#{selector} > :where(:not(.alignleft):not(.alignright):not(.alignfull))",
                                     "declarations" => { "margin-left" => "0 !important" } }
                end
                if justify_content == "right"
                  layout_styles << { "selector" => "#{selector} > :where(:not(.alignleft):not(.alignright):not(.alignfull))",
                                     "declarations" => { "margin-right" => "0 !important" } }
                end
              end

              layout_styles.concat(flow_gap_rules(selector, gap_value, has_block_gap_support,
                                                  should_output_block_gap, should_skip_gap))
            when "flex"
              orientation = layout_for_styles["orientation"] || "horizontal"
              justify_options = { "left" => "flex-start", "right" => "flex-end", "center" => "center" }
              vertical_options = { "top" => "flex-start", "center" => "center", "bottom" => "flex-end" }
              if orientation == "horizontal"
                justify_options["space-between"] = "space-between"
                vertical_options["stretch"] = "stretch"
              else
                justify_options["stretch"] = "stretch"
                vertical_options["space-between"] = "space-between"
              end

              output_wrap = viewport_overrides.nil? || override.call("flexWrap")
              output_orientation = viewport_overrides.nil? || override.call("orientation")
              output_justification = viewport_overrides.nil? || override.call("justifyContent") || override.call("orientation")
              output_alignment = viewport_overrides.nil? || override.call("verticalAlignment") || override.call("orientation")

              if output_wrap && truthy(layout_for_styles["flexWrap"]) && layout_for_styles["flexWrap"] == "nowrap"
                layout_styles << { "selector" => selector, "declarations" => { "flex-wrap" => "nowrap" } }
              end

              if has_block_gap_support && should_output_block_gap && !gap_value.nil?
                gap_value = combined_gap_value(gap_value, fallback_gap_value)
                if !gap_value.nil? && !should_skip_gap
                  layout_styles << { "selector" => selector, "declarations" => { "gap" => gap_value } }
                end
              end

              flex_justify = layout_for_styles["justifyContent"]
              flex_vertical = layout_for_styles["verticalAlignment"]

              if orientation == "horizontal"
                if output_justification && truthy(flex_justify) && flex_justify.is_a?(String) && justify_options.key?(flex_justify)
                  layout_styles << { "selector" => selector,
                                     "declarations" => { "justify-content" => justify_options[flex_justify] } }
                end
                if output_alignment && truthy(flex_vertical) && flex_vertical.is_a?(String) && vertical_options.key?(flex_vertical)
                  layout_styles << { "selector" => selector,
                                     "declarations" => { "align-items" => vertical_options[flex_vertical] } }
                end
              else
                if output_orientation
                  layout_styles << { "selector" => selector, "declarations" => { "flex-direction" => "column" } }
                end
                if output_justification && truthy(flex_justify) && flex_justify.is_a?(String) && justify_options.key?(flex_justify)
                  layout_styles << { "selector" => selector,
                                     "declarations" => { "align-items" => justify_options[flex_justify] } }
                elsif output_justification
                  layout_styles << { "selector" => selector, "declarations" => { "align-items" => "flex-start" } }
                end
                if output_alignment && truthy(flex_vertical) && flex_vertical.is_a?(String) && vertical_options.key?(flex_vertical)
                  layout_styles << { "selector" => selector,
                                     "declarations" => { "justify-content" => vertical_options[flex_vertical] } }
                end
              end
            when "grid"
              layout_styles.concat(grid_rules(selector, base_layout, layout_for_styles, gap_value,
                                              fallback_gap_value, has_block_gap_support,
                                              should_output_block_gap, should_skip_gap,
                                              has_block_gap_override, viewport_overrides, override))
            end

            return "" if Php.empty?(layout_styles)

            unless Php.empty?(rules_group)
              layout_styles.each { |rule| rule["rules_group"] = rules_group }
            end

            Styling::StyleEngine.get_stylesheet_from_css_rules(layout_styles, store: store, prettify: false)
          end

          # The `default` and `constrained` block-gap rules are byte-identical in the
          # legacy (layout.php:534 and layout.php:690); factored, not paraphrased.
          def flow_gap_rules(selector, gap_value, has_block_gap_support, should_output_block_gap, should_skip_gap)
            return [] unless has_block_gap_support && should_output_block_gap

            gap_value = gap_value["top"] if gap_value.is_a?(Hash)
            return [] if gap_value.nil? || should_skip_gap

            gap_value = preset_to_var(gap_value)
            [
              { "selector" => "#{selector} > *",
                "declarations" => { "margin-block-start" => "0", "margin-block-end" => "0" } },
              { "selector" => "#{selector} > * + *",
                "declarations" => { "margin-block-start" => gap_value, "margin-block-end" => "0" } }
            ]
          end

          # layout.php:539 — `var:preset|spacing|<slug>` becomes the custom property. The
          # slug is taken after the LAST pipe and kebab-cased.
          def preset_to_var(value)
            return value unless value.is_a?(String) && value.include?("var:preset|spacing|")

            slug = Styling::PhpCompat.to_kebab_case(value[(value.rindex("|") + 1)..])
            "var(--wp--preset--spacing--#{slug})"
          end

          # layout.php:770 / :874 — the flex and grid gap shorthand.
          def combined_gap_value(gap_value, fallback_gap_value)
            combined = +""
            gap_sides = gap_value.is_a?(Hash) ? %w[top left] : %w[top]
            gap_sides.each do |side|
              process_value = gap_value
              if gap_value.is_a?(Hash)
                fallback = if fallback_gap_value.is_a?(Hash)
                             fallback_gap_value[side] || fallback_gap_value.values.first
                           else
                             fallback_gap_value
                           end
                process_value = gap_value.key?(side) && !gap_value[side].nil? ? gap_value[side] : fallback
              end
              combined << "#{preset_to_var(process_value)} "
            end
            combined.strip
          end

          def grid_rules(selector, base_layout, layout_for_styles, gap_value, fallback_gap_value,
                         has_block_gap_support, should_output_block_gap, should_skip_gap,
                         has_block_gap_override, viewport_overrides, override)
            styles = []
            column_count = numeric_int(layout_for_styles["columnCount"])
            row_count = numeric_int(layout_for_styles["rowCount"])

            responsive_gap_value = if fallback_gap_value.is_a?(Hash)
                                     fallback_gap_value["left"] || fallback_gap_value.values.first
                                   else
                                     fallback_gap_value
                                   end

            if has_block_gap_support && !gap_value.nil?
              gap_value = combined_gap_value(gap_value, fallback_gap_value)
              responsive_gap_value = gap_value
            end
            responsive_gap_value = "0px" if responsive_gap_value == "0" || responsive_gap_value == 0

            should_output_grid_columns = viewport_overrides.nil? || override.call("minimumColumnWidth") ||
                                         override.call("columnCount") || override.call("autoFit")
            uses_gap_in_grid_columns = truthy(column_count) && truthy(layout_for_styles["minimumColumnWidth"])
            should_output_grid_columns = true if has_block_gap_override && uses_gap_in_grid_columns

            should_output_grid_rows = (viewport_overrides.nil? || override.call("rowCount")) &&
                                      truthy(column_count) && truthy(row_count)
            grid_declarations = {}
            auto_placement = truthy(layout_for_styles["autoFit"]) ? "auto-fit" : "auto-fill"

            if should_output_grid_columns && truthy(column_count) && truthy(layout_for_styles["minimumColumnWidth"])
              max_value = "max(min(#{layout_for_styles["minimumColumnWidth"]}, 100%), (100% - (#{responsive_gap_value} * (#{column_count} - 1))) /#{column_count})"
              grid_declarations["grid-template-columns"] = "repeat(#{auto_placement}, minmax(#{max_value}, 1fr))"
            elsif should_output_grid_columns && truthy(column_count)
              grid_declarations["grid-template-columns"] = "repeat(#{column_count}, minmax(0, 1fr))"
            elsif should_output_grid_columns
              minimum_column_width = truthy(layout_for_styles["minimumColumnWidth"]) ? layout_for_styles["minimumColumnWidth"] : "12rem"
              grid_declarations["grid-template-columns"] = "repeat(#{auto_placement}, minmax(min(#{minimum_column_width}, 100%), 1fr))"
            end

            unless grid_declarations.empty?
              base_has_container_type = !truthy(base_layout["columnCount"]) ||
                                        (truthy(base_layout["columnCount"]) && truthy(base_layout["minimumColumnWidth"]))
              if !truthy(column_count) || truthy(layout_for_styles["minimumColumnWidth"])
                if viewport_overrides.nil? || !base_has_container_type
                  grid_declarations["container-type"] = "inline-size"
                end
              end
              styles << { "selector" => selector, "declarations" => grid_declarations }
            end

            if should_output_grid_rows
              styles << { "selector" => selector,
                          "declarations" => { "grid-template-rows" => "repeat(#{row_count}, minmax(1rem, auto))" } }
            end

            if has_block_gap_support && should_output_block_gap && !gap_value.nil? && !should_skip_gap
              styles << { "selector" => selector, "declarations" => { "gap" => gap_value } }
            end
            styles
          end

          # layout.php:109 `wp_get_child_layout_style_rules()`.
          def child_layout_style_rules(selector, child_layout, parent_layout = {}, viewport_overrides = nil)
            base_child_layout = child_layout.is_a?(Hash) ? child_layout : {}
            viewport_overrides = nil unless viewport_overrides.is_a?(Hash)
            child_layout = viewport_overrides.nil? ? base_child_layout : base_child_layout.merge(viewport_overrides)
            declarations = {}
            styles = []
            override = ->(property) { viewport_overrides.key?(property) }

            self_stretch = child_layout["selfStretch"]
            base_self_stretch = base_child_layout["selfStretch"]
            flex_size_values = %w[fixed fixedNoShrink]

            if viewport_overrides.nil? || override.call("selfStretch") || override.call("flexSize")
              if !viewport_overrides.nil? && %w[fit fill].include?(self_stretch) &&
                 flex_size_values.include?(base_self_stretch) && !base_child_layout["flexSize"].nil?
                declarations["flex-basis"] = "unset"
                declarations["flex-shrink"] = "unset" if base_self_stretch == "fixedNoShrink"
              end
              if flex_size_values.include?(self_stretch) && !child_layout["flexSize"].nil?
                declarations["flex-basis"] = child_layout["flexSize"]
                if self_stretch == "fixedNoShrink"
                  declarations["flex-shrink"] = "0"
                elsif !viewport_overrides.nil? && base_self_stretch == "fixedNoShrink"
                  declarations["flex-shrink"] = "unset"
                end
                declarations["box-sizing"] = "border-box"
              elsif self_stretch == "fill"
                declarations["flex-grow"] = "1"
              end
            end

            column_start = numeric_int(child_layout["columnStart"])
            column_span = numeric_int(child_layout["columnSpan"])
            if viewport_overrides.nil? || override.call("columnStart") || override.call("columnSpan")
              if truthy(column_start) && truthy(column_span)
                declarations["grid-column"] = "#{column_start} / span #{column_span}"
              elsif truthy(column_start)
                declarations["grid-column"] = column_start.to_s
              elsif truthy(column_span)
                declarations["grid-column"] = "span #{column_span}"
              end
            end

            row_start = numeric_int(child_layout["rowStart"])
            row_span = numeric_int(child_layout["rowSpan"])
            if viewport_overrides.nil? || override.call("rowStart") || override.call("rowSpan")
              if truthy(row_start) && truthy(row_span)
                declarations["grid-row"] = "#{row_start} / span #{row_span}"
              elsif truthy(row_start)
                declarations["grid-row"] = row_start.to_s
              elsif truthy(row_span)
                declarations["grid-row"] = "span #{row_span}"
              end
            end

            styles << { "selector" => selector, "declarations" => declarations } unless declarations.empty?

            minimum_column_width = parent_layout["minimumColumnWidth"].is_a?(String) ? parent_layout["minimumColumnWidth"] : nil
            column_count = parent_layout["columnCount"]

            if viewport_overrides.nil? && (truthy(column_span) || truthy(column_start)) &&
               (truthy(minimum_column_width) || !truthy(column_count))
              column_span_number = php_floatval(column_span)
              column_start_number = php_floatval(column_start)
              parent_column_width = minimum_column_width || "12rem"
              parent_column_value = php_floatval(parent_column_width)
              # PHP `explode($parent_column_value, $parent_column_width)` splits on the
              # STRING form of the float, which is how the unit gets separated from the
              # number; `explode` casts its first argument to string.
              parts = parent_column_width.split(Styling::PhpCompat.to_php_string(parent_column_value), -1)

              num_cols_to_break_at = if truthy(column_span_number) && truthy(column_start_number)
                                       column_start_number + column_span_number - 1
                                     elsif truthy(column_span_number)
                                       column_span_number
                                     else
                                       column_start_number
                                     end

              if parts.length <= 1
                parent_column_unit = "rem"
                parent_column_value = 12
              else
                parent_column_unit = parts[1]
                parent_column_unit = "rem" unless %w[px rem em].include?(parent_column_unit)
              end

              default_gap_value = parent_column_unit == "px" ? 24 : 1.5
              container_query_value = num_cols_to_break_at * parent_column_value +
                                      (num_cols_to_break_at - 1) * default_gap_value
              minimum_container_query_value = parent_column_value * 2 + default_gap_value - 1
              container_query_value = "#{Styling::PhpCompat.to_php_string([container_query_value, minimum_container_query_value].max)}#{parent_column_unit}"
              grid_column_value = truthy(column_span) && column_span > 1 ? "1/-1" : "auto"

              styles << { "rules_group" => "@container (max-width: #{container_query_value} )",
                          "selector" => selector,
                          "declarations" => { "grid-column" => grid_column_value, "grid-row" => "auto" } }
            end

            styles
          end

          # PHP `is_numeric($v) ? (int) $v : null` — content saved by WordPress 6.3…6.6
          # stored grid line numbers as numeric STRINGS and the front end still sees them.
          def numeric_int(value)
            return value.to_i if value.is_a?(Numeric)
            return value.strip.to_i if value.is_a?(String) && Styling::PhpCompat.php_numeric?(value)

            nil
          end

          def php_floatval(value)
            return 0.0 if value.nil?
            return value.to_f if value.is_a?(Numeric)

            value.to_s[/\A\s*[+-]?(\d+\.?\d*([eE][+-]?\d+)?|\.\d+([eE][+-]?\d+)?)/].to_f
          end

          private

          # layout.php:1381 — find the element that wraps the inner blocks by the class
          # attribute the SAVED markup gave it. The stack exists so that a sibling which
          # opens and closes inside the first chunk is not mistaken for the wrapper.
          def inner_wrapper_classes(block)
            first_chunk = block.inner_content&.first
            return nil unless first_chunk.is_a?(String) && block.inner_content.length > 1

            chunk_processor = Markup::TagProcessor.new(first_chunk)
            tag_stack = []
            while chunk_processor.next_tag({ tag_closers: "visit" })
              if chunk_processor.tag_closer?
                tag_stack.pop
              elsif !Markup::Processor.void?(chunk_processor.get_tag)
                tag_stack << chunk_processor.get_attribute("class")
              end
            end
            tag_stack.reverse.find { |c| c.is_a?(String) && !c.empty? }
          end
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # The typography support — wp-includes/block-supports/typography.php:306.
      # ────────────────────────────────────────────────────────────────────────────────
      #
      # Only the FLUID FONT SIZE half fires on a static block: everything else typography
      # contributes (`has-x-large-font-size`, `style="font-style:…"`) is already in the
      # saved markup, written by the editor. What the server does is REWRITE the literal
      # `font-size:9.6rem` the editor saved into the `clamp()` the theme asked for.
      module TypographySupport
        # typography.php:614 — the defaults, and the two the theme's settings override.
        DEFAULT_MAXIMUM_VIEWPORT_WIDTH = "1600px"
        DEFAULT_MINIMUM_VIEWPORT_WIDTH = "320px"
        MINIMUM_FONT_SIZE_FACTOR_MAX = 0.75
        MINIMUM_FONT_SIZE_FACTOR_MIN = 0.25
        DEFAULT_SCALE_FACTOR = 1
        DEFAULT_MINIMUM_FONT_SIZE_LIMIT = "14px"
        ACCEPTABLE_UNITS = %w[rem px em].freeze

        class << self
          def render(block_content, block, _ctx)
            attrs = block.attrs || {}
            # typography.php:307 — `fitText` supersedes everything else. No block in this
            # family carries it in the corpus; the branch is recorded, not ported, because
            # it emits Interactivity API directives that belong to another wave.
            return block_content if Php.dig(attrs, "fitText")

            custom_font_size = Php.dig(attrs, "style", "typography", "fontSize")
            return block_content if custom_font_size.nil?

            fluid = font_size_value(custom_font_size)
            return block_content if Php.empty?(fluid) || fluid == custom_font_size

            # typography.php:339 — first occurrence only.
            block_content.sub(/font-size\s*:\s*#{Regexp.escape(custom_font_size.to_s)}\s*;?/,
                              "font-size:#{fluid};")
          end

          # typography.php:565 `wp_get_typography_font_size_value()`, non-preset path.
          # The preset path (`$preset['fluid']` as an array with explicit min/max) is not
          # reachable from a block attribute — it exists for theme.json font-size presets.
          def font_size_value(size)
            return size if Php.empty?(size)

            settings = GlobalStyles.settings
            typography_settings = settings["typography"] || {}
            return size if Php.empty?(typography_settings["fluid"])

            fluid_settings = typography_settings["fluid"]
            # `settings.typography.fluid` is `true` for this theme, and PHP's `$true['k']`
            # is null rather than an error, so every lookup below falls to its default.
            fluid_settings = {} unless fluid_settings.is_a?(Hash)
            layout_settings = settings["layout"] || {}

            minimum_viewport_width = fluid_settings["minViewportWidth"] || DEFAULT_MINIMUM_VIEWPORT_WIDTH
            maximum_viewport_width =
              if layout_settings["wideSize"] && !Php.empty?(value_and_unit(layout_settings["wideSize"]))
                layout_settings["wideSize"]
              else
                DEFAULT_MAXIMUM_VIEWPORT_WIDTH
              end
            maximum_viewport_width = fluid_settings["maxViewportWidth"] if fluid_settings.key?("maxViewportWidth")

            has_min_font_size = fluid_settings.key?("minFontSize") &&
                                !Php.empty?(value_and_unit(fluid_settings["minFontSize"]))
            minimum_font_size_limit = has_min_font_size ? fluid_settings["minFontSize"] : DEFAULT_MINIMUM_FONT_SIZE_LIMIT

            minimum_font_size_raw = nil
            maximum_font_size_raw = nil

            preferred_size = value_and_unit(size)
            return size if preferred_size.nil? || Php.empty?(preferred_size["unit"])

            minimum_font_size_limit = value_and_unit(minimum_font_size_limit, coerce_to: preferred_size["unit"])

            if !Php.empty?(minimum_font_size_limit) && !minimum_font_size_raw && !maximum_font_size_raw
              return size if preferred_size["value"] <= minimum_font_size_limit["value"]
            end

            maximum_font_size_raw ||= "#{num(preferred_size["value"])}#{preferred_size["unit"]}"

            unless minimum_font_size_raw
              preferred_in_px = preferred_size["unit"] == "px" ? preferred_size["value"] : preferred_size["value"] * 16
              factor = clamp(1 - (0.075 * Math.log2(preferred_in_px)),
                             MINIMUM_FONT_SIZE_FACTOR_MIN, MINIMUM_FONT_SIZE_FACTOR_MAX)
              calculated = Styling::ThemeJson.php_round(preferred_size["value"] * factor, 3)
              minimum_font_size_raw =
                if !Php.empty?(minimum_font_size_limit) && calculated <= minimum_font_size_limit["value"]
                  "#{num(minimum_font_size_limit["value"])}#{minimum_font_size_limit["unit"]}"
                else
                  "#{num(calculated)}#{preferred_size["unit"]}"
                end
            end

            computed = computed_fluid_value(minimum_viewport_width, maximum_viewport_width,
                                            minimum_font_size_raw, maximum_font_size_raw,
                                            DEFAULT_SCALE_FACTOR)
            Php.empty?(computed) ? size : computed
          end

          # typography.php:464 `wp_get_computed_fluid_typography_value()`.
          def computed_fluid_value(min_viewport_raw, max_viewport_raw, min_font_raw, max_font_raw, scale_factor)
            minimum_font_size = value_and_unit(min_font_raw)
            font_size_unit = minimum_font_size&.fetch("unit", nil) || "rem"
            maximum_font_size = value_and_unit(max_font_raw, coerce_to: font_size_unit)
            return nil if maximum_font_size.nil? || minimum_font_size.nil?

            minimum_font_size_rem = value_and_unit(min_font_raw, coerce_to: "rem")
            maximum_viewport_width = value_and_unit(max_viewport_raw, coerce_to: font_size_unit)
            minimum_viewport_width = value_and_unit(min_viewport_raw, coerce_to: font_size_unit)
            return nil if minimum_viewport_width.nil? || maximum_viewport_width.nil?

            denominator = maximum_viewport_width["value"] - minimum_viewport_width["value"]
            return nil if Php.empty?(denominator)

            offset = "#{num(Styling::ThemeJson.php_round(minimum_viewport_width["value"] / 100, 3))}#{font_size_unit}"
            linear_factor = 100 * ((maximum_font_size["value"] - minimum_font_size["value"]) / denominator)
            linear_factor_scaled = Styling::ThemeJson.php_round(linear_factor * scale_factor, 3)
            linear_factor_scaled = 1 if Php.empty?(linear_factor_scaled)
            target = "#{num(minimum_font_size_rem["value"])}#{minimum_font_size_rem["unit"]} + " \
                     "((1vw - #{offset}) * #{num(linear_factor_scaled)})"

            "clamp(#{min_font_raw}, #{target}, #{max_font_raw})"
          end

          # typography.php:368 `wp_get_typography_value_and_unit()`.
          def value_and_unit(raw_value, coerce_to: "", root_size_value: 16)
            return nil unless raw_value.is_a?(String) || raw_value.is_a?(Numeric)
            return nil if Php.empty?(raw_value)

            raw_value = "#{num(raw_value)}px" if raw_value.is_a?(Numeric)
            match = raw_value.to_s.match(/\A(\d*\.?\d+)([a-zA-Z]+|%)\z/)
            return nil if match.nil?

            value = match[1].to_f
            unit = match[2]
            return nil unless ACCEPTABLE_UNITS.include?(unit)

            if coerce_to == "px" && %w[em rem].include?(unit)
              value *= root_size_value
              unit = coerce_to
            end
            if unit == "px" && %w[em rem].include?(coerce_to)
              value /= root_size_value
              unit = coerce_to
            end
            unit = coerce_to if %w[em rem].include?(coerce_to) && %w[em rem].include?(unit)

            { "value" => Styling::ThemeJson.php_round(value, 3), "unit" => unit }
          end

          # PHP's `clamp()` polyfill, wp-includes/compat.php:715.
          def clamp(value, min, max) = [[value, min].max, max].min

          # PHP renders `(string) 9.6` as "9.6" and `(string) 1.0` as "1".
          def num(value) = Styling::PhpCompat.to_php_string(value)
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # The dimensions support — wp-includes/block-supports/dimensions.php:120.
      # ────────────────────────────────────────────────────────────────────────────────
      module DimensionsSupport
        class << self
          def render(block_content, block, _ctx)
            block_type = Registry[block.block_name]
            attrs = (block.attrs.is_a?(Hash) ? block.attrs : {})
            has_support = block_has_support_path?(block_type, %w[dimensions aspectRatio])
            return block_content if !has_support ||
                                    LayoutSupport.skip_serialization?(block_type, "dimensions", "aspectRatio")

            styles_in = {}
            styles_in["aspectRatio"] = Php.dig(attrs, "style", "dimensions", "aspectRatio")

            if explicit_aspect_ratio?(styles_in["aspectRatio"])
              # dimensions.php:135 — "ensure the aspect ratio does not get overridden by
              # `minHeight` or `height`".
              styles_in["minHeight"] = "unset"
              styles_in["height"] = "unset"
            elsif !Php.dig(attrs, "style", "dimensions", "minHeight").nil? || !attrs["minHeight"].nil?
              styles_in["aspectRatio"] = "unset"
            end

            styles = Styling::StyleEngine.get_styles({ "dimensions" => styles_in })
            return block_content if Php.empty?(styles["css"])

            tags = Markup::TagProcessor.new(block_content)
            return block_content unless tags.next_tag

            existing_style = tags.get_attribute("style")
            updated_style = +""
            unless Php.empty?(existing_style)
              updated_style << existing_style
              updated_style << ";" unless existing_style.end_with?(";")
            end
            updated_style << styles["css"]
            tags.set_attribute("style", updated_style)

            unless Php.empty?(styles["classnames"])
              styles["classnames"].split(" ").each do |class_name|
                next if class_name.include?("aspect-ratio") &&
                        !explicit_aspect_ratio?(Php.dig(attrs, "style", "dimensions", "aspectRatio"))

                tags.add_class(class_name)
              end
            end
            tags.get_updated_html
          end

          # dimensions.php:95 `wp_is_explicit_aspect_ratio_value()`.
          def explicit_aspect_ratio?(aspect_ratio)
            return false unless aspect_ratio.is_a?(String) || aspect_ratio.is_a?(Numeric)

            value = aspect_ratio.to_s.strip.downcase(:ascii)
            value != "" && value != "auto"
          end

          # blocks.php:2732 `block_has_support()`, ARRAY form.
          def block_has_support_path?(block_type, path, default_value = false)
            return default_value if block_type.nil?

            support = Styling::PhpCompat.array_get(block_type.supports, path, default_value)
            support == true || support.is_a?(Hash) || support.is_a?(Array)
          end
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # The elements support — wp-includes/block-supports/elements.php:139 and :278.
      # ────────────────────────────────────────────────────────────────────────────────
      #
      # Two halves in the legacy: a `render_block_data` filter that appends a
      # `wp-elements-<n>` class to the block's `className` attribute and stores the element
      # CSS, and a `render_block` filter that copies that class onto the markup. Both run
      # here, in that order, from `ElementsSupport.prepare` / `.render`.
      module ElementsSupport
        ELEMENT_TYPES = %w[button link heading].freeze

        class << self
          # elements.php:139 `wp_render_elements_support_styles()`. Returns the class name
          # to append, or nil, and stores the element rules as a side effect.
          def prepare(block, ctx)
            block_type = Registry[block.block_name]
            return nil if block_type.nil?

            attrs = block.attrs.is_a?(Hash) ? block.attrs : {}
            element_block_styles = Php.dig(attrs, "style", "elements")
            return nil if Php.empty?(element_block_styles)

            skip = ELEMENT_TYPES.to_h do |type|
              [type, LayoutSupport.skip_serialization?(block_type, "color", type == "heading" ? "heading" : type)]
            end
            return nil if skip.values.all?

            return nil unless add_class_name?(element_block_styles, skip)

            class_name = LayoutBlocks.unique_prefixed_id("wp-elements-", ctx)
            store = LayoutBlocks.block_supports_store(ctx)

            selectors = {
              "button" => { "selector" => ".#{class_name} .wp-element-button, .#{class_name} .wp-block-button__link" },
              "link" => { "selector" => ".#{class_name} a:where(:not(.wp-element-button))",
                          "hover_selector" => ".#{class_name} a:where(:not(.wp-element-button)):hover" },
              "heading" => { "selector" => (1..6).map { |n| ".#{class_name} h#{n}" }.join(", "),
                             "elements" => (1..6).map { |n| "h#{n}" } }
            }

            ELEMENT_TYPES.each do |type|
              next if skip[type]

              config = selectors[type]
              style_object = element_block_styles[type]
              if style_object
                Styling::StyleEngine.get_styles(style_object, selector: config["selector"], store: store)
                if style_object.is_a?(Hash) && style_object[":hover"] && config["hover_selector"]
                  Styling::StyleEngine.get_styles(style_object[":hover"], selector: config["hover_selector"], store: store)
                end
              end
              next unless config["elements"]

              config["elements"].each do |element|
                nested = element_block_styles[element]
                next unless nested

                Styling::StyleEngine.get_styles(nested, selector: ".#{class_name} #{element}", store: store)
              end
            end

            class_name
          end

          # elements.php:278 `wp_render_elements_class_name()` — the class the data pass
          # put on `attrs.className` is copied onto the first tag.
          def render(block_content, class_name)
            return block_content if class_name.nil?

            tags = Markup::TagProcessor.new(block_content)
            tags.add_class(class_name) if tags.next_tag
            tags.get_updated_html
          end

          # elements.php:96 `wp_should_add_elements_class_name()`.
          def add_class_name?(element_block_styles, skip)
            ELEMENT_TYPES.any? do |type|
              next false if skip[type]
              next true if element_block_styles[type]

              type == "heading" && (1..6).any? { |n| element_block_styles["h#{n}"] }
            end
          end
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # NOT PORTED, on purpose. See the report.
      # ────────────────────────────────────────────────────────────────────────────────
      module SettingsSupport
        # settings.php:105 `_wp_add_block_level_presets_class()` fires only when a block
        # declares `attrs.settings.color.palette` — a BLOCK-LEVEL PRESET. No block in this
        # family, in any template, pattern or corpus post, carries one; verified by
        # grepping the parsed corpus. It is a pass-through here rather than a wrong guess.
        def self.render(block_content, _block, _ctx) = block_content
      end

      # The remaining members of the `render_block` chain, and why each contributes
      # nothing to this family's output. Every claim below was checked by rendering the
      # whole theme — 8 templates, 7 parts, 98 patterns — through the oracle and diffing.
      #
      #   position (position.php:151)   FIRES ONCE, and is the one real omission.
      #       `patterns/vertical-header.php` has a `core/group` with
      #       `style.position.type: "sticky"`, and the oracle emits
      #       `wp-container-<n> is-position-sticky` on it. The `<n>` is `wp_unique_id()`,
      #       a process-global counter shared with every other block on the page
      #       (functions.php:8196) — the same obstacle as the variation class below, and
      #       one this agent cannot resolve alone. Impact on the 18 golden screens: NONE.
      #       `is-position-sticky` appears in all 18, but only inside a stylesheet;
      #       `wp-container-<n>` appears in none, because that pattern is not on any of
      #       them.
      #   background (background.php:131)   No block in the theme sets
      #       `style.background.backgroundImage`; `grep -r backgroundImage` over the theme
      #       returns nothing.
      #   duotone (duotone.php:44)   Only the `08-midnight` STYLE VARIATION declares a
      #       duotone, and it is not the active style.
      #   custom-css (custom-css.php:153)   Reads `attrs.style.css`, a block-level custom
      #       CSS string. The theme's `"css":` keys are all in theme.json's global styles,
      #       which is a different mechanism.
      #   block-visibility (block-visibility.php:132), states (states.php:740)   No block
      #       in the theme declares either attribute.
      #   wp_strip_inline_note_markers (default-filters.php:791)   Returns immediately
      #       unless the content contains the substring `wp-note`. Nothing does.
      module BlockStyleVariationSupport
        # block-style-variations.php:217 `wp_render_block_style_variation_class_name()`
        # adds `is-style-<slug>--<n>` — but ONLY when the earlier `render_block_data` pass
        # produced a stylesheet for the variation, and that pass runs
        # `WP_Theme_JSON::get_stylesheet()`, which the `styling` pack deliberately did not
        # port (its README §3: "the bulk of the 5,980-line god-object"). Guessing the class
        # without the stylesheet would add a class the legacy omits whenever the variation
        # resolves to no CSS, so this is left OFF rather than approximated.
        #
        # Cost, measured: 60 of the 524 pure-family corpus instances differ by exactly this
        # class and nothing else. Cost on the 18 golden screens: ZERO — `is-style-*--<n>`
        # appears once in the whole golden set, on a `core/post-terms`, which is not in this
        # family.
        def self.render(block_content, _block, _ctx) = block_content
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # ────────────────────────────────────────────────────────────────────────────────
      # Render-scoped state.
      #
      # The legacy keeps both of these in PHP statics — `WP_Style_Engine::$stores`
      # (class-wp-style-engine-css-rules-store.php:30) and the `$id_counters` inside
      # `wp_unique_prefixed_id()` (functions.php:8229) — which under php-fpm are reset
      # between requests because the whole interpreter is. A long-lived Ruby process has
      # no such reset, and paradigm_decision.md implication 1 forbids the global besides,
      # so the lifetime is pinned to the object that already has exactly the right one:
      # the render's `StyleCollector`. A weak key means the entry disappears with it.
      #
      # ⚠️ Puma runs three threads per worker (config/puma.rb:29), so these tables are
      # touched concurrently by unrelated renders. `WeakKeyMap` is not thread-safe and
      # `||=` is check-then-act: without the mutex two simultaneous requests can each
      # install a store for their own `StyleCollector` and one of them is dropped, which
      # loses that page's entire `core-block-supports` stylesheet — intermittently, and
      # only under load. The lock covers the lookup only; the rules themselves are written
      # through a store that exactly one render can reach.
      STORES = ObjectSpace::WeakKeyMap.new
      PREFIXED_COUNTERS = ObjectSpace::WeakKeyMap.new
      RENDER_SCOPE = Mutex.new

      # The `render_block` chain, in registration order.
      # ────────────────────────────────────────────────────────────────────────────────
      class << self
        # The legacy runs these as filters on `render_block`, all at priority 10, so the
        # order is the order the files are required in wp-settings.php:154…436:
        #   typography (default-filters.php:788) → settings → elements → layout →
        #   position → dimensions → duotone → background → block-style-variations →
        #   block-visibility → custom-css → states.
        # AD-01: the list is fixed here, in that order, and nothing can extend it.
        #
        # Only the supports that change the output of THIS family are implemented; each
        # omission is recorded in the report with the reason it cannot fire for these
        # thirteen blocks.
        def apply_supports(block_content, block, ctx, elements_class = nil)
          html = TypographySupport.render(block_content, block, ctx)
          html = SettingsSupport.render(html, block, ctx)
          html = ElementsSupport.render(html, elements_class)
          html = LayoutSupport.render(html, block, ctx)
          html = DimensionsSupport.render(html, block, ctx)
          BlockStyleVariationSupport.render(html, block, ctx)
        end

        # wp-includes/functions.php:8229 `wp_unique_prefixed_id()`, which the legacy backs
        # with a `static $id_counters` — process-global, i.e. per REQUEST under php-fpm.
        # paradigm_decision.md implication 1 forbids a global, so the counter lives for the
        # lifetime of one render, keyed the same way as the block-supports store.
        #
        # ⚠️ The legacy counter is shared by EVERY block on the page, not just this family.
        # Until the shared renderer owns it, a `wp-elements-<n>` emitted by another family
        # would draw from a different sequence. Nothing in the 18 golden screens emits one.
        def unique_prefixed_id(prefix, ctx)
          counters = RENDER_SCOPE.synchronize { PREFIXED_COUNTERS[ctx.styles] ||= Hash.new(0) }
          counters[prefix] += 1
          "#{prefix}#{counters[prefix]}"
        end

        # `WP_Style_Engine::store_css_rule('block-supports', …)` is a process-global
        # static in the legacy. paradigm_decision.md implication 1 forbids that, and
        # `RenderContext` is a shared contract this agent may not extend, so the store is
        # keyed on the one object that already has exactly the lifetime of a single render:
        # the `StyleCollector`, which `RenderContext#with` shares with every child context.
        # See the report — the right home for this is a field on `RenderContext`.
        def block_supports_store(ctx)
          RENDER_SCOPE.synchronize do
            STORES[ctx.styles] ||= Styling::CssRulesStore.new("block-supports")
          end
        end

        # What the legacy prints as `<style id="core-block-supports-inline-css">`, via
        # `wp_enqueue_stored_styles()` → `wp_style_engine_get_stylesheet_from_context()`
        # (script-loader.php:3334, style-engine.php:198). BR-MIGRATE-217/218.
        #
        # ⚠️ `$options` is `array()` at that call site — the action is registered bare
        # (default-filters.php:655) — so `optimize` AND `prettify` are both false. The
        # Processor still deduplicates and combines identical selectors (BR-MIGRATE-218);
        # `optimize` is the separate, stronger pass that also merges selectors sharing a
        # declaration block, and turning it on here reorders output the oracle does not.
        #
        # ⚠️ Call this only AFTER the template has rendered. It reads a store that the
        # render fills; reading it first returns "" and the caller drops the element.
        def block_supports_css(ctx)
          Styling::StyleEngine.get_stylesheet_from_store(block_supports_store(ctx),
                                                         optimize: false, prettify: false)
        end
      end

      # ────────────────────────────────────────────────────────────────────────────────
      # Renderers.
      # ────────────────────────────────────────────────────────────────────────────────

      # A static block that still goes through the support chain.
      #
      # `Base` is right about the MARKUP — these blocks have no render callback and their
      # saved HTML is the output — and wrong about nothing except that the legacy runs the
      # `render_block` filters over that HTML afterwards. So: `Base`'s splice, then the
      # chain.
      class Supported < Base
        # layout.php:1466 `wp_add_parent_layout_to_parsed_block()`, a `render_block_data`
        # filter: a child sees its DIRECT parent's `attrs.layout`, and nothing else. It is
        # not inherited down the tree, so a parent with no layout attribute must CLEAR the
        # key rather than leave the grandparent's value in scope.
        def child_context
          @child_context ||= ctx.with(context: { "layout.parentLayout" => (block.attrs.is_a?(Hash) ? block.attrs["layout"] : nil) })
        end

        # The legacy order, from `WP_Block::render()` (class-wp-block.php:600…732):
        #   1. `render_block_data` for this block  — here, `prepare_supports`
        #   2. inner blocks render                 — here, `render_saved_markup`
        #   3. the block's own render callback     — here, `render_callback`
        #   4. the `render_block` filter chain     — here, `apply_supports`
        #   5. the `render_block_<name>` filter    — here, `after_supports`
        def render
          elements_class = prepare_supports
          content = render_callback(render_saved_markup)
          after_supports(apply_supports(content, elements_class))
        end

        private

        # Step 1. `render_block_data` is the only place the legacy MUTATES the parsed block,
        # and the elements support is the one member of the chain that uses it.
        def prepare_supports = ElementsSupport.prepare(block, ctx)

        # Step 3. Static blocks have none; the four dynamic blocks in this family override.
        def render_callback(content) = content

        # Step 5.
        def after_supports(content) = content

        def apply_supports(html, elements_class = nil)
          LayoutBlocks.apply_supports(html, block, ctx, elements_class)
        end

        # `Base#render`, with the child context threaded through.
        def render_saved_markup
          return block.inner_html if block.inner_blocks.empty?

          index = -1
          block.inner_content.map do |chunk|
            next chunk unless chunk.nil?

            index += 1
            Renderer.render_block(block.inner_blocks[index], child_context)
          end.join
        end
      end

      # Adds one class to the first tag of a given kind. Three blocks in this family do
      # exactly this and nothing else, and all three are "dynamic" only in that sense.
      class ClassAdder < Supported
        class << self
          attr_reader :added_class, :target_tags

          def adds(class_name, tags:)
            @added_class = class_name
            @target_tags = tags.map(&:upcase)
          end
        end

        private

        def render_callback(content)
          return content if content.to_s.empty?

          processor = Markup::TagProcessor.new(content)
          while processor.next_tag
            next unless self.class.target_tags.include?(processor.get_tag)

            processor.add_class(self.class.added_class)
            break
          end
          processor.get_updated_html
        end
      end

      # wp-includes/blocks/heading.php:24 `block_core_heading_render()`.
      class Heading < ClassAdder
        handles "core/heading"
        adds "wp-block-heading", tags: %w[h1 h2 h3 h4 h5 h6]
      end

      # wp-includes/blocks/list.php:22 `block_core_list_render()`.
      class List < ClassAdder
        handles "core/list"
        adds "wp-block-list", tags: %w[ol ul]
      end

      # wp-includes/blocks/paragraph.php:24 `block_core_paragraph_add_class()`.
      #
      # ⚠️ This one is a `render_block_core/paragraph` FILTER in the legacy, not a render
      # callback, so it runs AFTER the whole `render_block` chain rather than before it.
      # The difference is observable: the class lands at the END of the class attribute.
      class Paragraph < Supported
        handles "core/paragraph"

        private

        def after_supports(content)
          return content if content.to_s.empty?

          processor = Markup::TagProcessor.new(content)
          processor.add_class("wp-block-paragraph") if processor.next_tag("p")
          processor.get_updated_html
        end
      end

      # Static blocks. `Base` handles the markup; the chain handles the rest.
      class Group < Supported
        handles "core/group"

        # layout.php:1497 `wp_restore_group_inner_container()` is a no-op for this site:
        # its first condition is `wp_theme_has_theme_json()`, and twentytwentyfive ships a
        # theme.json, so the filter returns the content untouched. AD-01 means there is no
        # way for that to change at runtime, so the branch is not ported — it is recorded
        # here instead, because a classic theme WOULD take it.
      end

      class Columns < Supported
        handles "core/columns"
      end

      class Column < Supported
        handles "core/column"
      end

      class Buttons < Supported
        handles "core/buttons"
      end

      class Quote < Supported
        handles "core/quote"
      end

      class Spacer < Supported
        handles "core/spacer"
      end

      class Separator < Supported
        handles "core/separator"
      end

      class ListItem < Supported
        handles "core/list-item"
      end

      # wp-includes/blocks/cover.php:18 `render_block_core_cover()`.
      class Cover < Supported
        handles "core/cover"

        private

        def render_callback(content)
          # cover.php:20 — the embed-video background rewrites the inner `figure` into an
          # autoplaying iframe. It needs `wp_oembed_get()`, i.e. a network fetch through the
          # egress policy, which belongs to another context; no cover in any template,
          # pattern or corpus post uses it (`backgroundType` is `image` everywhere).
          return content if attrs["backgroundType"] == "embed-video"

          # cover.php:133 — the ONLY other thing this callback does is splice the featured
          # image in, and it returns untouched unless `useFeaturedImage` is set. `attrs` here
          # is the schema-prepared attribute set (BR-MIGRATE-204), so `backgroundType`
          # defaults to "image" and `useFeaturedImage` to false.
          return content if attrs["backgroundType"] != "image" || attrs["useFeaturedImage"] == false

          # The featured-image path needs `get_the_post_thumbnail()` — the post's attachment,
          # its size variants and its alt text. Reported as an unclosed gap rather than
          # approximated; it cannot fire without a post in context.
          content
        end
      end

      # wp-includes/blocks/button.php:18 `render_block_core_button()`.
      class Button < Supported
        handles "core/button"

        LEGACY_WIDTHS = {
          "25%" => "wp-block-button__width-25",
          "50%" => "wp-block-button__width-50",
          "75%" => "wp-block-button__width-75",
          "100%" => "wp-block-button__width-100"
        }.freeze

        private

        def render_callback(content)
          processor = Markup::TagProcessor.new(content)
          tag = nil
          while processor.next_tag
            tag = processor.get_tag
            break if tag == "A" || tag == "BUTTON"
          end
          return content if tag.nil?

          # button.php:41 — "if the next token is the closing tag, the button is empty".
          # A comment does not count as content; anything else does.
          is_empty = true
          while is_empty && processor.next_token
            break if tag == processor.get_token_name

            is_empty = false if processor.get_token_type != "#comment"
          end
          # button.php:59 — an empty button renders NOTHING. That is deliberate upstream
          # (gutenberg#17221), not an accident, so it is reproduced exactly.
          return "" if is_empty

          width = Php.dig(attrs, "style", "dimensions", "width")
          return content unless LayoutSupport.truthy(width)

          resolved_width = width
          is_preset = width.to_s.start_with?("var:preset|dimension|")
          slug = is_preset ? width.to_s[("var:preset|dimension|".length)..] : nil
          if is_preset
            resolved_width = dimension_preset_size(slug) || width
          end

          is_percentage = resolved_width.to_s.end_with?("%")
          processor = Markup::TagProcessor.new(content)
          return content unless processor.next_tag({ class_name: "wp-block-button" })

          processor.add_class("has-custom-width")
          existing_style = processor.get_attribute("style")
          existing_style = "" unless existing_style.is_a?(String)

          if is_percentage
            numeric_width = TypographySupport.num(php_floatval(resolved_width))
            processor.add_class("wp-block-button__width")
            legacy = LEGACY_WIDTHS[resolved_width]
            processor.add_class(legacy) if legacy
            width_style = "--wp--block-button--width: #{numeric_width};"
          else
            css_value = is_preset ? "var(--wp--preset--dimension--#{Styling::PhpCompat.to_kebab_case(slug)})" : width
            width_style = "width: #{css_value};"
          end
          processor.set_attribute("style", width_style + (existing_style.empty? ? "" : " #{existing_style}"))
          processor.get_updated_html
        end

        # button.php:72 — `wp_get_global_settings(['dimensions','dimensionSizes'], …)`,
        # searched custom → theme → default. Neither core's nor the theme's theme.json
        # declares `settings.dimensions.dimensionSizes`, so this resolves to nil and the
        # raw `var:preset|dimension|<slug>` falls through to the `var(--wp--preset--…)`
        # branch, which is what the oracle does.
        def dimension_preset_size(slug)
          presets = Styling::PhpCompat.array_get(GlobalStyles.settings, %w[dimensions dimensionSizes])
          return nil unless presets.is_a?(Hash)

          %w[custom theme default].each do |origin|
            list = presets[origin]
            next unless list.is_a?(Array) && !list.empty?

            found = list.find { |preset| preset.is_a?(Hash) && preset["slug"] == slug }
            return found["size"] if found&.key?("size")
          end
          nil
        end

        def php_floatval(value) = LayoutSupport.send(:php_floatval, value)
      end
    end
  end
end
