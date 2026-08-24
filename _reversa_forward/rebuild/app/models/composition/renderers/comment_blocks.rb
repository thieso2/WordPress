# frozen_string_literal: true

module Composition
  module Renderers
    # The comment family: the twelve server-rendered blocks that make up the
    # comments area of a block theme.
    #
    #   core/comments               wp-includes/blocks/comments.php:28
    #   core/comment-template       wp-includes/blocks/comment-template.php:19,100
    #   core/comment-author-name    wp-includes/blocks/comment-author-name.php:18
    #   core/comment-content        wp-includes/blocks/comment-content.php:18
    #   core/comment-date           wp-includes/blocks/comment-date.php:18
    #   core/comment-reply-link     wp-includes/blocks/comment-reply-link.php:18
    #   core/comment-edit-link      wp-includes/blocks/comment-edit-link.php:19
    #   core/comments-title         wp-includes/blocks/comments-title.php:17
    #   core/comments-pagination    wp-includes/blocks/comments-pagination.php:18
    #   core/post-comments-form     wp-includes/blocks/post-comments-form.php:18
    #   core/post-comments-count    wp-includes/blocks/post-comments-count.php:18
    #   core/post-comments-link     wp-includes/blocks/post-comments-link.php:18
    #
    # AD-01. Every `apply_filters` these callbacks reach for is gone. Where a legacy
    # render callback's output depends on a filter, what is implemented here is the
    # value WordPress CORE produces with no plugin present — because that is the value
    # the oracle emits and the golden files record — and there is no way to change it.
    # The two places where that distinction bites are named at their site:
    #   * `comment_text` (Renderers::CommentBlocks::CommentText) — core registers six
    #     callbacks on it in wp-includes/default-filters.php:225..230; they are inlined
    #     as a fixed pipeline.
    #   * `the_title` (CommentsTitle) — three core callbacks, likewise inlined.
    #
    # Implication 1 (no global mutable state). The legacy threads FOUR globals through
    # this family: `$post`, `$comment_depth`, `$comment_alt` and `$comment_thread_alt`
    # (wp-includes/comment-template.php:521). None of them exists here. `$post` travels
    # as `ctx.post`; the three counters live in a `ThreadState` created per
    # comment-template render and passed down the recursion explicitly.
    module CommentBlocks
      # ── PHP-compatible primitives ────────────────────────────────────────────
      #
      # ⚠️ SHARED-CODE NOTE. `Php.date`, `Php.number_format_i18n` and `Urls` are not
      # comment-specific — every date-bearing and link-bearing block needs them. They
      # live here only because this agent owns exactly one file. They should move to a
      # shared home (a `Composition::Php` / `Composition::Urls`, or the `sanitizing`
      # pack) the moment one exists; see the report.
      module Php
        module_function

        DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
        MONTHS = %w[January February March April May June July August September
                    October November December].freeze

        # PHP's date() format language, as `mysql2date()` uses it
        # (wp-includes/functions.php, via get_comment_date()). A backslash escapes the
        # next character, which is why `c` can be expressed in terms of itself.
        def date(time, format)
          out = +""
          i = 0
          chars = format.to_s.chars
          while i < chars.length
            ch = chars[i]
            if ch == "\\"
              out << chars[i + 1].to_s
              i += 2
              next
            end
            out << token(time, ch)
            i += 1
          end
          out
        end

        def token(t, ch)
          case ch
          when "d" then format("%02d", t.day)
          when "D" then DAYS[t.wday][0, 3]
          when "j" then t.day.to_s
          when "l" then DAYS[t.wday]
          when "N" then (t.wday.zero? ? 7 : t.wday).to_s
          when "S" then ordinal_suffix(t.day)
          when "w" then t.wday.to_s
          when "z" then (t.yday - 1).to_s
          when "W" then t.strftime("%V")
          when "F" then MONTHS[t.month - 1]
          when "m" then format("%02d", t.month)
          when "M" then MONTHS[t.month - 1][0, 3]
          when "n" then t.month.to_s
          when "t" then Date.new(t.year, t.month, -1).day.to_s
          when "L" then (Date.leap?(t.year) ? "1" : "0")
          when "o" then t.strftime("%G")
          when "Y" then t.year.to_s
          when "y" then format("%02d", t.year % 100)
          when "a" then (t.hour < 12 ? "am" : "pm")
          when "A" then (t.hour < 12 ? "AM" : "PM")
          when "g" then ((t.hour % 12).zero? ? 12 : t.hour % 12).to_s
          when "G" then t.hour.to_s
          when "h" then format("%02d", (t.hour % 12).zero? ? 12 : t.hour % 12)
          when "H" then format("%02d", t.hour)
          when "i" then format("%02d", t.min)
          when "s" then format("%02d", t.sec)
          when "u" then format("%06d", t.usec)
          when "v" then format("%03d", t.usec / 1000)
          when "e", "T" then t.strftime("%Z")
          when "I" then (t.respond_to?(:dst?) && t.dst? ? "1" : "0")
          when "O" then t.strftime("%z")
          when "P" then t.strftime("%:z")
          when "Z" then t.utc_offset.to_s
          when "c" then date(t, 'Y-m-d\TH:i:sP')
          when "r" then date(t, "D, d M Y H:i:s O")
          when "U" then t.to_i.to_s
          else ch
          end
        end

        def ordinal_suffix(day)
          return "th" if [11, 12, 13].include?(day % 100)

          case day % 10
          when 1 then "st"
          when 2 then "nd"
          when 3 then "rd"
          else "th"
          end
        end

        # number_format_i18n() for the en_US locale WordPress ships with: thousands
        # separator ',', no decimals. AD-01: there is no `number_format_i18n` filter and
        # no locale switch, so this IS the number format.
        def number_format_i18n(number)
          int = number.to_i
          int.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end

        # PHP prints an integral float without its fractional part ("h" . 3.0 === "h3").
        def num_to_s(value)
          return value.to_i.to_s if value.is_a?(Float) && value == value.to_i

          value.to_s
        end

        # English plural selection. `_n()` with the default (en_US) locale.
        def n_(single, plural, count) = count == 1 ? single : plural
      end

      # ── Options ──────────────────────────────────────────────────────────────
      #
      # BR-MIGRATE-012: `Configuration::Setting[]` returns `false` for a missing name,
      # exactly as get_option() does, so PHP's truthiness tests port directly — with the
      # one correction that PHP treats the STRING "0" as false and Ruby does not.
      module Options
        module_function

        def get(name) = Configuration::Setting[name]

        # PHP `empty()` / falsy test.
        def falsy?(value)
          value.nil? || value == false || value == 0 || value == "" || value == "0"
        end

        def truthy?(value) = !falsy?(value)
      end

      # ── Site URLs ────────────────────────────────────────────────────────────
      #
      # ⚠️ `Composition::RenderContext#permalink_for` returns a HOST-RELATIVE path with
      # no trailing slash ("/2026/03/hello-world"). Every golden file records the
      # legacy's absolute, trailing-slashed permalink ("<SITE>/2026/03/hello-world/"),
      # so it cannot be used here without failing the diff on every link this family
      # emits. The correct permalink is computed below instead. This duplication is a
      # symptom, not a design: see the report.
      module Urls
        module_function

        # get_option('siteurl') — wp-includes/link-template.php, site_url().
        def site_url(path = "")
          "#{Configuration::Setting["siteurl"].to_s.chomp("/")}#{path}"
        end

        # get_option('home') — home_url(). BR-MIGRATE-012 already makes an empty `home`
        # fall back to `siteurl`.
        def home_url(path = "")
          "#{Configuration::Setting["home"].to_s.chomp("/")}#{path}"
        end

        # get_permalink(), wp-includes/link-template.php.
        #
        # Implemented for the token set the corpus permastruct uses
        # (/%year%/%monthnum%/%postname%/) plus the remaining date/id tokens. A
        # permastruct containing %category% or %author% would need the taxonomy and
        # author lookups those tokens imply; it is not implemented and would fall
        # through to the raw token. Pages are hierarchical and use their page URI.
        POST_TOKENS = %w[year monthnum day hour minute second post_id postname].freeze

        def permalink(record)
          return home_url("/") if record.nil?
          return home_url("/#{page_uri(record)}/") if record.is_a?(Publishing::Page)
          # A record with no publication instant has no pretty permalink; the legacy
          # falls back to the plain query form.
          return home_url("/?p=#{record.id}") if record.published_at.nil? || record.slug.blank?

          structure = Routing::PermalinkStructure.current.pattern.to_s
          return home_url("/?p=#{record.id}") if structure.empty?

          t = Times.local(record.published_at)
          path = structure.gsub(/%([a-z_]+)%/) do
            case Regexp.last_match(1)
            when "year"     then Php.date(t, "Y")
            when "monthnum" then Php.date(t, "m")
            when "day"      then Php.date(t, "d")
            when "hour"     then Php.date(t, "H")
            when "minute"   then Php.date(t, "i")
            when "second"   then Php.date(t, "s")
            when "post_id"  then record.id.to_s
            when "postname" then record.slug.to_s
            else Regexp.last_match(0)
            end
          end
          home_url(path)
        end

        # get_page_uri(): the slug chain from the root down.
        def page_uri(page)
          segments = [page.slug.to_s]
          node = page.parent
          seen = Set.new([page.id])
          while node && !seen.include?(node.id)
            seen << node.id
            segments.unshift(node.slug.to_s)
            node = node.parent
          end
          segments.reject(&:empty?).join("/")
        end

        # get_comment_link(), wp-includes/comment-template.php:778. With
        # `page_comments` off — the corpus setting — the 'cpage' branch is unreachable
        # and the link is the post permalink plus the comment anchor.
        def comment_link(comment, post)
          "#{permalink(post)}#comment-#{comment.id}"
        end

        # get_comments_link(), wp-includes/comment-template.php.
        def comments_link(post, comments_number)
          "#{permalink(post)}#{comments_number.to_i.zero? ? "#respond" : "#comments"}"
        end

        # add_query_arg() for the one shape this family needs: a key with a scalar value
        # appended to a URL that has no query string of its own. `false` values are
        # REMOVED by add_query_arg, which is why 'unapproved' and 'moderation-hash'
        # never appear (comment-reply-link.php:44).
        def add_query_arg(url, key, value)
          separator = url.include?("?") ? "&" : "?"
          "#{url}#{separator}#{ERB::Util.url_encode(key.to_s)}=#{ERB::Util.url_encode(value.to_s)}"
        end
      end

      # ── Site time ────────────────────────────────────────────────────────────
      #
      # The legacy stores a comment twice: `comment_date` (site-local wall clock) and
      # `comment_date_gmt`. The rebuild has ONE column, `submitted_at`, and the corpus
      # migration put the LOCAL wall clock in it (oracle comment 1: comment_date
      # 2026-03-15 09:59:00 local == rebuild submitted_at 2026-03-15 09:59:00). So the
      # instant is reconstructed by re-reading those wall-clock components in the site
      # timezone rather than by converting them — converting would move the printed
      # date, and `get_comment_date()` prints the local one.
      module Times
        module_function

        def zone
          name = Configuration::Setting["timezone_string"]
          zone = ActiveSupport::TimeZone[name.to_s] if name.is_a?(String) && !name.empty?
          return zone if zone

          offset = Configuration::Setting["gmt_offset"]
          ActiveSupport::TimeZone[(offset.to_f * 3600).to_i] || ActiveSupport::TimeZone["UTC"]
        end

        def local(timestamp)
          return nil if timestamp.nil?

          zone.local(timestamp.year, timestamp.month, timestamp.day,
                     timestamp.hour, timestamp.min, timestamp.sec)
        end

        # human_time_diff(), wp-includes/formatting.php.
        MINUTE = 60
        HOUR = 3600
        DAY = 86_400
        WEEK = 604_800
        MONTH = 2_629_746
        YEAR = 31_556_952

        def human_time_diff(from, to = Time.current)
          diff = (to.to_i - from.to_i).abs
          if diff < MINUTE
            n = [diff, 1].max
            "#{n} #{Php.n_("second", "seconds", n)}"
          elsif diff < HOUR
            n = [(diff.to_f / MINUTE).round, 1].max
            "#{n} #{Php.n_("minute", "minutes", n)}"
          elsif diff < DAY
            n = [(diff.to_f / HOUR).round, 1].max
            "#{n} #{Php.n_("hour", "hours", n)}"
          elsif diff < WEEK
            n = [(diff.to_f / DAY).round, 1].max
            "#{n} #{Php.n_("day", "days", n)}"
          elsif diff < MONTH
            n = [(diff.to_f / WEEK).round, 1].max
            "#{n} #{Php.n_("week", "weeks", n)}"
          elsif diff < YEAR
            n = [(diff.to_f / MONTH).round, 1].max
            "#{n} #{Php.n_("month", "months", n)}"
          else
            n = [(diff.to_f / YEAR).round, 1].max
            "#{n} #{Php.n_("year", "years", n)}"
          end
        end
      end

      # ── The `comment_text` pipeline ──────────────────────────────────────────
      #
      # wp-includes/default-filters.php:225..230 registers, in priority order:
      #   9  make_clickable        ⚠️ NOT IMPLEMENTED — see below
      #   10 wptexturize           → Sanitizing::Texturize.wptexturize
      #   10 convert_chars         → implemented here (two regexes)
      #   20 convert_smilies       ⚠️ NOT IMPLEMENTED — see below
      #   25 force_balance_tags    ⚠️ NOT IMPLEMENTED — see below
      #   30 wpautop               → Sanitizing::Formatting.wpautop
      #   31 capital_P_dangit      → implemented here
      # (`wp_kses_post` is registered on `comment_text` only under `is_admin()`,
      #  wp-includes/default-filters.php:54..58, so the front end does not kses at
      #  display time. Comment bodies are ksesed on WRITE, by `pre_comment_content`.)
      #
      # The three unimplemented stages need ports that belong in the `sanitizing` pack,
      # which this agent does not own. Each was checked against the oracle over every
      # comment in the corpus and is a no-op on all of them; the check is a spec.
      module CommentText
        module_function

        def call(raw)
          text = raw.to_s
          text = Sanitizing::Texturize.wptexturize(text)
          text = convert_chars(text)
          text = Sanitizing::Formatting.wpautop(text)
          capital_p_dangit(text)
        end

        # convert_chars(), wp-includes/formatting.php:2492. Since 7.x this function does
        # ONE thing (:2497-2498): a bare `&` — one not already opening a `&#…;` numeric or
        # a short named entity — becomes `&#038;`. The `<title>`/`<category>` stripping an
        # earlier port carried here was the pre-4.x body and is not what the oracle runs.
        def convert_chars(content)
          return content unless content.include?("&")

          content.gsub(/&([^#])(?![a-z1-4]{1,8};)/i, '&#038;\1')
        end

        # capital_P_dangit(), wp-includes/formatting.php — the "judicious" branch, which
        # is the one that applies outside `the_title`/`wp_title`.
        DBLQ = "&#8220;"

        def capital_p_dangit(text)
          [" ", "&#8216;", DBLQ, ">", "("].reduce(text) do |acc, prefix|
            acc.gsub("#{prefix}Wordpress", "#{prefix}WordPress")
          end
        end

        # capital_P_dangit()'s `the_title`/`wp_title` branch.
        def capital_p_dangit_title(text) = text.gsub("Wordpress", "WordPress")
      end

      # ── Block wrapper attributes ─────────────────────────────────────────────
      #
      # get_block_wrapper_attributes(), wp-includes/class-wp-block-supports.php:203,
      # over the supports that can produce output for THIS family's block types.
      #
      # BR-MIGRATE-200: only a registered block type gets anything.
      # BR-MIGRATE-201: the first support to write an attribute takes the slot; later
      #                 ones append after one space — which is why the support order
      #                 below is the legacy's REGISTRATION order, not alphabetical.
      # BR-MIGRATE-204: schema defaults are already applied (`Base#attrs`).
      # BR-MIGRATE-205: the block being rendered is a parameter, never a static.
      #
      # ⚠️ Implemented: align, custom-classname, generated-classname, colors,
      # typography, border, spacing, dimensions, shadow, anchor, aria-label.
      # NOT implemented: layout, position, duotone, background,
      # block-style-variation, custom-css. Of those only `layout` is declared by a
      # block in this family (core/comments-pagination), and only on a block whose
      # callback returns '' whenever its inner pagination links are empty — which is
      # the whole corpus, because `page_comments` is off. Reported rather than faked.
      class Wrapper
        # Each support builds its own value tree and hands it to the `styling` pack's
        # port of the style engine, which owns the declaration order and the units —
        # they are not re-derived here.
        def initialize(type, attrs)
          @type = type
          @attrs = attrs || {}
        end

        # @return [String] e.g. `class="wp-block-comment-date"`, or "" for nothing.
        def to_s(extra = {})
          new_attributes = supports_attributes
          extra = extra.reject { |_, v| v.nil? }
          return "" if new_attributes.empty? && extra.empty?

          merged = {}
          # The merge order is hardcoded in the legacy "on purpose, as we only support a
          # fixed list of attributes" — and it is also the ORDER THE ATTRIBUTES PRINT IN.
          merged["style"] = merge_style(new_attributes["style"], extra["style"])
          merged["class"] = merge_class(new_attributes["class"], extra["class"])
          merged["id"] = merge_first(extra["id"], new_attributes["id"])
          merged["aria-label"] = merge_first(extra["aria-label"], new_attributes["aria-label"])
          merged = merged.reject { |_, v| v.nil? }

          extra.each do |name, value|
            next if %w[style class id aria-label].include?(name)
            next unless scalar?(value)

            merged[name] = value.to_s
          end

          return "" if merged.empty?

          merged.map { |k, v| %(#{k}="#{Sanitizing::Formatting.esc_attr(v)}") }.join(" ")
        end

        private

        def scalar?(value)
          (value.is_a?(String) || value.is_a?(Numeric)) && !value.is_a?(TrueClass)
        end

        def merge_style(new_value, extra_value)
          parts = [new_value, extra_value].compact
                                          .map { |v| v.to_s.strip.sub(/;+\z/, "") }
                                          .reject(&:empty?)
          return nil if parts.empty?

          Sanitizing::Css.safecss_filter_attr(parts.join(";"))
        end

        # extra classes first, then the supports' — get_block_wrapper_attributes():231.
        def merge_class(new_value, extra_value)
          classes = (extra_value.to_s.split(/\s+/) + new_value.to_s.split(/\s+/))
                    .reject(&:empty?).uniq
          classes.empty? ? nil : classes.join(" ")
        end

        def merge_first(preferred, fallback)
          return preferred if preferred.is_a?(String) && !preferred.empty?

          fallback
        end

        # The supports pipeline, in the legacy's REGISTRATION order — which is what
        # BR-MIGRATE-201 makes observable, because the first writer of an attribute takes
        # the slot and everyone after it appends.
        def supports_attributes
          out = {}
          push(out, "class", align_class)
          push(out, "class", custom_classname)
          push(out, "class", generated_classname)
          [colors_support, typography_support, border_support,
           spacing_support, dimensions_support, shadow_support].each do |attributes|
            next if attributes.nil?

            attributes.each { |key, value| push(out, key, value) }
          end
          push(out, "id", anchor)
          out
        end

        def push(out, key, value)
          return if value.nil? || value.to_s.empty?

          out[key] = out[key].to_s.empty? ? value.to_s : "#{out[key]} #{value}"
        end

        def supports?(key) = @type && @type.supports.key?(key) && @type.supports[key]

        # wp_style_engine_get_styles(), via the `styling` pack's port. `classnames: true`
        # is the legacy's `convert_vars_to_classnames`, which turns `var:preset|…` into
        # `has-…` instead of a declaration.
        def engine(styles, classnames: false)
          result = Styling::StyleEngine.get_styles(styles, convert_vars_to_classnames: classnames)
          out = {}
          out["class"] = result["classnames"] if result["classnames"].present?
          out["style"] = result["css"] if result["css"].present?
          out.empty? ? nil : out
        end

        # `$preset ? $preset : $custom` — the preset ATTRIBUTE always beats the custom
        # `style` value, and the custom one is then not emitted at all.
        def preset_or_custom(attribute, preset_kind, *style_path)
          preset = @attrs.key?(attribute) ? "var:preset|#{preset_kind}|#{@attrs[attribute]}" : nil
          preset || @attrs.dig("style", *style_path)
        end

        # wp_apply_colors_support(), wp-includes/block-supports/colors.php:39.
        def colors_support
          support = @type&.supports&.[]("color")
          return nil unless support

          hash = support.is_a?(Hash)
          styles = {}
          if support == true || (hash && (support["text"] || !support.key?("text")))
            styles["text"] = preset_or_custom("textColor", "color", "color", "text")
          end
          if support == true || (hash && (support["background"] || !support.key?("background")))
            styles["background"] = preset_or_custom("backgroundColor", "color", "color", "background")
          end
          styles["gradient"] = preset_or_custom("gradient", "gradient", "color", "gradient") if hash && support["gradients"]
          engine({ "color" => styles.compact }, classnames: true)
        end

        # wp_apply_typography_support(), wp-includes/block-supports/typography.php:73.
        #
        # ⚠️ `wp_get_typography_font_size_value()` and
        # `wp_typography_get_preset_inline_style_value()` are passed through unchanged.
        # The first of the two applies FLUID TYPOGRAPHY when theme.json enables it,
        # turning a custom `style.typography.fontSize` into a clamp(); that conversion
        # is not implemented. No block in this family carries a custom font size in the
        # corpus, and a preset font size — which is what the theme uses — never reaches
        # that function. Reported.
        TYPOGRAPHY_FEATURES = {
          "__experimentalFontStyle" => "fontStyle",
          "__experimentalFontWeight" => "fontWeight",
          "lineHeight" => "lineHeight",
          "__experimentalTextDecoration" => "textDecoration",
          "__experimentalTextTransform" => "textTransform",
          "__experimentalLetterSpacing" => "letterSpacing",
          "textColumns" => "textColumns",
          "textIndent" => "textIndent",
          "__experimentalWritingMode" => "writingMode"
        }.freeze

        def typography_support
          support = @type&.supports&.[]("typography")
          return nil unless support.is_a?(Hash)

          styles = {}
          styles["fontSize"] = preset_or_custom("fontSize", "font-size", "typography", "fontSize") if support["fontSize"]
          if support["__experimentalFontFamily"]
            styles["fontFamily"] = preset_or_custom("fontFamily", "font-family", "typography", "fontFamily")
          end
          TYPOGRAPHY_FEATURES.each do |flag, key|
            next unless support[flag]

            value = @attrs.dig("style", "typography", key)
            styles[key] = value unless value.nil?
          end

          out = engine({ "typography" => styles.compact }, classnames: true) || {}
          # typography.php:302 — textAlign is a CLASS the support adds after the engine's.
          if support["textAlign"] && @attrs.dig("style", "typography", "textAlign")
            align = "has-text-align-#{@attrs.dig("style", "typography", "textAlign")}"
            out["class"] = out["class"].present? ? "#{out["class"]} #{align}" : align
          end
          out.empty? ? nil : out
        end

        # wp_apply_border_support(), wp-includes/block-supports/border.php:44.
        BORDER_SIDES = %w[top right bottom left].freeze

        def border_support
          support = @type&.supports&.[]("__experimentalBorder")
          return nil unless support

          feature = ->(name) { support == true || (support.is_a?(Hash) && support[name]) }
          styles = {}
          if feature.call("radius") && @attrs.dig("style", "border", "radius")
            styles["radius"] = with_px(@attrs.dig("style", "border", "radius"))
          end
          styles["style"] = @attrs.dig("style", "border", "style") if feature.call("style") && @attrs.dig("style", "border", "style")
          if feature.call("width") && @attrs.dig("style", "border", "width")
            styles["width"] = with_px(@attrs.dig("style", "border", "width"))
          end
          styles["color"] = preset_or_custom("borderColor", "color", "border", "color") if feature.call("color")
          if feature.call("color") || feature.call("width")
            BORDER_SIDES.each do |side|
              side_values = @attrs.dig("style", "border", side) || {}
              values = { "width" => side_values["width"], "color" => side_values["color"],
                         "style" => side_values["style"] }.compact
              styles[side] = values unless values.empty?
            end
          end
          engine({ "border" => styles.compact })
        end

        # "This check handles original unitless implementation."
        def with_px(value) = value.is_a?(Numeric) || /\A-?\d+(\.\d+)?\z/.match?(value.to_s) ? "#{value}px" : value

        # wp_apply_spacing_support(), wp-includes/block-supports/spacing.php:44.
        def spacing_support
          support = @type&.supports&.[]("spacing")
          return nil unless support

          hash = support.is_a?(Hash)
          styles = {}
          styles["padding"] = @attrs.dig("style", "spacing", "padding") if support == true || (hash && support["padding"])
          styles["margin"] = @attrs.dig("style", "spacing", "margin") if support == true || (hash && support["margin"])
          engine({ "spacing" => styles.compact })
        end

        DIMENSION_FEATURES = %w[minHeight aspectRatio].freeze

        def dimensions_support
          support = @type&.supports&.[]("dimensions")
          return nil unless support

          hash = support.is_a?(Hash)
          styles = DIMENSION_FEATURES.each_with_object({}) do |feature, out|
            next unless support == true || (hash && support[feature])

            value = @attrs.dig("style", "dimensions", feature)
            out[feature] = value unless value.nil?
          end
          engine({ "dimensions" => styles })
        end

        def shadow_support
          return nil unless @type&.supports&.key?("shadow")

          value = @attrs.dig("style", "shadow")
          return nil if value.nil?

          engine({ "shadow" => value })
        end

        # wp_apply_align_support(): only an align the block type actually allows.
        def align_class
          align = @attrs["align"]
          return nil if align.nil? || align.to_s.empty?

          allowed = @type&.supports&.[]("align")
          return nil unless allowed
          return "align#{align}" if allowed == true
          return "align#{align}" if allowed.is_a?(Array) && allowed.map(&:to_s).include?(align.to_s)

          nil
        end

        def custom_classname
          return nil if @type && @type.supports["customClassName"] == false

          @attrs["className"]
        end

        def generated_classname
          return nil if @type.nil? || @type.supports["className"] == false

          "wp-block-#{@type.short_name}"
        end

        def anchor
          return nil unless supports?("anchor")

          @attrs["anchor"]
        end
      end

      # ── The comment thread ───────────────────────────────────────────────────

      # The three order-sensitive globals of comment_class()
      # (wp-includes/comment-template.php:521), as one explicit object.
      #
      # ⚠️ The legacy's own comment says why the order matters: "We need to create the
      # CSS classes BEFORE recursing into the children. This is because comment_class()
      # uses globals like `$comment_alt` and `$comment_thread_alt` which are
      # order-sensitive." (comment-template.php:56). The recursion below preserves that
      # order exactly.
      class ThreadState
        attr_accessor :alt, :thread_alt

        def initialize
          @alt = 0
          @thread_alt = 0
        end
      end

      # One comment plus its already-resolved approved children, i.e. what
      # WP_Comment_Query's `hierarchical => 'threaded'` mode hands the callback via
      # `$comment->get_children()`.
      Node = Struct.new(:comment, :children)

      # build_comment_query_vars_from_block(), wp-includes/blocks.php.
      #
      #   orderby comment_date_gmt, order ASC, status approve, post_id, hierarchical.
      #
      # `include_unapproved` is unreachable: it needs either a logged-in user or the
      # unapproved-comment cookie, and Composition may not depend on Access (contexts
      # are namespaces; nothing may depend on Access). The read-only Wave 2 visitor is
      # anonymous, so only approved comments are listed — `Discussion::Comment.approved`.
      #
      # `page_comments` is off in the corpus; when it is on the legacy paginates here.
      # That branch is NOT implemented — see the report.
      module Query
        module_function

        def nodes_for(post_id)
          comments = Discussion::Comment.approved.where(post_id: post_id).oldest_first.to_a
          return [] if comments.empty?

          if Options.falsy?(Options.get("thread_comments"))
            # hierarchical => false: every comment is returned flat and
            # `get_children()` is empty, so replies render at depth 1 alongside roots.
            return comments.map { |c| Node.new(c, []) }
          end

          by_parent = comments.group_by(&:parent_id)
          build = lambda do |parent_id|
            (by_parent[parent_id] || []).map { |c| Node.new(c, build.call(c.id)) }
          end
          roots = build.call(nil)
          # An approved reply whose parent is not itself approved is an orphan: the
          # legacy's threaded query returns it at the top level, because
          # `fill_descendants` only ever attaches a child to a parent it fetched.
          attached = Set.new
          collect = lambda { |ns| ns.each { |n| attached << n.comment.id; collect.call(n.children) } }
          collect.call(roots)
          orphans = comments.reject { |c| attached.include?(c.id) }
                            .map { |c| Node.new(c, []) }
          (roots + orphans).sort_by { |n| [n.comment.submitted_at, n.comment.id] }
        end
      end

      # ── Shared renderer base ─────────────────────────────────────────────────
      class CommentBlock < Renderers::Base
        private

        def wrapper_attributes(extra = {}) = Wrapper.new(type, attrs).to_s(extra)

        def esc_attr(value) = Sanitizing::Formatting.esc_attr(value.to_s)
        def esc_html(value) = Sanitizing::Formatting.esc_html(value.to_s)
        def esc_url(value) = Sanitizing::Formatting.esc_url(value.to_s)

        def context_post_id = ctx.context["postId"]

        def context_post
          id = context_post_id
          return ctx.post if id.nil?
          return ctx.post if ctx.post && ctx.post.id == id

          Publishing::Post.find_by(id: id)
        end

        def context_comment
          id = ctx.context["commentId"]
          return nil if id.nil?

          Discussion::Comment.find_by(id: id)
        end

        # comments_open(), wp-includes/comment-template.php.
        def comments_open?(post) = post.present? && post.comment_status.to_s == "open"

        # post_password_required(), wp-includes/post-template.php:882. A post with no
        # password never requires one (:885). For one that does, the answer hinges on the
        # `wp-postpass_<COOKIEHASH>` cookie (:890): absent, the password is required, and
        # only a cookie carrying a phpass hash of the right password (:895-903) lifts it.
        # A rendered block has no request in this system and the Wave 2 visitor is
        # anonymous, so the cookie branch is unreachable and the rule collapses to "the
        # post has a password". Four callbacks in this family return '' on it —
        # comments-title.php:19, comment-template.php:110, comments-pagination.php:23,
        # post-comments-form.php:23 — and that is what keeps the comment-form stylesheets
        # OUT of the inline-style budget on a protected post: the oracle inlines
        # `wp-block-navigation` on `/2026/03/password-protected/` precisely because the
        # form never rendered and never enqueued `wp-block-buttons`/`wp-block-button`.
        # AD-01: the `post_password_required` filter (:887, :892) is gone.
        def post_password_required?(post) = post.present? && post.password_digest.present?

        # get_comments_number(): the legacy reads `$post->comment_count`, a column
        # WordPress maintains as the count of APPROVED comments of every type
        # (wp_update_comment_count_now(): "WHERE comment_approved = '1'").
        #
        # ⚠️ DEVIATION, deliberate. The rebuild's `comment_count` is an Active Record
        # counter_cache and counts EVERY row — the oracle reports 7 for the threaded
        # corpus post where the rebuild's column says 10. The legacy's NUMBER is the
        # specification, so it is computed, not read.
        def comments_number(post)
          return 0 if post.nil?

          Discussion::Comment.approved.where(post_id: post.id).count
        end

        # get_the_title(). Core registers wptexturize, convert_chars and trim on
        # `the_title` (wp-includes/default-filters.php:197..199) plus capital_P_dangit
        # at priority 11 (:170) — inlined, per AD-01.
        def the_title(post)
          return "" if post.nil?

          title = post.title.to_s
          title = "Protected: #{title}" if post.password_digest.present?
          title = "Private: #{title}" if post.status.to_s == "private"
          title = Sanitizing::Texturize.wptexturize(title)
          title = CommentText.convert_chars(title)
          CommentText.capital_p_dangit_title(title.strip)
        end

        # The `class` contribution both `textAlign` and a link colour make, shared by
        # six of these callbacks verbatim.
        def callback_classes
          classes = []
          classes << "has-text-align-#{attrs["textAlign"]}" if attrs.key?("textAlign")
          classes << "has-link-color" if link_color?
          classes
        end

        def link_color?
          attrs.dig("style", "elements", "link", "color", "text").present?
        end

        # Renders this block's inner blocks into the nil slots of `inner_content`,
        # optionally under a scoped child context. This is `WP_Block::render(array(
        # 'dynamic' => false ))` — the same splice `Renderers::Base` performs, but with
        # a context the parent block provides (`providesContext`).
        def inner_with(child_ctx = ctx)
          return block.inner_html.to_s if block.inner_blocks.empty?

          index = -1
          block.inner_content.map do |chunk|
            next chunk unless chunk.nil?

            index += 1
            Renderer.render_block(block.inner_blocks[index], child_ctx)
          end.join
        end
      end

      # ── core/comments ────────────────────────────────────────────────────────
      #
      # wp-includes/blocks/comments.php:28. Two guards, then — for every block that is
      # not the deprecated `core/post-comments` — the SAVED markup with its inner blocks
      # spliced in ("If this isn't the legacy block, we need to render the static
      # version of this block": `$block->render( array( 'dynamic' => false ) )`).
      class CommentsBlock < CommentBlock
        handles "core/comments"

        def render
          post_id = context_post_id
          return "" if post_id.nil?

          post = context_post
          return "" if !comments_open?(post) && comments_number(post).zero?

          # ⚠️ The legacy branch for `attributes.legacy` renders `comments_template()`,
          # i.e. a CLASSIC theme's comments.php (or the deprecated
          # wp-includes/theme-compat/comments.php fallback). There is no classic theme
          # in this system and no template hierarchy to resolve it against, so that
          # branch is NOT implemented; the static markup is rendered instead. The
          # corpus and the active theme never set `legacy`. Reported.
          inner_with
        end
      end

      # ── core/comment-template ────────────────────────────────────────────────
      #
      # wp-includes/blocks/comment-template.php:100 (the callback) and :19 (the
      # recursion). The one block in this family that recurses: a comment's replies
      # render the same inner blocks one level deeper, wrapped in a bare `<ol>`.
      class CommentTemplate < CommentBlock
        handles "core/comment-template"

        def render
          post_id = context_post_id
          return "" if post_id.nil? || post_id == 0
          # comment-template.php:110.
          return "" if post_password_required?(context_post)

          nodes = Query.nodes_for(post_id)
          return "" if nodes.empty?

          nodes = nodes.reverse if Options.get("comment_order").to_s == "desc"

          %(<ol #{wrapper_attributes}>#{render_comments(nodes, ThreadState.new, 1)}</ol>)
        end

        private

        # block_core_comment_template_render_comments(), comment-template.php:19.
        def render_comments(nodes, state, depth)
          thread_comments = Options.truthy?(Options.get("thread_comments"))
          max_depth = Options.get("thread_comments_depth").to_i

          nodes.map do |node|
            comment = node.comment
            body = inner_with(ctx.with(context: { "commentId" => comment.id }))

            # Classes BEFORE the recursion — the legacy says so at :54 and the alt
            # counters make it observable.
            classes = comment_class(comment, state, depth)

            if node.children.any? && thread_comments
              body += if depth < max_depth
                        %(<ol>#{render_comments(node.children, state, depth + 1)}</ol>)
                      else
                        render_comments(node.children, state, depth)
                      end
            end

            %(<li id="comment-#{comment.id}" #{classes}>#{body}</li>)
          end.join
        end

        # comment_class()/get_comment_class(), wp-includes/comment-template.php:520.
        # Returns the `class="…"` attribute, which is what the `false` echo argument
        # asks for.
        def comment_class(comment, state, depth)
          classes = []
          classes << (comment.kind.to_s.empty? ? "comment" : comment.kind.to_s)

          user = comment.user
          if user
            classes << "byuser"
            classes << "comment-author-#{sanitize_html_class(user.nicename, user.id)}"
            post = context_post
            classes << "bypostauthor" if post && comment.user_id == post.author_id
          end

          if state.alt.odd?
            classes << "odd"
            classes << "alt"
          else
            classes << "even"
          end
          state.alt += 1

          if depth == 1
            if state.thread_alt.odd?
              classes << "thread-odd"
              classes << "thread-alt"
            else
              classes << "thread-even"
            end
            state.thread_alt += 1
          end

          classes << "depth-#{depth}"

          %(class="#{classes.map { |c| esc_attr(c) }.join(" ")}")
        end

        # sanitize_html_class(), wp-includes/formatting.php: strip everything that is
        # not a valid class character; fall back to the supplied value if nothing is
        # left.
        def sanitize_html_class(value, fallback = "")
          sanitized = value.to_s.gsub(/%[a-fA-F0-9]{2}/, "").gsub(/[^A-Za-z0-9_-]/, "")
          sanitized.empty? ? fallback.to_s : sanitized
        end
      end

      # ── core/comment-author-name ─────────────────────────────────────────────
      # wp-includes/blocks/comment-author-name.php:18.
      class CommentAuthorName < CommentBlock
        handles "core/comment-author-name"

        def render
          return "" if ctx.context["commentId"].nil?

          comment = context_comment
          return "" if comment.nil?

          # wp_get_current_commenter() reads the comment_author cookie; the Wave 2
          # visitor is anonymous, so pending links are never shown.
          show_pending_links = false

          author = comment_author(comment)
          link = comment_author_url(comment)

          if !link.empty? && attrs["isLink"] && attrs["linkTarget"].present?
            author = %(<a rel="external nofollow ugc" href="#{esc_url(link)}" ) +
                     %(target="#{esc_attr(attrs["linkTarget"])}" >#{author}</a>)
          end
          # '0' === comment_approved: a comment awaiting moderation shows no markup at
          # all to anybody but its own author.
          author = Sanitizing::Kses.wp_kses(author, "strip") if comment.status == "pending" && !show_pending_links

          %(<div #{wrapper_attributes("class" => callback_classes.join(" "))}>#{author}</div>)
        end

        private

        # get_comment_author(), wp-includes/comment-template.php. No core filter is
        # registered on it, so the stored value is the value — unescaped, exactly as
        # the legacy sprintf's it into the anchor.
        def comment_author(comment)
          name = comment.author_name.to_s
          return name unless name.empty?
          return comment.user.display_name.to_s if comment.user

          "Anonymous"
        end

        # get_comment_author_url(): 'http://' alone means "no url", and the value is
        # esc_url()'d with the http/https allowlist before it is returned.
        def comment_author_url(comment)
          url = comment.author_url.to_s
          url = "" if url == "http://"
          Sanitizing::Formatting.esc_url(url, %w[http https]).to_s
        end
      end

      # ── core/comment-content ─────────────────────────────────────────────────
      # wp-includes/blocks/comment-content.php:18.
      class CommentContent < CommentBlock
        handles "core/comment-content"

        AWAITING_WITH_EMAIL = "Your comment is awaiting moderation."
        AWAITING_PREVIEW = "Your comment is awaiting moderation. This is a preview; " \
                           "your comment will be visible after it has been approved."

        def render
          return "" if ctx.context["commentId"].nil?

          comment = context_comment
          return "" if comment.nil?

          show_pending_links = false
          text = CommentText.call(comment.content)
          return "" if text.to_s.empty?

          moderation_note = ""
          if comment.status == "pending"
            # wp_get_current_commenter()['comment_author_email'] is empty for the
            # anonymous visitor, so it is always the preview wording.
            moderation_note = %(<p><em class="comment-awaiting-moderation">#{AWAITING_PREVIEW}</em></p>)
            text = Sanitizing::Kses.wp_kses(text, "strip") unless show_pending_links
          end

          %(<div #{wrapper_attributes("class" => callback_classes.join(" "))}>#{moderation_note}#{text}</div>)
        end
      end

      # ── core/comment-date ────────────────────────────────────────────────────
      # wp-includes/blocks/comment-date.php:18.
      class CommentDate < CommentBlock
        handles "core/comment-date"

        def render
          return "" if ctx.context["commentId"].nil?

          comment = context_comment
          return "" if comment.nil?

          time = Times.local(comment.submitted_at)
          formatted =
            if attrs["format"] == "human-diff"
              "#{Times.human_time_diff(time)} ago"
            else
              format = attrs["format"].to_s
              Php.date(time, format.empty? ? Options.get("date_format").to_s : format)
            end

          if attrs["isLink"]
            link = Urls.comment_link(comment, comment.post)
            formatted = %(<a href="#{esc_url(link)}">#{formatted}</a>)
          end

          # ⚠️ The only class this callback contributes is `has-link-color`; unlike its
          # siblings it never reads `textAlign`.
          extra = link_color? ? { "class" => "has-link-color" } : { "class" => "" }
          %(<div #{wrapper_attributes(extra)}><time datetime="#{esc_attr(Php.date(time, "c"))}">#{formatted}</time></div>)
        end
      end

      # ── core/comment-reply-link ──────────────────────────────────────────────
      # wp-includes/blocks/comment-reply-link.php:18 and
      # get_comment_reply_link(), wp-includes/comment-template.php:1755.
      class CommentReplyLink < CommentBlock
        handles "core/comment-reply-link"

        REPLY_TEXT = "Reply"
        REPLY_TO_TEXT = "Reply to %s"

        def render
          return "" if ctx.context["commentId"].nil?
          return "" if Options.falsy?(Options.get("thread_comments"))

          comment = context_comment
          return "" if comment.nil?

          depth = comment_depth(comment)
          max_depth = Options.get("thread_comments_depth").to_i
          # get_comment_reply_link() returns null at or past the maximum depth, and the
          # callback renders nothing when the link is empty.
          return "" if depth.zero? || max_depth <= depth

          post = comment.post
          return "" unless comments_open?(post)

          link = reply_link(comment, post)
          %(<div #{wrapper_attributes("class" => callback_classes.join(" "))}>#{link}</div>)
        end

        private

        # "Compute comment's depth iterating over its ancestors."
        def comment_depth(comment)
          depth = 1
          seen = Set.new([comment.id])
          parent = comment.parent
          while parent && !seen.include?(parent.id)
            seen << parent.id
            depth += 1
            parent = parent.parent
          end
          depth
        end

        def reply_link(comment, post)
          # `page_comments` is off, so the permalink is the post's own
          # (comment-template.php:1799).
          permalink = Urls.permalink(post)
          href = Urls.add_query_arg(permalink, "replytocom", comment.id)
          author = comment.author_name.to_s.presence || comment.user&.display_name.to_s.presence || "Anonymous"
          reply_to = REPLY_TO_TEXT.sub("%s", author)

          data = {
            "commentid" => comment.id,
            "postid" => post.id,
            "belowelement" => "comment-#{comment.id}",
            "respondelement" => "respond",
            "replyto" => reply_to
          }
          data_string = data.map { |k, v| %( data-#{k}="#{esc_attr(v)}") }.join.strip

          %(<a rel="nofollow" class="comment-reply-link" href="#{esc_url("#{href}#respond")}" ) +
            %(#{data_string} aria-label="#{esc_attr(reply_to)}">#{REPLY_TEXT}</a>)
        end
      end

      # ── core/comment-edit-link ───────────────────────────────────────────────
      #
      # wp-includes/blocks/comment-edit-link.php:19. The callback's first line is
      # `! current_user_can( 'edit_comment', … )` and returns '' when it fails.
      #
      # ⚠️ NOT a stub, and not an approximation: `Composition` may not depend on
      # `Access` (contexts are namespaces — nothing may depend on Access), and Wave 2
      # renders for an anonymous, read-only visitor for whom `edit_comment` is false on
      # every comment. So the legacy's answer for every render this system can perform
      # is the empty string, and that is what is implemented. Wiring an editor's view
      # needs the capability to arrive through the render context; reported.
      class CommentEditLink < CommentBlock
        handles "core/comment-edit-link"

        def render = ""
      end

      # ── core/comments-title ──────────────────────────────────────────────────
      # wp-includes/blocks/comments-title.php:17.
      class CommentsTitle < CommentBlock
        handles "core/comments-title"

        def render
          post = context_post
          # comments-title.php:19 — `post_password_required()` on the global post, which
          # on the singular template this block lives in is the context post.
          return "" if post_password_required?(post)

          count = comments_number(post)
          return "" if count.zero?

          show_post_title = attrs["showPostTitle"] == true
          show_comments_count = attrs["showCommentsCount"] == true
          title = the_title(post)

          text =
            if show_comments_count
              if show_post_title
                if count == 1
                  "One response to &#8220;#{title}&#8221;"
                else
                  "#{Php.number_format_i18n(count)} responses to &#8220;#{title}&#8221;"
                end
              elsif count == 1
                "One response"
              else
                "#{Php.number_format_i18n(count)} responses"
              end
            elsif show_post_title
              count == 1 ? "Response to &#8220;#{title}&#8221;" : "Responses to &#8220;#{title}&#8221;"
            elsif count == 1
              "Response"
            else
              "Responses"
            end

          tag = attrs.key?("level") ? "h#{Php.num_to_s(attrs["level"])}" : "h2"
          extra = { "class" => attrs["textAlign"].present? ? "has-text-align-#{attrs["textAlign"]}" : "" }
          %(<#{tag} id="comments" #{wrapper_attributes(extra)}>#{text}</#{tag}>)
        end
      end

      # ── core/comments-pagination ─────────────────────────────────────────────
      #
      # wp-includes/blocks/comments-pagination.php:18. Renders NOTHING when its inner
      # pagination links produce nothing, which — with `page_comments` off, as the
      # corpus has it — is always.
      class CommentsPagination < CommentBlock
        handles "core/comments-pagination"

        ARIA_LABEL = "Comments pagination"

        def render
          content = inner_with
          return "" if content.to_s.strip.empty?
          # comments-pagination.php:23.
          return "" if post_password_required?(context_post)

          extra = { "aria-label" => ARIA_LABEL, "class" => link_color? ? "has-link-color" : "" }
          %(<nav #{wrapper_attributes(extra)}>#{content}</nav>)
        end
      end

      # ── core/post-comments-form ──────────────────────────────────────────────
      #
      # wp-includes/blocks/post-comments-form.php:18 and comment_form(),
      # wp-includes/comment-template.php:2495.
      #
      # The form's `action` is `site_url('/wp-comments-post.php')` — verbatim, because
      # that string is what the oracle emits and what the golden records. Wave 3 wired
      # the endpoint at that literal path: `POST /wp-comments-post.php` →
      # Web::CommentsController#create (config/routes.rb), which reads the fields by the
      # legacy names rendered below — `comment`, `author`, `email`, `url`,
      # `wp-comment-cookies-consent`, `comment_post_ID`, `comment_parent`
      # (Discussion::Submission::FIELDS). The markup is unchanged: the wiring is the
      # route, not the form.
      #
      # The block's own wrapper attributes replace `class="comment-respond"` in the
      # generated form, exactly as the legacy `str_replace` does, "so that all styling
      # applied to the block is carried along when the comment form is moved to the
      # location of the 'Reply' link".
      class PostCommentsForm < CommentBlock
        handles "core/post-comments-form"

        REQUIRED_INDICATOR = %(<span class="required">*</span>)
        REQUIRED_MESSAGE = %(<span class="required-field-message">Required fields are marked ) +
                           %(<span class="required">*</span></span>)
        TITLE_REPLY = "Leave a Reply"
        CANCEL_REPLY = "Cancel reply"
        LABEL_SUBMIT = "Post Comment"
        EMAIL_NOTE = "Your email address will not be published."
        COOKIES_LABEL = "Save my name, email, and website in this browser for the next time I comment."

        def render
          post_id = context_post_id
          return "" if post_id.nil?

          post = context_post
          # post-comments-form.php:23 — BEFORE anything is enqueued: a form that does
          # not render enqueues no stylesheet, and the budget below counts on that.
          return "" if post_password_required?(post)
          # comment_form() exits without output when the post is invalid or comments
          # are closed (comment-template.php:2498).
          return "" if post.nil? || !comments_open?(post)

          classes = ["comment-respond"] + callback_classes
          wrapper = wrapper_attributes("class" => classes.join(" "))

          # This block's block.json declares THREE style handles, not one:
          # `"style": ["wp-block-post-comments-form", "wp-block-buttons",
          # "wp-block-button"]` (wp-includes/blocks/post-comments-form/block.json:52-56)
          # — the button block's CSS is what styles the form's submit button. They are
          # enqueued in array order when the block renders (WP_Block::render →
          # `wp_enqueue_style` per handle), which is why the golden singular head prints
          # post-comments-form, buttons, button consecutively. Renderer.render_block
          # enqueues `block.block_name` after this method returns non-empty; enqueueing
          # it here first keeps the three in declaration order (the collector
          # deduplicates the second call).
          ctx.styles.use("core/post-comments-form")
          ctx.styles.use("core/buttons")
          ctx.styles.use("core/button")
          # post-comments-form.php:52 — `wp_enqueue_script( 'comment-reply' )`, printed
          # by wp_footer(). Presentation::Footer is what renders the tag.
          ctx.scripts.use("comment-reply")

          # ⚠️ `class_container` is 'comment-respond'; the legacy renders the div with
          # that class and then str_replaces the whole attribute with the wrapper's.
          # Splicing the wrapper in directly is the same bytes with one fewer pass.
          +"\t<div id=\"respond\" #{wrapper}>\n\t\t" + title(post) + form(post) + "\t</div><!-- #respond -->\n\t"
        end

        private

        # ⚠️ `_get_comment_reply_id()` reads $_GET['replytocom']. A rendered block has no
        # request in this system, so the reply-to id is always 0 — which is the value
        # for every one of the 18 literal screens, all of which are plain GETs of the
        # permalink. The three places it shows are marked below.
        def reply_to_id = 0

        def title(post)
          # comment_form_title(): with no replytocom, the plain reply title.
          cancel_url = "#{URI.parse(Urls.permalink(post)).request_uri}#respond"
          cancel = %(<a rel="nofollow" id="cancel-comment-reply-link" href="#{esc_url(cancel_url)}") +
                   %( style="display:none;">#{CANCEL_REPLY}</a>)
          # `thread_comments` gates the cancel link (comment-template.php:2705).
          cancel_markup = Options.truthy?(Options.get("thread_comments")) ? " <small>#{cancel}</small>" : ""
          %(<h3 id="reply-title" class="comment-reply-title">#{TITLE_REPLY}#{cancel_markup}</h3>)
        end

        def form(post)
          require_name_email = Options.truthy?(Options.get("require_name_email"))
          required_attribute = " required" # html5
          indicator = " #{REQUIRED_INDICATOR}"
          required_text = " #{REQUIRED_MESSAGE}"

          out = +%(<form action="#{esc_url(Urls.site_url("/wp-comments-post.php"))}" method="post" ) +
                %(id="commentform" class="comment-form">)
          # comment_registration is off and the visitor is anonymous, so the
          # `must_log_in` and `logged_in_as` branches are unreachable here.
          out << %(<p class="comment-notes"><span id="email-notes">#{EMAIL_NOTE}</span>#{required_text}</p>)
          out << %(<p class="comment-form-comment"><label for="comment">Comment#{indicator}</label> ) +
                 %(<textarea id="comment" name="comment" cols="45" rows="8" maxlength="65525") +
                 %(#{required_attribute}></textarea></p>)
          out << fields(require_name_email, indicator, required_attribute).map { |f| "#{f}\n" }.join
          out << submit_field(post)
          out << "</form>"
          out
        end

        # comment_form()'s $fields (comment-template.php:2532). Each is
        # `sprintf('<p class="…">%s %s</p>', label, input)` — note the SPACE between the
        # label and the input, and that only `required` is conditional.
        def fields(req, indicator, required_attribute)
          [
            %(<p class="comment-form-author">) +
              %(<label for="author">Name#{req ? indicator : ""}</label> ) +
              %(<input id="author" name="author" type="text" value="" size="30" maxlength="245" ) +
              %(autocomplete="name"#{req ? required_attribute : ""} /></p>),
            %(<p class="comment-form-email">) +
              %(<label for="email">Email#{req ? indicator : ""}</label> ) +
              %(<input id="email" name="email" type="email" value="" size="30" maxlength="100" ) +
              %(aria-describedby="email-notes" autocomplete="email"#{req ? required_attribute : ""} /></p>),
            %(<p class="comment-form-url">) +
              %(<label for="url">Website</label> ) +
              %(<input id="url" name="url" type="url" value="" size="30" maxlength="200" ) +
              %(autocomplete="url" /></p>),
            cookies_field
          ].compact
        end

        # The cookies field exists only while `show_comments_cookies_opt_in` is on
        # (comment-template.php:2573).
        def cookies_field
          return nil if Options.falsy?(Options.get("show_comments_cookies_opt_in"))

          %(<p class="comment-form-cookies-consent"><input id="wp-comment-cookies-consent" ) +
            %(name="wp-comment-cookies-consent" type="checkbox" value="yes" /> ) +
            %(<label for="wp-comment-cookies-consent">#{COOKIES_LABEL}</label></p>)
        end

        # comments_block_form_defaults()/post_comments_form_block_form_defaults(): in a
        # BLOCK THEME the submit button carries the button block's classes and the
        # submit field is a `wp-block-button` paragraph (comments.php:110,
        # post-comments-form.php:80).
        def submit_field(post)
          button = %(<input name="submit" type="submit" id="submit" ) +
                   %(class="wp-block-button__link wp-element-button" value="#{LABEL_SUBMIT}" />)
          %(<p class="form-submit wp-block-button">#{button} #{id_fields(post)}</p>)
        end

        # get_comment_id_fields(), comment-template.php:2046 — single quotes and the
        # trailing newlines are the legacy's own.
        def id_fields(post)
          "<input type='hidden' name='comment_post_ID' value='#{post.id}' id='comment_post_ID' />\n" \
            "<input type='hidden' name='comment_parent' id='comment_parent' value='#{reply_to_id}' />\n"
        end
      end

      # ── core/post-comments-count ─────────────────────────────────────────────
      # wp-includes/blocks/post-comments-count.php:18.
      class PostCommentsCount < CommentBlock
        handles "core/post-comments-count"

        def render
          return "" if context_post_id.nil?

          # ⚠️ This callback builds its class with `.=` on a STRING, so it never emits
          # `has-link-color` — only `has-text-align-*`.
          extra = { "class" => attrs.key?("textAlign") ? "has-text-align-#{attrs["textAlign"]}" : "" }
          %(<div #{wrapper_attributes(extra)}>#{comments_number(context_post)}</div>)
        end
      end

      # ── core/post-comments-link ──────────────────────────────────────────────
      # wp-includes/blocks/post-comments-link.php:18.
      class PostCommentsLink < CommentBlock
        handles "core/post-comments-link"

        def render
          post_id = context_post_id
          return "" if post_id.nil?

          post = context_post
          return "" unless comments_open?(post)

          count = comments_number(post)
          link = Urls.comments_link(post, count)
          title = the_title(post)

          html =
            if count.zero?
              %(No comments<span class="screen-reader-text"> on #{title}</span>)
            else
              plural = Php.n_("comment", "comments", count)
              %(#{esc_html(Php.number_format_i18n(count))} #{plural}) +
                %(<span class="screen-reader-text"> on #{title}</span>)
            end

          # ⚠️ The legacy concatenates the href WITHOUT quotes:
          #   '<div ' . $wrapper . '><a href=' . esc_url( $link ) . '>' . …
          # (post-comments-link.php:60). Reproduced, defect and all — this is markup
          # the golden files record.
          "<div #{wrapper_attributes(callback_extra)}><a href=#{esc_url(link)}>#{html}</a></div>"
        end

        private

        def callback_extra = { "class" => callback_classes.join(" ") }
      end

      # ── block style variations (section styles) ────────────────────────────────
      #
      # wp-includes/block-supports/block-style-variations.php — the support that turns a
      # `className: "is-style-<slug>"` attribute into a per-INSTANCE stylesheet when the
      # theme defines data for that variation. It is what puts
      # `<style id="block-style-variation-styles-inline-css">` into the three singular
      # goldens: the single template's post-terms block carries
      # `"className":"is-style-post-terms-1"` and twentytwentyfive ships
      # styles/blocks/post-terms-1.json for it.
      #
      # ⚠️ NOT comment-specific — it runs for EVERY block (`render_block_data`,
      # block-style-variations.php:265). It lives in this file only under the precedent
      # `Php`/`Urls` set at the top: this agent owns exactly one renderer file. It
      # belongs beside `Renderer` or in the styling seam; see the report.
      #
      # Two legacy filters are folded into `Renderer.render_block` (AD-01 — both are
      # core's own, registered unconditionally):
      #   * `wp_render_block_style_variation_support_styles` (:79, on render_block_data)
      #     — BEFORE the block renders: allocate the instance name, generate the scoped
      #     CSS, append the instance class to `attrs.className`.
      #   * `wp_render_block_style_variation_class_name` (:217, on render_block) — AFTER:
      #     ensure the instance class reaches the rendered markup's first tag.
      #
      # Implication 1 (no global mutable state): the legacy parks the generated CSS in
      # `$wp_styles` via `wp_add_inline_style('block-style-variation-styles', …)` (:193).
      # Here it keys off `ctx.styles` in a weak map — the same seam
      # `NavigationBlocks::RenderScope` documents — and `Presentation::Page` reads it
      # after the render, exactly as it reads the collectors.
      module StyleVariations
        # `\bis-style-(?!default)(\S+)\b` — block-style-variations.php:23.
        VARIATION_CLASS = /\bis-style-(?!default)(\S+)\b/
        # `\bis-style-(\S+?--\d+)\b` — :231, an already-instanced class.
        INSTANCE_CLASS = /\bis-style-(\S+?--\d+)\b/

        THEME_DIR = File.join(Composition::Renderers::LayoutBlocks::LEGACY_ROOT,
                              "wp-content", "themes", "twentytwentyfive")

        STORE = ObjectSpace::WeakKeyMap.new

        class << self
          # `wp_render_block_style_variation_support_styles()`,
          # block-style-variations.php:79. Returns the block to render — a copy with the
          # instance class appended to `attrs.className` when a variation fired, the
          # given block untouched otherwise (parsed templates may be shared; the legacy
          # mutates `$parsed_block`, its per-request copy).
          def apply(block, ctx)
            classes = block.attrs.is_a?(Hash) ? block.attrs["className"] : nil
            return block unless classes.is_a?(String)

            names = classes.scan(VARIATION_CLASS).flatten
            return block if names.empty?

            # ":91 — Only the first block style variation with data is supported."
            variation = nil
            data = nil
            names.each do |name|
              found = variations.dig(block.block_name.to_s, name)
              next if found.nil? || found.empty?

              variation = name
              data = deep_dup(found)
              break
            end
            return block if data.nil?

            resolve_refs(data, merged_theme_json)

            # :110 — `wp_unique_id()`. ⚠️ ONE counter for the whole request, shared with
            # navigation's `modal-` and search's input ids (functions.php:8177) — which
            # is why the singular golden reads `post-terms-1--2`: the header's
            # navigation took 1.
            instance = NavigationBlocks.scope(ctx).unique_id("#{variation}--")
            class_name = "is-style-#{instance}"

            css = generate_css(block.block_name.to_s, instance, data, class_name)
            return block if css.empty?

            (STORE[ctx.styles] ||= []) << css

            Composition::Parser::Block.new(
              block_name: block.block_name,
              attrs: block.attrs.merge("className" => "#{classes} #{class_name}"),
              inner_blocks: block.inner_blocks, inner_html: block.inner_html,
              inner_content: block.inner_content
            )
          end

          # `wp_render_block_style_variation_class_name()`, block-style-variations.php:217
          # — the instance class must reach the RENDERED markup even when the block's own
          # callback ignored `className`.
          def apply_class_name(html, block)
            return html if html.to_s.empty?

            classes = block.attrs.is_a?(Hash) ? block.attrs["className"] : nil
            return html unless classes.is_a?(String)

            match = classes[INSTANCE_CLASS]
            return html if match.nil? || html.include?(match)

            processor = Markup::TagProcessor.new(html)
            return html unless processor.next_tag

            existing = processor.get_attribute("class")
            processor.set_attribute("class", existing.to_s.empty? ? match : "#{existing} #{match}")
            processor.get_updated_html
          end

          # What `wp_head` prints as `block-style-variation-styles-inline-css` — every
          # instance's stylesheet, in registration order, exactly as repeated
          # `wp_add_inline_style()` calls concatenate (class-wp-styles.php joins with
          # "\n").
          def css(ctx)
            Array(STORE[ctx.styles]).join("\n").presence
          end

          # The merged tree's `styles.blocks.<type>.variations`, built the way
          # WP_Theme_JSON_Resolver::theme_data() builds it (:282,
          # `inject_variations_from_block_style_variation_files()`, :947): the theme's own
          # theme.json variations, then each styles/ partial that names `blockTypes`,
          # with top-level `styles.variations[name]` and block-level
          # `styles.blocks[type].variations[name]` overriding the partial in that order.
          # `inject_variations_from_block_styles_registry` (:988) contributes nothing:
          # core registers its button/image styles with CSS classes, never `style_data`,
          # so every entry hits the `empty( $variation['style_data'] )` continue.
          def variations
            @variations ||= begin
              theme_json = theme_theme_json
              data = {}
              (theme_json.dig("styles", "blocks") || {}).each do |type, node|
                (node["variations"] || {}).each { |name, styles| Styling::PhpCompat.array_set(data, [type, name], styles) }
              end
              partial_files.each do |path|
                partial = JSON.parse(File.read(path))
                styles = partial["styles"]
                types = partial["blockTypes"]
                next if styles.nil? || styles.empty? || types.nil? || types.empty?

                # :957 — `$variation['slug'] ?? _wp_to_kebab_case( $variation['title'] )`.
                # Every twentytwentyfive partial carries a slug, so the kebab-case
                # fallback is not ported; a slugless partial would raise here rather
                # than silently misfile.
                name = partial.fetch("slug")
                Array(types).each do |type|
                  merged = deep_dup(styles)
                  top = theme_json.dig("styles", "variations", name)
                  merged = Styling::PhpCompat.array_replace_recursive(merged, top) if top.is_a?(Hash) && !top.empty?
                  block_level = theme_json.dig("styles", "blocks", type, "variations", name)
                  merged = Styling::PhpCompat.array_replace_recursive(merged, block_level) if block_level.is_a?(Hash) && !block_level.empty?
                  Styling::PhpCompat.array_set(data, [type, name], merged)
                end
              end
              data.freeze
            end
          end

          def reset! = (@variations = @merged_theme_json = nil)

          private

          # block-style-variations.php:112-158 — the config WP_Theme_JSON receives:
          # `elements` and `blocks` relocated so custom selectors keep working, the rest
          # nested under the block's own `variations.<instance>`.
          def generate_css(block_name, instance, variation_data, class_name)
            elements_data = variation_data.delete("elements") || {}
            blocks_data = variation_data.delete("blocks") || {}
            Styling::PhpCompat.array_set(blocks_data, [block_name, "variations", instance], variation_data)

            config = {
              "version" => Styling::ThemeJson::LATEST_SCHEMA,
              "settings" => { "spacing" => { "blockGap" => true } },
              "styles" => { "elements" => elements_data, "blocks" => blocks_data },
            }
            viewport = merged_theme_json.dig("settings", "viewport")
            config["settings"]["viewport"] = viewport if viewport

            # :170 — get_stylesheet( array('styles'), array('custom'), … ). The Ruby port
            # reproduces it byte-for-byte for the corpus's one instance; verified against
            # golden-web-singular.html:157.
            Styling::Stylesheet.new(
              Styling::ThemeJson.new(config, "blocks"), blocks_metadata, block_definitions
            ).get_stylesheet(
              %w[styles], %w[custom],
              "include_block_style_variations" => true,
              "skip_root_layout_styles" => true,
              "scope" => ".#{class_name}"
            )
          end

          # `wp_resolve_block_style_variation_ref_values()`, block-style-variations.php:36.
          def resolve_refs(node, theme_json)
            node.each do |key, value|
              next unless value.is_a?(Hash)

              if value.key?("ref")
                ref = value["ref"]
                resolved = ref.is_a?(String) && !ref.empty? &&
                           Styling::PhpCompat.array_get(theme_json, ref.split("."))
                resolved ? node[key] = resolved : node.delete(key)
              else
                resolve_refs(value, theme_json)
              end
            end
          end

          # The raw merged document refs resolve against. The legacy uses
          # `WP_Theme_JSON_Resolver::get_merged_data()->get_raw_data()`; core-then-theme
          # replace-recursive is the slice of that cascade a `ref` path can reach here
          # (no user styles exist — the corpus registers none).
          def merged_theme_json
            @merged_theme_json ||= Styling::PhpCompat.array_replace_recursive(
              LayoutBlocks::GlobalStyles.core_theme_json, theme_theme_json
            )
          end

          def theme_theme_json = LayoutBlocks::GlobalStyles.theme_theme_json

          def partial_files
            Dir[File.join(THEME_DIR, "styles", "**", "*.json")].sort
          end

          def blocks_metadata
            @blocks_metadata ||= Styling::BlocksMetadata.build(block_definitions)
          end

          def block_definitions
            @block_definitions ||= JSON.parse(File.read(Rails.root.join("db", "blocks", "types.json")))
          end

          def deep_dup(value)
            case value
            when Hash then value.transform_values { |v| deep_dup(v) }
            when Array then value.map { |v| deep_dup(v) }
            else value
            end
          end
        end
      end
    end
  end
end
