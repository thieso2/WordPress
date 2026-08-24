# frozen_string_literal: true

require "seeding/legacy"
require "seeding/report"
require "seeding/transformations"
require "seeding/php_serialization"

module Seeding
  # The oracle corpus seeding pipeline. data_migration_plan.md § ETL strategy.
  #
  # Deliberately NOT raw SQL-to-SQL: routing the load through the models means every
  # CHECK, unique index, FK and validation in target_data_model.md is exercised by the
  # seeding itself. The pipeline is therefore also the first honest test of the schema.
  #
  # Idempotent by the simplest available guarantee: it truncates the target tables on
  # every run. That is available precisely because there is no production data — the one
  # genuine benefit of having no live deployment.
  class Pipeline
    include Transformations

    T = Transformations

    # AD-03: every postmeta key core itself owns is promoted to a column, association or
    # table. These are therefore NOT copied into the residual bucket.
    PROMOTED_POST_META = %w[
      _thumbnail_id _wp_page_template _wp_trash_meta_status _wp_trash_meta_time
      _wp_old_slug _wp_old_date _edit_lock _edit_last
      _wp_attached_file _wp_attachment_metadata _wp_attachment_image_alt
      _wp_desired_post_slug _pingme _encloseme _menu_item_orphaned
      _menu_item_type _menu_item_menu_item_parent _menu_item_object_id _menu_item_object
      _menu_item_target _menu_item_classes _menu_item_xfn _menu_item_url
      _wp_attachment_backup_sizes _wp_attachment_context
    ].freeze

    PROMOTED_USER_META = %w[locale nickname first_name last_name description
                            session_tokens rich_editing syntax_highlighting].freeze

    # T-11: discarded sources. Row counts are still REPORTED — a rewrite_rules option
    # that had grown past the 150 KB autoload threshold is evidence about the corpus
    # even though the value is discarded.
    DISCARDED_OPTIONS = %w[rewrite_rules cron].freeze
    TRANSIENT_PREFIXES = %w[_transient_ _site_transient_].freeze

    CONTENT_TYPES = { "post" => "Publishing::Article", "page" => "Publishing::Page" }.freeze

    attr_reader :report

    def initialize(io: $stdout)
      @io = io
      @report = Report.new
      @map = Hash.new { |h, k| h[k] = {} } # :posts => {legacy_id => new_id}
    end

    def call
      inventory
      truncate_target
      ActiveRecord::Base.transaction do
        load_users
        load_settings
        load_taxonomies_and_terms
        load_posts
        load_assets
        attach_featured_assets
        load_term_assignments
        load_comments
        load_menus
        load_composition
        load_syndication_and_routing
        load_data_requests
        remap_identifier_settings
        recompute_counter_caches
        raise ActiveRecord::Rollback unless @report.clean?
      end
      verify
      @report
    end

    # ── 1. Inventory — emitted BEFORE loading anything ───────────────────────────
    def inventory
      say "── inventory (before load) ───────────────────────────────────────"
      %w[posts postmeta comments commentmeta terms term_taxonomy term_relationships
         termmeta users usermeta options links].each do |t|
        c = Legacy.count_of(t)
        say format("  %-22s %s", t, c.nil? ? "(absent)" : c)
        @report.count!("legacy.#{t}", c.to_i) if c
      end

      # T-02 inventory: how many a: / O: / scalar payloads exist in the corpus.
      %w[postmeta usermeta termmeta commentmeta].each { |t| inventory_serialized(t, "meta_value") }
      inventory_serialized("options", "option_value")

      zero = Legacy.connection.select_value(
        "SELECT COUNT(*) FROM #{Legacy.table("posts")} WHERE post_date_gmt = '#{T::ZERO_DATE}'"
      ).to_i
      @report.count!("legacy.zero_dates(post_date_gmt)", zero)
      say "  zero dates (post_date_gmt): #{zero}"

      orphaned = Legacy.connection.select_value(
        "SELECT COUNT(*) FROM #{Legacy.table("postmeta")} WHERE meta_key = '_menu_item_orphaned'"
      ).to_i
      @report.count!("legacy._menu_item_orphaned tombstones", orphaned)
      say "  _menu_item_orphaned tombstones: #{orphaned}   (T-04: dropped, FK makes them unrepresentable)"
      say
    end

    def inventory_serialized(table, column)
      rows = Legacy.rows("SELECT #{column} AS v FROM #{Legacy.table(table)}") rescue return
      a = o = scalar = 0
      rows.each do |r|
        v = r["v"].to_s
        if v.start_with?("a:") then a += 1
        elsif v.start_with?("O:") then o += 1
        else scalar += 1
        end
      end
      @report.count!("serialized.#{table}.array", a)
      @report.count!("serialized.#{table}.object", o)
      @report.count!("serialized.#{table}.scalar", scalar)
      say format("  %-22s a:=%-5d O:=%-5d scalar=%d", "#{table}.#{column}", a, o, scalar)
      return if o.zero?

      @report.note!("#{table} carries #{o} O: payload(s) — T-02: each distinct class is a human decision.")
    end

    # ── 2. Idempotency ───────────────────────────────────────────────────────────
    def truncate_target
      tables = %w[post_status_transitions post_attributes revisions moderation_verdicts
                  comment_rate_limits comments term_assignments terms taxonomies
                  asset_variants menu_items menus themes templates patterns redirects
                  embed_caches data_requests application_passwords sessions
                  role_assignments settings]
      ActiveRecord::Base.connection.execute("TRUNCATE #{tables.join(", ")} RESTART IDENTITY CASCADE")
      # posts <-> assets carry FKs in both directions, so they truncate together.
      ActiveRecord::Base.connection.execute("TRUNCATE posts, assets, users RESTART IDENTITY CASCADE")
    end


    # ── 3. Load, in FK order ─────────────────────────────────────────────────────

    # T-03 + T-10. wp_users -> users; usermeta profile keys promoted to columns;
    # {prefix}capabilities exploded into role_assignments; session_tokens into sessions.
    def load_users
      rows = Legacy.rows("SELECT * FROM #{Legacy.table("users")} ORDER BY ID")
      meta = meta_for("usermeta", "user_id", rows.map { |r| r["ID"].to_i })

      rows.each do |r|
        legacy_id = r["ID"].to_i
        m = meta[legacy_id]
        digest = T.password_digest(r["user_pass"])
        @report.note!("user #{r["user_login"]} loaded with authentication disabled (T-10)") if T.authentication_disabled?(digest)

        registered = begin
          T.zero_date_to_null(r["user_registered"])
        rescue ArgumentError => e
          @report.dead_letter!(source: "users", legacy_id: legacy_id, reason: e.message, payload: r["user_registered"])
          next
        end

        user = Identity::User.new(
          login: r["user_login"], email: r["user_email"], password_digest: digest,
          nicename: r["user_nicename"], display_name: T.text(r["display_name"]),
          url: r["user_url"].presence, status: r["user_status"].to_i.zero? ? "active" : "inactive",
          registered_at: registered || Time.current,
          locale: m["locale"]&.first.presence
        )
        unless user.save
          @report.dead_letter!(source: "users", legacy_id: legacy_id,
                               reason: user.errors.full_messages.join("; "))
          next
        end
        @map[:users][legacy_id] = user.id
        @report.count!("loaded.users")

        # T-03: the serialized role => true map becomes one row per truthy key.
        m.each do |key, values|
          site_id = T.site_id_from_capabilities_key(key, Legacy::PREFIX)
          next unless key.end_with?("capabilities") && !site_id.nil? || key == "#{Legacy::PREFIX}capabilities"

          map = decode(values.first, source: "usermeta[#{key}]", legacy_id: legacy_id)
          next unless map.is_a?(Hash)

          map.each do |role, truthy|
            next unless truthy

            Identity::RoleAssignment.create!(user: user, role: role.to_s, site_id: site_id)
            @report.count!("loaded.role_assignments")
            # "A role name not in the known role set -> LOAD IT ANYWAY and report it.
            #  An unknown role is data, not corruption."
            unless %w[administrator editor author contributor subscriber].include?(role.to_s)
              @report.note!("unknown role #{role.inspect} loaded for #{r["user_login"]} (T-03)")
            end
          end
        end

        # usermeta['session_tokens'] -> sessions rows.
        if (tokens = m["session_tokens"]&.first)
          decoded = decode(tokens, source: "usermeta[session_tokens]", legacy_id: legacy_id)
          (decoded.is_a?(Hash) ? decoded : {}).each do |digest_key, info|
            expiry = info.is_a?(Hash) ? info["expiration"] : nil
            Identity::Session.create!(
              user: user, token_digest: digest_key.to_s,
              expires_at: expiry ? Time.zone.at(expiry.to_i) : 14.days.from_now,
              ip: (info.is_a?(Hash) ? info["ip"].presence : nil),
              user_agent: (info.is_a?(Hash) ? info["ua"] : nil)
            )
            @report.count!("loaded.sessions")
          end
        end
      end
    end

    # T-11 discards + T-02 decoding. AD-06 bars the routing table and the job queue.
    def load_settings
      Legacy.rows("SELECT option_id, option_name, option_value, autoload FROM #{Legacy.table("options")}").each do |r|
        name = r["option_name"].to_s
        legacy_id = r["option_id"].to_i

        if DISCARDED_OPTIONS.include?(name)
          @report.count!("discarded.options.#{name}")
          @report.note!("option #{name} discarded (T-11/AD-06) — #{r["option_value"].to_s.bytesize} bytes in the corpus")
          next
        end
        if TRANSIENT_PREFIXES.any? { |p| name.start_with?(p) }
          @report.count!("discarded.options.transients")
          next
        end
        if Configuration::Setting::PROTECTED_NAMES.include?(name)
          @report.count!("discarded.options.protected")
          next
        end

        value = decode(r["option_value"], source: "options", legacy_id: legacy_id)
        next if value.nil? && r["option_value"].to_s.start_with?("O:")

        setting = Configuration::Setting.new(
          name: name, value: value,
          # AD-06 / BR-OPT-06: an EXPLICIT policy. The legacy's varchar carries
          # yes/no/auto/auto-on/auto-off/on/off depending on version.
          autoload: %w[yes on auto auto-on].include?(r["autoload"].to_s)
        )
        if setting.save
          @report.count!("loaded.settings")
        else
          @report.dead_letter!(source: "options", legacy_id: legacy_id,
                               reason: setting.errors.full_messages.join("; "), payload: name)
        end
      end
      # The 150 KB threshold is observable in the corpus; record where it fell.
      big = Configuration::Setting.autoloaded.select { |s| s.value.to_s.bytesize > 150 * 1024 }
      @report.note!("#{big.length} autoloaded setting(s) exceed the legacy's 150 KB threshold " \
                    "(BR-OPT-06) and remain autoloaded here — AD-06 makes the policy explicit.") if big.any?
    end

    # T-06: wp_terms + wp_term_taxonomy -> ONE terms row per (term, taxonomy) pair.
    def load_taxonomies_and_terms
      tt = Legacy.rows(<<~SQL)
        SELECT tt.term_taxonomy_id, tt.term_id, tt.taxonomy, tt.description, tt.parent, tt.count,
               t.name, t.slug
        FROM #{Legacy.table("term_taxonomy")} tt
        JOIN #{Legacy.table("terms")} t ON t.term_id = tt.term_id
        ORDER BY tt.parent, tt.term_taxonomy_id
      SQL

      tt.map { |r| r["taxonomy"] }.uniq.each do |name|
        Classification::Taxonomy.create!(
          name: name,
          hierarchical: %w[category nav_menu wp_template_part_area wp_pattern_category].include?(name),
          object_types: %w[Publishing::Post]
        )
        @report.count!("loaded.taxonomies")
      end
      taxonomies = Classification::Taxonomy.pluck(:name, :id).to_h

      # nav_menu terms become Presentation::Menu, not Classification::Term — AD-02
      # splits the menu model out entirely.
      menu_rows, term_rows = tt.partition { |r| r["taxonomy"] == "nav_menu" }
      menu_rows.each do |r|
        menu = Presentation::Menu.create!(name: r["name"], slug: r["slug"])
        @map[:menus][r["term_taxonomy_id"].to_i] = menu.id
        @report.count!("loaded.menus")
      end

      # Two passes: parents first, so the FK resolves. `parent` is an id into
      # term_taxonomy and is remapped to the new terms.id.
      pending = term_rows.dup
      2.times do
        pending = pending.reject do |r|
          ttid = r["term_taxonomy_id"].to_i
          parent_ttid = r["parent"].to_i
          parent_id = parent_ttid.zero? ? nil : @map[:terms][parent_ttid]
          next false if parent_ttid.positive? && parent_id.nil?

          # ⚠️ The term KEEPS the legacy `wp_terms.term_id`. Unlike post ids (masked as
          # `<ID>` by the parity normalizer's stripAutoincrementIds rule), term ids are
          # LITERAL bytes of the golden screens: get_body_class() emits `tag-6` /
          # `category-3` (post-template.php:761,769), and the page-list block compares
          # `get_queried_object_id() === $page->ID` (blocks/page-list.php:283) — an id
          # COLLISION in the oracle's data (term 2 'top-category' vs page 2
          # 'sample-page') that marks Sample Page `current-menu-item` on the category
          # archive. Both are reproducible only if the ids survive the migration.
          # In this corpus term_id == term_taxonomy_id for every row, so the T-06 merge
          # loses nothing by carrying it.
          term = Classification::Term.new(
            id: r["term_id"].to_i,
            taxonomy_id: taxonomies.fetch(r["taxonomy"]), parent_id: parent_id,
            name: r["name"], slug: r["slug"], description: T.text(r["description"])
          )
          if term.save
            @map[:terms][ttid] = term.id
            @report.count!("loaded.terms")
          else
            @report.dead_letter!(source: "term_taxonomy", legacy_id: ttid,
                                 reason: term.errors.full_messages.join("; "),
                                 payload: "#{r["taxonomy"]}/#{r["slug"]}")
          end
          true
        end
      end
      pending.each do |r|
        # "A parent pointing at a non-existent or cross-taxonomy row -> set NULL and report."
        term = Classification::Term.create!(
          id: r["term_id"].to_i,
          taxonomy_id: taxonomies.fetch(r["taxonomy"]), parent_id: nil,
          name: r["name"], slug: r["slug"], description: T.text(r["description"])
        )
        @map[:terms][r["term_taxonomy_id"].to_i] = term.id
        @report.count!("loaded.terms")
        @report.note!("term #{r["slug"]} had an unresolvable parent (#{r["parent"]}); loaded with parent NULL (T-06)")
      end
      # Explicit ids bypass the sequence; realign it so a future INSERT cannot collide.
      Classification::Term.connection.reset_pk_sequence!(Classification::Term.table_name)
    end


    # AD-02, the decision the rest of the model hangs from: CONTENT types stay in
    # `posts` under STI; the eleven machinery types go to tables shaped like what they
    # are. This method is the proof of that split (RISK-003).
    def load_posts
      rows = Legacy.rows("SELECT * FROM #{Legacy.table("posts")} ORDER BY post_parent, ID")
      all_meta = meta_for("postmeta", "post_id", rows.map { |r| r["ID"].to_i })
      content = rows.select { |r| CONTENT_TYPES.key?(r["post_type"]) }

      # Two passes for the self-referential parent FK.
      pending = content.dup
      2.times do
        pending = pending.reject { |r| insert_post(r, all_meta) }
      end
      pending.each { |r| insert_post(r, all_meta, force_root: true) }

      @posts_meta = all_meta
      @legacy_rows = rows
      load_revisions(rows, all_meta)
    end

    def insert_post(r, all_meta, force_root: false)
      legacy_id = r["ID"].to_i
      parent_legacy = r["post_parent"].to_i
      parent_id = parent_legacy.zero? ? nil : @map[:posts][parent_legacy]
      return false if parent_legacy.positive? && parent_id.nil? && !force_root

      m = all_meta[legacy_id]
      begin
        published_at = T.zero_date_to_null(r["post_date_gmt"])
        modified_at  = T.zero_date_to_null(r["post_modified_gmt"])
        status       = T.post_status(r["post_status"])
      rescue ArgumentError => e
        @report.dead_letter!(source: "posts", legacy_id: legacy_id, reason: e.message,
                             payload: "#{r["post_type"]}/#{r["post_status"]}")
        return true
      end

      # AD-03: _wp_trash_meta_status / _wp_trash_meta_time become columns, set together.
      before_trash = m["_wp_trash_meta_status"]&.first
      trashed_at = m["_wp_trash_meta_time"]&.first
      if status == "trashed"
        before_trash = T.post_status(before_trash || "draft")
        trashed_at = trashed_at ? Time.zone.at(trashed_at.to_i) : Time.current
      else
        before_trash = nil
        trashed_at = nil
      end

      post = CONTENT_TYPES.fetch(r["post_type"]).constantize.new(
        author_id: @map[:users][r["post_author"].to_i], parent_id: parent_id,
        title: T.text(r["post_title"]), slug: T.slug_or_null(r["post_name"]),
        content: T.text(r["post_content"]), excerpt: T.text(r["post_excerpt"]),
        status: status, published_at: published_at, modified_at: modified_at || Time.current,
        trashed_at: trashed_at, status_before_trash: before_trash,
        comment_status: r["comment_status"].to_s,
        password_digest: T.post_password_digest(r["post_password"]),
        menu_order: r["menu_order"].to_i,
        guid: T.fresh_guid,                       # T-07
        template_slug: m["_wp_page_template"]&.first.presence,
        # AD-03 promoted `comment_status` and dropped `ping_status` — but the value is
        # still OBSERVABLE output: `feed_links_extra()` prints a per-post comments feed
        # link when `comments_open() || pings_open() || comment_count > 0`
        # (wp-includes/general-template.php:3577), and the corpus's privacy-policy page
        # reaches that link through `pings_open()` ALONE (comment_status=closed,
        # comment_count=0, ping_status=open). So the column value is parked in the
        # residual bucket rather than lost; Presentation::Head#comments_feed? reads it.
        residual_attributes: { "ping_status" => r["ping_status"].to_s }
      )
      # BR-MIGRATE-029/030 must not re-fire during a load: the corpus's stored status is
      # the fact, not a request to re-evaluate the 60-second threshold against *now*.
      post.define_singleton_method(:resolve_scheduled_status) { nil }

      unless post.save
        @report.dead_letter!(source: "posts", legacy_id: legacy_id,
                             reason: post.errors.full_messages.join("; "),
                             payload: "#{r["post_type"]}/#{r["post_name"]}")
        return true
      end
      @map[:posts][legacy_id] = post.id
      @report.count!("loaded.posts.#{r["post_type"]}")

      load_post_attributes(post, m, legacy_id)
      # AD-03: _wp_old_slug / _wp_old_date become Routing::Redirect rows.
      Array(m["_wp_old_slug"]).each do |old|
        next if old.to_s.empty?

        Routing::Redirect.create!(from_path: "/#{old}", post_id: post.id) rescue nil
        @report.count!("loaded.redirects")
      end
      true
    end

    # AD-03: the RESIDUAL bucket only. Multi-valued keys cannot satisfy the
    # (post_id, key) unique index, so they land in the jsonb column as arrays — the
    # unique index is what surfaces the distinction, exactly as AD-05 intends.
    def load_post_attributes(post, meta, legacy_id)
      residual = {}
      meta.each do |key, values|
        next if PROMOTED_POST_META.include?(key)

        decoded = values.map { |v| decode(v, source: "postmeta[#{key}]", legacy_id: legacy_id) }
        if decoded.length == 1
          Publishing::Attribute.create!(post: post, key: key, value: decoded.first.to_json)
          @report.count!("loaded.post_attributes")
        else
          residual[key] = decoded
          @report.count!("loaded.residual_attributes")
        end
      end
      # MERGE, don't replace: the row already parks `ping_status` there (see load_posts).
      post.update_column(:residual_attributes, post.residual_attributes.merge(residual)) if residual.any?
    end

    # AD-02: post_type='revision' becomes an audit record, not content.
    def load_revisions(rows, all_meta)
      _ = all_meta
      rows.select { |r| r["post_type"] == "revision" }.each do |r|
        post_id = @map[:posts][r["post_parent"].to_i]
        next unless post_id

        Publishing::Revision.create!(
          post_id: post_id, author_id: @map[:users][r["post_author"].to_i],
          title: T.text(r["post_title"]), content: T.text(r["post_content"]),
          excerpt: T.text(r["post_excerpt"]),
          autosave: r["post_name"].to_s.include?("autosave"),
          created_at: T.zero_date_to_null(r["post_date_gmt"]) || Time.current
        )
        @report.count!("loaded.revisions")
      end
    end

    # AD-02: post_type='attachment' -> assets, joining the four _wp_attachment* keys.
    def load_assets
      @legacy_rows.select { |r| r["post_type"] == "attachment" }.each do |r|
        legacy_id = r["ID"].to_i
        m = @posts_meta[legacy_id]
        metadata = decode(m["_wp_attachment_metadata"]&.first, source: "postmeta[_wp_attachment_metadata]",
                                                               legacy_id: legacy_id) || {}
        metadata = {} unless metadata.is_a?(Hash)

        asset = Library::Asset.new(
          uploader_id: @map[:users][r["post_author"].to_i],
          attached_to_id: @map[:posts][r["post_parent"].to_i],
          title: T.text(r["post_title"]),
          slug: T.slug_or_null(r["post_name"]) || "attachment-#{legacy_id}",
          alt_text: T.text(m["_wp_attachment_image_alt"]&.first),
          caption: T.text(r["post_excerpt"]),
          mime_type: r["post_mime_type"].presence || "application/octet-stream",
          byte_size: metadata["filesize"].to_i,
          width: metadata["width"], height: metadata["height"],
          # ⚠️ `sizes` is KEPT. AD-03 promotes the per-size dimensions to `asset_variants`
          # rows, but that table (target_data_model.md:361) has no filename column, and
          # `wp_calculate_image_srcset()` builds every candidate URL from
          # `_wp_attachment_metadata['sizes'][<name>]['file']`. Dropping it made the whole
          # srcset guess WordPress's canonical `<base>-<w>x<h>.<ext>`, which is wrong for
          # any size whose file was not named that way — this corpus's are `med-…` /
          # `large-…`, and that difference appears on 10 of the 18 golden screens.
          metadata: metadata
        )
        unless asset.save
          @report.dead_letter!(source: "posts(attachment)", legacy_id: legacy_id,
                               reason: asset.errors.full_messages.join("; "))
          next
        end
        @map[:assets][legacy_id] = asset.id
        @report.count!("loaded.assets")

        (metadata["sizes"] || {}).each do |size_name, dims|
          next unless dims.is_a?(Hash)

          Library::Variant.create!(asset: asset, size_name: size_name.to_s,
                                   width: dims["width"].to_i, height: dims["height"].to_i,
                                   mime_type: dims["mime-type"].presence || asset.mime_type)
          @report.count!("loaded.asset_variants")
        end
      end
    end

    # "posts.featured_asset_id is a DEFERRED FK added after assets exist, so featured
    #  images are set in a second pass." AD-03: postmeta '_thumbnail_id'.
    def attach_featured_assets
      @posts_meta.each do |legacy_post_id, m|
        thumb = m["_thumbnail_id"]&.first
        next if thumb.blank?

        post_id = @map[:posts][legacy_post_id]
        asset_id = @map[:assets][thumb.to_i]
        next unless post_id && asset_id

        Publishing::Post.where(id: post_id).update_all(featured_asset_id: asset_id)
        @report.count!("loaded.featured_assets")
      end
    end

    # term_relationships.object_id -> the polymorphic classifiable_*.
    def load_term_assignments
      Legacy.rows("SELECT * FROM #{Legacy.table("term_relationships")}").each do |r|
        ttid = r["term_taxonomy_id"].to_i
        term_id = @map[:terms][ttid]
        object_legacy = r["object_id"].to_i

        if term_id.nil?
          # nav_menu relationships point at menus, which AD-02 moved out of terms.
          @report.count!("skipped.term_relationships.nav_menu") if @map[:menus][ttid]
          next
        end

        if (pid = @map[:posts][object_legacy])
          type, id = "Publishing::Post", pid
        elsif (aid = @map[:assets][object_legacy])
          type, id = "Library::Asset", aid
        else
          @report.count!("skipped.term_relationships.unmapped_object")
          next
        end

        Classification::Assignment.create!(term_id: term_id, classifiable_type: type,
                                           classifiable_id: id, position: r["term_order"].to_i)
        @report.count!("loaded.term_assignments")
      end
    end

    # T-05.
    def load_comments
      rows = Legacy.rows("SELECT * FROM #{Legacy.table("comments")} ORDER BY comment_parent, comment_ID")
      pending = rows.dup
      2.times { pending = pending.reject { |r| insert_comment(r) } }
      pending.each { |r| insert_comment(r, force_root: true) }
    end

    def insert_comment(r, force_root: false)
      legacy_id = r["comment_ID"].to_i
      parent_legacy = r["comment_parent"].to_i
      parent_id = parent_legacy.zero? ? nil : @map[:comments][parent_legacy]
      return false if parent_legacy.positive? && parent_id.nil? && !force_root

      post_id = @map[:posts][r["comment_post_ID"].to_i]
      if post_id.nil?
        @report.count!("skipped.comments.unmapped_post")
        return true
      end

      begin
        status = T.comment_status(r["comment_approved"])
        submitted = T.zero_date_to_null(r["comment_date_gmt"])
      rescue ArgumentError => e
        @report.dead_letter!(source: "comments", legacy_id: legacy_id, reason: e.message,
                             payload: r["comment_approved"])
        return true
      end

      comment = Discussion::Comment.new(
        post_id: post_id, parent_id: parent_id,
        user_id: @map[:users][r["user_id"].to_i],
        author_name: T.text(r["comment_author"]), author_email: r["comment_author_email"].presence,
        author_url: r["comment_author_url"].presence, author_ip: r["comment_author_IP"].presence,
        user_agent: r["comment_agent"].presence, content: T.text(r["comment_content"]),
        status: status, kind: r["comment_type"].presence || "comment",
        submitted_at: submitted || Time.current
      )
      # The corpus is threaded deeper than the configured limit in places; the stored
      # thread is the fact, and re-validating it against a *setting* would reject data
      # the oracle holds. The depth rule governs new submissions, not the load.
      comment.define_singleton_method(:thread_depth_within_limit) { nil }

      if comment.save
        @map[:comments][legacy_id] = comment.id
        @report.count!("loaded.comments")
      else
        @report.dead_letter!(source: "comments", legacy_id: legacy_id,
                             reason: comment.errors.full_messages.join("; "))
      end
      true
    end


    # T-04: the nine _menu_item_* keys -> columns. 🔑 target_domain_model.md calls this
    # "the clearest single win in the model".
    def load_menus
      items = @legacy_rows.select { |r| r["post_type"] == "nav_menu_item" }
      # Which menu each item belongs to comes from term_relationships against nav_menu.
      membership = {}
      Legacy.rows("SELECT * FROM #{Legacy.table("term_relationships")}").each do |r|
        menu_id = @map[:menus][r["term_taxonomy_id"].to_i]
        membership[r["object_id"].to_i] = menu_id if menu_id
      end

      pending = items.dup
      2.times { pending = pending.reject { |r| insert_menu_item(r, membership) } }
      pending.each { |r| insert_menu_item(r, membership, force_root: true) }
    end

    def insert_menu_item(r, membership, force_root: false)
      legacy_id = r["ID"].to_i
      m = @posts_meta[legacy_id]

      # "Rows carrying _menu_item_orphaned are DROPPED, and the count is reported.
      #  These are tombstones (BR-MENU-05) that exist only because the legacy has no
      #  foreign keys (F-DD-01); the FK on menu_items.menu_id makes the condition they
      #  mark unrepresentable."
      if m.key?("_menu_item_orphaned")
        @report.count!("dropped.menu_items.orphaned_tombstone")
        return true
      end

      menu_id = membership[legacy_id]
      if menu_id.nil?
        @report.count!("skipped.menu_items.no_menu")
        return true
      end

      parent_legacy = m["_menu_item_menu_item_parent"]&.first.to_i
      parent_id = parent_legacy.zero? ? nil : @map[:menu_items][parent_legacy]
      return false if parent_legacy.positive? && parent_id.nil? && !force_root

      kind = m["_menu_item_type"]&.first.to_s
      object = m["_menu_item_object"]&.first.to_s
      object_id = m["_menu_item_object_id"]&.first.to_i

      # "_menu_item_type decides which arm of the menu_items_one_target CHECK applies:
      #  post_type/taxonomy -> internal target; custom -> url."
      target_type = target_id = url = nil
      case kind
      when "post_type"
        target_type = "Publishing::Post"
        target_id = @map[:posts][object_id]
      when "taxonomy"
        target_type = "Classification::Term"
        target_id = @map[:terms].values_at(*@map[:terms].keys).compact.first if false
        target_id = resolve_term_by_legacy_term_id(object_id)
      when "custom"
        url = m["_menu_item_url"]&.first.presence
      end
      if target_type && target_id.nil?
        # The target was not migrated (e.g. it pointed at a machinery post type).
        # Degrading to a custom URL would fabricate data; drop and report instead.
        @report.dead_letter!(source: "posts(nav_menu_item)", legacy_id: legacy_id,
                             reason: "menu item targets #{object}##{object_id}, which is not in the target",
                             payload: kind)
        return true
      end
      url ||= nil
      if target_type.nil? && url.nil?
        @report.dead_letter!(source: "posts(nav_menu_item)", legacy_id: legacy_id,
                             reason: "menu item has neither an internal target nor a URL " \
                                     "(menu_items_one_target CHECK)", payload: kind)
        return true
      end

      item = Presentation::MenuItem.new(
        menu_id: menu_id, parent_id: parent_id, position: r["menu_order"].to_i,
        target_type: target_type, target_id: target_id, url: url,
        label: T.text(r["post_title"]), title: T.text(r["post_excerpt"]),
        css_classes: Array(decode(m["_menu_item_classes"]&.first, source: "postmeta[_menu_item_classes]",
                                  legacy_id: legacy_id)).reject(&:blank?),
        xfn: T.text(m["_menu_item_xfn"]&.first)
      )
      if item.save
        @map[:menu_items][legacy_id] = item.id
        @report.count!("loaded.menu_items")
      else
        @report.dead_letter!(source: "posts(nav_menu_item)", legacy_id: legacy_id,
                             reason: item.errors.full_messages.join("; "))
      end
      true
    end

    # A menu item stores the legacy *term_id*, while T-06 keys the target on
    # term_taxonomy_id. Resolve through the source table rather than guessing.
    def resolve_term_by_legacy_term_id(term_id)
      return nil if term_id.zero?

      @term_id_index ||= Legacy.rows(
        "SELECT term_taxonomy_id, term_id FROM #{Legacy.table("term_taxonomy")}"
      ).group_by { |r| r["term_id"].to_i }
      candidates = @term_id_index[term_id] || []
      candidates.filter_map { |r| @map[:terms][r["term_taxonomy_id"].to_i] }.first
    end

    # AD-02: wp_template / wp_template_part -> templates; wp_block -> patterns.
    def load_composition
      @legacy_rows.each do |r|
        case r["post_type"]
        when "wp_template", "wp_template_part"
          Composition::Template.create!(
            theme_slug: theme_slug_for(r), slug: r["post_name"].presence || "template-#{r["ID"]}",
            kind: r["post_type"] == "wp_template" ? "template" : "part",
            area: nil, content: T.text(r["post_content"]),
            updated_at: T.zero_date_to_null(r["post_modified_gmt"]) || Time.current
          )
          @report.count!("loaded.templates")
        when "wp_block"
          Composition::Pattern.create!(
            slug: r["post_name"].presence || "pattern-#{r["ID"]}",
            title: T.text(r["post_title"]), content: T.text(r["post_content"]),
            updated_at: T.zero_date_to_null(r["post_modified_gmt"]) || Time.current
          )
          @report.count!("loaded.patterns")
        when "wp_navigation"
          # AD-02, same split as wp_template_part: a `wp_navigation` post is a document
          # of block markup, and `core/navigation` renders the most recently published
          # one as its fallback (class-wp-navigation-fallback.php:70). Only published
          # rows are candidates there (post_status => 'publish', :119), so only those are
          # content; anything else is reported and dropped.
          if r["post_status"] == "publish"
            Composition::Template.create!(
              theme_slug: theme_slug_for(r), slug: r["post_name"].presence || "navigation-#{r["ID"]}",
              kind: "navigation", area: nil,
              title: T.text(r["post_title"]), content: T.text(r["post_content"]),
              updated_at: T.zero_date_to_null(r["post_modified_gmt"]) || Time.current
            )
            @report.count!("loaded.navigations")
          else
            @report.count!("skipped.wp_navigation.unpublished")
          end
        when "wp_global_styles", "wp_font_family", "wp_font_face"
          # T-09: these belong to the `styling` pack's own store, which is a leaf with
          # zero dependencies and therefore no ActiveRecord. Reported, not loaded here.
          @report.count!("deferred.styling.#{r["post_type"]}")
        when "customize_changeset"
          @report.count!("deferred.console.customize_changeset")
        when "custom_css"
          # wp_get_custom_css_post() (wp-includes/theme.php:1982) finds this post BY
          # NAME — the post_name IS the stylesheet it styles — and
          # wp_enqueue_global_styles() (script-loader.php:2626) appends its content to
          # the global stylesheet on a block theme. The pivot keys the content the same
          # way: one setting per stylesheet, read by Presentation::GlobalStylesheet.
          # Stored VERBATIM (RISK-008: no slash/unslash pass).
          Configuration::Setting.set("custom_css_#{r["post_name"]}", r["post_content"].to_s,
                                     autoload: false)
          @report.count!("loaded.custom_css")
        end
      end
      if @report.counts.keys.any? { |k| k.start_with?("deferred.styling") }
        @report.note!("T-09: global styles / font faces are deferred to the " \
                      "styling pack's own store (Wave 2); counted, not loaded.")
      end
    end

    def theme_slug_for(row)
      ttids = Legacy.rows(
        "SELECT tt.term_taxonomy_id, t.slug FROM #{Legacy.table("term_relationships")} tr " \
        "JOIN #{Legacy.table("term_taxonomy")} tt ON tt.term_taxonomy_id = tr.term_taxonomy_id " \
        "JOIN #{Legacy.table("terms")} t ON t.term_id = tt.term_id " \
        "WHERE tr.object_id = #{row["ID"].to_i} AND tt.taxonomy = 'wp_theme'"
      )
      ttids.first&.fetch("slug", nil) || "default"
    end

    def load_syndication_and_routing
      @legacy_rows.select { |r| r["post_type"] == "oembed_cache" }.each do |r|
        payload = begin
          JSON.parse(r["post_content"].to_s)
        rescue JSON::ParserError
          { "raw" => T.text(r["post_content"]) }
        end
        Syndication::EmbedCache.create!(
          url_digest: r["post_name"].to_s.presence || Digest::SHA256.hexdigest(r["ID"].to_s),
          payload: payload,
          # ⚠️ "a cache stops being content; TTL is RE-DERIVED, not migrated."
          fetched_at: Time.current, expires_at: 1.day.from_now
        )
        @report.count!("loaded.embed_caches")
      end
    end

    def load_data_requests
      @legacy_rows.select { |r| r["post_type"] == "user_request" }.each do |r|
        m = @posts_meta[r["ID"].to_i]
        email = m["_user_email"]&.first.presence || r["post_title"].to_s
        kind = r["post_title"].to_s.include?("erasure") ? "erasure" : "export"
        Identity::DataRequest.create!(
          user_id: Identity::User.find_by(email: email)&.id, email: email, kind: kind,
          status: r["post_status"].to_s.delete_prefix("request-")
        )
        @report.count!("loaded.data_requests")
      end
    end

    # Implication 4: derived state moves into the model. Term counts and comment counts
    # are counter caches here, not read-time joins.
    def recompute_counter_caches
      Classification::Term.find_each { |t| t.recompute_count! }
      Publishing::Post.find_each do |p|
        Publishing::Post.where(id: p.id).update_all(
          comment_count: Discussion::Comment.where(post_id: p.id).count
        )
      end
      @report.count!("recomputed.counter_caches", Classification::Term.count + Publishing::Post.count)
    end


    # ── 4b. T-12 (not in the plan): settings whose VALUES are record ids ─────────────
    #
    # data_migration_plan.md's T-01…T-11 transform shapes and encodings, but nothing in
    # the plan remaps OPTION VALUES that carry record ids — and several do:
    # `sticky_posts` is an array of post ids, `page_on_front` / `page_for_posts` /
    # `wp_page_for_privacy_policy` are post ids, `site_logo` / `site_icon` are attachment
    # ids, `default_category` is a term id.
    #
    # ⚠️ Found the dangerous way. The pipeline copied `sticky_posts: [15]` verbatim; the
    # sticky article's NEW id is 14, and new id 15 belongs to a different post — so the
    # front page floated the WRONG post to the top. The mechanism worked, the data lied,
    # and nothing failed. An id that cannot be remapped goes to the DEAD-LETTER QUEUE,
    # never silently dropped: an option pointing at a record that did not migrate is
    # evidence, not noise.
    POST_ID_SETTINGS = %w[page_on_front page_for_posts wp_page_for_privacy_policy].freeze
    ASSET_ID_SETTINGS = %w[site_logo site_icon].freeze

    def remap_identifier_settings
      remap_setting("sticky_posts") do |value|
        Array(value).map { |legacy_id| remap_id!(:posts, legacy_id, "sticky_posts") }
      end
      POST_ID_SETTINGS.each do |name|
        remap_setting(name) { |value| remap_id!(:posts, value, name) }
      end
      ASSET_ID_SETTINGS.each do |name|
        remap_setting(name) { |value| remap_id!(:assets, value, name) }
      end
      # T-06 keys the target's terms by term_taxonomy_id while options store term_id, so
      # the remap goes through the same source-table resolution menu items use.
      remap_setting("default_category") do |value|
        resolve_term_by_legacy_term_id(value.to_i) or
          raise UnmappableId, "default_category: legacy term #{value} has no target row"
      end
    end

    class UnmappableId < StandardError; end

    def remap_setting(name)
      row = Configuration::Setting.find_by(name: name)
      return if row.nil? || row.value.nil?

      row.update!(value: yield(row.value))
      @report.count!("remapped.settings")
    rescue UnmappableId => e
      @report.dead_letter!(source: "options", legacy_id: name, reason: e.message)
    end

    def remap_id!(map_name, legacy_id, setting_name)
      id = legacy_id.to_i
      return 0 if id.zero? # 0 is the legacy's "unset", not a reference

      @map[map_name][id] or
        raise UnmappableId, "#{setting_name}: legacy #{map_name} id #{id} has no target row"
    end

    # ── 5. Verify — data_migration_plan.md § Quality validation ──────────────────
    def verify
      say "── quality validation ────────────────────────────────────────────"
      checks = []

      legacy_by_type = Legacy.rows(
        "SELECT post_type, COUNT(*) c FROM #{Legacy.table("posts")} GROUP BY post_type"
      ).to_h { |r| [r["post_type"], r["c"].to_i] }

      checks << check("posts (post+page) equal ±0",
                      legacy_by_type.values_at("post", "page").compact.sum,
                      Publishing::Post.count)
      checks << check("revisions equal ±0", legacy_by_type["revision"].to_i,
                      Publishing::Revision.count)
      checks << check("assets equal ±0", legacy_by_type["attachment"].to_i,
                      Library::Asset.count)
      checks << check("comments equal ±0", Legacy.count_of("comments"), Discussion::Comment.count)
      checks << check("users equal ±0", Legacy.count_of("users"), Identity::User.count)

      # ⚠️ "target = count of wp_term_taxonomy rows, NOT wp_terms rows (T-06) — the
      #     difference is the expected behavioural change, and getting this backwards is
      #     how the split gets missed." nav_menu rows became menus, so they are excluded.
      tt_non_menu = Legacy.connection.select_value(
        "SELECT COUNT(*) FROM #{Legacy.table("term_taxonomy")} WHERE taxonomy <> 'nav_menu'"
      ).to_i
      checks << check("terms = wp_term_taxonomy rows (T-06, not wp_terms)",
                      tt_non_menu, Classification::Term.count)

      menu_items_expected = legacy_by_type["nav_menu_item"].to_i -
                            @report.counts["dropped.menu_items.orphaned_tombstone"]
      checks << check("menu items equal ±0 (less orphan tombstones)",
                      menu_items_expected, Presentation::MenuItem.count)

      # Zero dates reaching PostgreSQL: structurally impossible, asserted anyway.
      checks << check("zero dates reaching PostgreSQL", 0,
                      Publishing::Post.where("published_at = '0001-01-01'").count)

      # Referential integrity: FKs make most of this structural. term_assignments is the
      # ONE polymorphic relationship that cannot carry an FK, so it gets an audit query.
      orphans = ActiveRecord::Base.connection.select_value(<<~SQL).to_i
        SELECT COUNT(*) FROM term_assignments ta
        WHERE (ta.classifiable_type = 'Publishing::Post'
                 AND NOT EXISTS (SELECT 1 FROM posts p WHERE p.id = ta.classifiable_id))
           OR (ta.classifiable_type = 'Library::Asset'
                 AND NOT EXISTS (SELECT 1 FROM assets a WHERE a.id = ta.classifiable_id))
      SQL
      checks << check("polymorphic term_assignments orphans", 0, orphans)

      # Counter caches: recompute and compare. ⚠️ PUBLISHED ONLY (BR-TAX-11).
      drift = Classification::Term.all.count do |t|
        stored = t.count
        t.recompute_count! != stored
      end
      checks << check("term counter-cache drift (published only)", 0, drift)

      comment_drift = Publishing::Post.all.count do |p|
        p.comment_count != Discussion::Comment.where(post_id: p.id).count
      end
      checks << check("comment counter-cache drift", 0, comment_drift)

      # Round-trip fidelity of text — "this is what catches an accidental slashing pass"
      # (T-08). Compared by checksum against the source, per post.
      checks << check("text round-trip mismatches (T-08 slashing)", 0, text_roundtrip_mismatches)
      checks << check("4-byte UTF-8 survival mismatches (RISK-014)", 0, astral_mismatches)

      say
      checks.each { |c| say(format("  %-52s %s", c[:label], c[:ok] ? "OK   (#{c[:actual]})" : "FAIL expected #{c[:expected]}, got #{c[:actual]}")) }
      @verification_failures = checks.reject { |c| c[:ok] }
      say
    end

    def check(label, expected, actual)
      { label: label, expected: expected, actual: actual, ok: expected.to_i == actual.to_i }
    end

    def verification_failures = @verification_failures || []

    # Byte-for-byte comparison of the text columns against the oracle.
    def text_roundtrip_mismatches
      mismatches = 0
      Legacy.rows(<<~SQL).each do |r|
        SELECT ID, post_title, post_content, post_excerpt FROM #{Legacy.table("posts")}
        WHERE post_type IN ('post','page')
      SQL
        new_id = @map[:posts][r["ID"].to_i]
        next unless new_id

        post = Publishing::Post.find(new_id)
        %w[title content excerpt].each_with_index do |field, i|
          legacy_value = r[%w[post_title post_content post_excerpt][i]].to_s
          next if Digest::SHA256.hexdigest(legacy_value) == Digest::SHA256.hexdigest(post.public_send(field).to_s)

          mismatches += 1
          @report.dead_letter!(
            source: "roundtrip", legacy_id: r["ID"].to_i,
            reason: "#{field} is not byte-identical to the oracle (T-08 / RISK-008)",
            payload: "legacy=#{legacy_value.byteslice(0, 120).inspect} target=#{post.public_send(field).to_s.byteslice(0, 120).inspect}"
          )
        end
      end
      mismatches
    end

    # RISK-014: a divergence in the permissive direction that diffing tends to miss.
    def astral_mismatches
      astral = /[\u{10000}-\u{10FFFF}]/
      legacy_rows = Legacy.rows(
        "SELECT ID, post_title FROM #{Legacy.table("posts")} WHERE post_type IN ('post','page')"
      ).select { |r| r["post_title"].to_s.match?(astral) }
      legacy_rows.count do |r|
        new_id = @map[:posts][r["ID"].to_i]
        new_id.nil? || Publishing::Post.find(new_id).title != r["post_title"].to_s
      end
    end

    private

    def say(msg = "") = @io.puts(msg)

    def meta_for(table, id_column, ids, key_column: "meta_key", value_column: "meta_value")
      return {} if ids.empty?

      grouped = Hash.new { |h, k| h[k] = Hash.new { |g, j| g[j] = [] } }
      Legacy.rows(<<~SQL).each do |r|
        SELECT #{id_column} AS oid, #{key_column} AS k, #{value_column} AS v
        FROM #{Legacy.table(table)} WHERE #{id_column} IN (#{ids.join(",")})
      SQL
        grouped[r["oid"].to_i][r["k"]] << r["v"]
      end
      grouped
    end

    # T-02 with the quarantine wired in.
    def decode(raw, source:, legacy_id:)
      kind, value = PhpSerialization.parse(raw)
      _ = kind
      value
    rescue PhpSerialization::UnmappableObject => e
      @report.quarantine!(source: source, legacy_id: legacy_id,
                          reason: "O: payload, class #{e.class_name}", payload: raw)
      nil
    rescue PhpSerialization::ParseError => e
      @report.quarantine!(source: source, legacy_id: legacy_id,
                          reason: "unparseable serialized payload: #{e.message}", payload: raw)
      nil
    end
  end
end
