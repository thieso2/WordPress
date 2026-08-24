# frozen_string_literal: true

module Console
  # console.upload — the Media Library list (wp-admin/upload.php, WP_Media_List_Table).
  # P-LIST over Library::Asset with ESTIMATED pagination (target_screens.md § Part 5,
  # DEV-003: the total row count is out of parity scope here; the page contents are exact).
  #
  # LITERAL strings verbatim from WP_Media_List_Table: columns "File / Author / Uploaded to
  # / Date", bulk "Delete permanently" (MEDIA_TRASH is off by default, so there is no Trash
  # step), "No media files found." A distinct controller from the P-EDIT track's
  # Console::MediaController (the single-asset editor at /console/media/:id/edit).
  class MediaListController < BaseController
    include Console::ListActions

    # GET /console/media
    def index
      @page_title = "Media Library"
      @screen = "console.upload"

      relation = ordered(scoped(Library::Asset.all))
      page = list_page(relation, strategy: :estimated)
      @parents_for = parents_for(page.records)
      @list = build_list(page)
      render "console/media_list/index"
    end

    # POST /console/media/bulk. Beyond the checkbox-column bulk "Delete permanently", this
    # is also the target of the "Uploaded to" column's Detach/Attach controls — upload.php's
    # 'detach'/'attach' doactions (upload.php:283-288, wp_media_attach_action()), AGG-Asset's
    # accepted `attach`/`detach` commands (target_domain_model.md:97).
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      assets = Library::Asset.where(id: bulk_ids).to_a

      case action
      when "delete"
        return confirm_bulk(assets) unless bulk_confirmed?

        count = run_delete(assets)
        redirect_to list_path, notice: "#{count} media item(s) permanently deleted.", status: :see_other
      when "detach"
        count = run_detach(assets)
        # upload.php:44-51 — "Media file detached." / "%s media files detached."
        flash[:success] = count == 1 ? "Media file detached." : "#{count} media files detached."
        redirect_to list_path, status: :see_other
      when "attach"
        count = run_attach(assets)
        # upload.php:27-34 — "Media file attached." / "%s media files attached."
        flash[:success] = count == 1 ? "Media file attached." : "#{count} media files attached."
        redirect_to list_path, status: :see_other
      else
        redirect_to list_path, status: :see_other
      end
    end

    private

    SORTABLE = %w[title date].freeze

    # The narrowing the media list offers (upload.php Overview: "You can narrow the list by
    # file type/status or by date"). WP_Media_List_Table::get_views (:148) is the
    # attachment-filter set — All / mime types / Unattached / Mine — carried in the
    # `attachment-filter` request var; column_author's link and months_dropdown add
    # `author` and `m`. This is the controller support that scoping requires; the
    # attachment-filter values are the oracle's own (`post_mime_type:<group>`, `detached`,
    # `mine`).
    def scoped(scope)
      filter = params["attachment-filter"].to_s

      scope = scope.where(uploader_id: current_actor&.id) if filter == "mine"
      scope = scope.where(attached_to_id: nil) if filter == "detached"
      if filter.start_with?("post_mime_type:")
        group = filter.delete_prefix("post_mime_type:")
        scope = scope.where("assets.mime_type LIKE ?", "#{group}/%") if group.present?
      end

      scope = scope.where(uploader_id: params[:author].to_i) if params[:author].present?

      if (m = params[:m].to_s) =~ /\A(\d{4})(\d{2})\z/
        start = Time.zone.local(Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, 1)
        scope = scope.where(created_at: start...start.next_month)
      end

      scope
    end

    # get_views(), class-wp-media-list-table.php:148 — the attachment-filter options,
    # rendered here as the P-LIST status-tab family (DEV-002: hook-registered UI becomes
    # DECLARED UI). LITERAL labels verbatim: "All media items", the available mime groups
    # ("Images"/"Audio"/"Video", get_post_mime_types()[$g][0]), "Unattached", "Mine". Only
    # mime groups actually present in the library appear (wp_match_mime_types against the
    # available types).
    MIME_GROUPS = { "image" => "Images", "audio" => "Audio", "video" => "Video" }.freeze

    def view_tabs
      filter = params["attachment-filter"].to_s
      tabs = [ListModel::Tab.new(key: "all", label: "All media items", count: nil,
                                 query: { "attachment-filter" => nil },
                                 current: filter.empty? || filter == "all")]

      available_mime_groups.each do |group|
        value = "post_mime_type:#{group}"
        tabs << ListModel::Tab.new(key: group, label: MIME_GROUPS[group], count: nil,
                                   query: { "attachment-filter" => value }, current: filter == value)
      end

      tabs << ListModel::Tab.new(key: "detached", label: "Unattached", count: nil,
                                 query: { "attachment-filter" => "detached" }, current: filter == "detached")
      tabs << ListModel::Tab.new(key: "mine", label: "Mine", count: nil,
                                 query: { "attachment-filter" => "mine" }, current: filter == "mine")
      tabs
    end

    # get_available_post_mime_types( 'attachment' ) reduced to the three always-defined
    # groups: a group appears only when a stored asset's mime type matches its wildcard.
    def available_mime_groups
      MIME_GROUPS.keys.select do |group|
        Library::Asset.where("assets.mime_type LIKE ?", "#{group}/%").exists?
      end
    end

    def ordered(scope)
      orderby = list_orderby(SORTABLE, default: "date")
      dir = list_order.upcase
      column = orderby == "title" ? "assets.title" : "assets.created_at"
      scope.order(Arel.sql("#{column} #{dir}, assets.id #{dir}"))
    end

    def build_list(page)
      ListModel.new(
        screen: "console.upload",
        title: "Media Library",
        primary_action: (site_can?("upload_files") ? { label: "Add Media File", path: "/console/media/new" } : nil),
        tabs: view_tabs,
        filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search", value: params[:s].to_s)],
        bulk_actions: bulk_actions,
        columns: columns,
        rows: page.records.map { |asset| row_for(asset) },
        page: page,
        strategy: :estimated,
        base_path: list_path,
        bulk_path: bulk_path,
        empty_message: "No media files found.",
        query: list_query,
        order: list_order,
        orderby: list_orderby(SORTABLE, default: "date"),
        search_query: params[:s].presence
      )
    end

    # get_columns(), class-wp-media-list-table.php:365 — LITERAL. cb, title ("File"),
    # author, parent ("Uploaded to"), comments and date; comments column omitted here.
    def columns
      [
        ListModel::Column.new(key: "title", label: "File", sortable: true, sort_key: "title"),
        ListModel::Column.new(key: "author", label: "Author", sortable: false),
        ListModel::Column.new(key: "parent", label: "Uploaded to", sortable: false),
        ListModel::Column.new(key: "date", label: "Date", sortable: true, sort_key: "date")
      ]
    end

    # get_bulk_actions(), class-wp-media-list-table.php:203 with MEDIA_TRASH off: a single
    # "Delete permanently", DEV-004-confirmed.
    def bulk_actions
      return [] unless site_can?("upload_files")

      [ListModel::BulkAction.new(value: "delete", label: "Delete permanently", destructive: true)]
    end

    def row_for(asset)
      ListModel::Row.new(
        id: asset.id,
        cells: {
          "title" => title_cell(asset),
          "author" => author_cell(asset),
          "parent" => parent_cell(asset),
          "date" => asset.created_at&.strftime("%Y/%m/%d").to_s
        },
        actions: row_actions(asset)
      )
    end

    # column_author(), class-wp-media-list-table.php:539 — the uploader's display name as a
    # link to the author-filtered list (upload.php?author=ID); a missing author is the
    # em-dash + "(no author)" screen-reader text (:548).
    def author_cell(asset)
      name = asset.uploader&.display_name.presence || asset.uploader&.login.to_s
      if asset.uploader && name.present?
        %(<a href="/console/media?author=#{asset.uploader_id}">#{ERB::Util.html_escape(name)}</a>).html_safe
      else
        %(<span aria-hidden="true">&#8212;</span><span class="screen-reader-text">(no author)</span>).html_safe
      end
    end

    def title_cell(asset)
      name = asset.title.presence || asset.file.presence || "(unnamed)"
      %(<strong><a href="/console/media/#{asset.id}/edit">#{ERB::Util.html_escape(name)}</a></strong>).html_safe
    end

    # column_parent(), class-wp-media-list-table.php:608. Attached: the parent link plus a
    # "Detach" control (:637); unattached: "(Unattached)" plus an "Attach" link (:653). Both
    # gated on `current_user_can( 'edit_post', $attachment )` — AssetPolicy(:edit) here.
    def parent_cell(asset)
      can_edit = can?(Access::AssetPolicy, asset, :edit)

      if asset.attached_to_id.present?
        title = @parents_for[asset.attached_to_id]
        link = if title
                 %(<strong><a href="/console/posts/#{asset.attached_to_id}/edit">#{ERB::Util.html_escape(title)}</a></strong>)
               else
                 %(<strong>#{ERB::Util.html_escape("(Private post)")}</strong>)
               end
        link += detach_control(asset) if can_edit
        link.html_safe
      else
        cell = "(Unattached)"
        # upload.php:287 launches a find-posts popup (JS) to pick the target; the doaction
        # itself is handled by #bulk ("attach" + found_post_id). The href mirrors the
        # oracle's `#the-list` anchor.
        cell += %(<br /><a href="#the-list" class="hide-if-no-js aria-button-if-js">Attach</a>) if can_edit
        cell.html_safe
      end
    end

    # The single-item "Detach" control — a POST to #bulk naming this one id, exactly the
    # path the checkbox-column "Delete permanently" row action uses. wp_media_attach_action(
    # $parent, 'detach' ) sets post_parent to 0.
    def detach_control(asset)
      view_context.button_to("Detach", bulk_path, method: :post,
                             params: { "bulk_action" => "detach", "ids[]" => asset.id },
                             form: { class: "detach-from-parent", data: { turbo: false } },
                             class: "button-link", data: { turbo: false })
    end

    # _get_row_actions(), class-wp-media-list-table.php:802. Default install (MEDIA_TRASH
    # off, not trash): Edit, Delete Permanently, View (the public display page, :854),
    # Copy URL (:864) and Download file (:876). View is present whenever the attachment has
    # a permalink (always, here); Copy URL / Download need the attachment file URL.
    def row_actions(asset)
      actions = []
      actions << ListModel::RowAction.new(label: "Edit", path: "/console/media/#{asset.id}/edit", method: :get, key: "edit") if can?(Access::AssetPolicy, asset, :edit)
      if can?(Access::AssetPolicy, asset, :delete)
        actions << ListModel::RowAction.new(label: "Delete Permanently", path: bulk_path, method: :post,
                                            params: { bulk_action: "delete", confirmed: "0", "ids[]" => asset.id },
                                            destructive: true, key: "delete")
      end
      actions << ListModel::RowAction.new(label: "View", path: attachment_permalink(asset), method: :get, key: "view")
      if asset.url.present?
        actions << ListModel::RowAction.new(label: "Copy URL", path: asset.url, method: :get, key: "copy")
        actions << ListModel::RowAction.new(label: "Download file", path: asset.url, method: :get, key: "download")
      end
      actions
    end

    # get_permalink() for an attachment. On a default install (plain permalinks) this is
    # `?attachment_id=ID` (get_attachment_link, mirrored by PublicApi::MediaSerializer).
    def attachment_permalink(asset)
      home = Configuration::Setting["home"].to_s.chomp("/")
      "#{home}/?attachment_id=#{asset.id}"
    end

    def run_delete(assets)
      count = 0
      assets.each do |asset|
        next unless can?(Access::AssetPolicy, asset, :delete)

        asset.destroy!
        count += 1
      end
      count
    end

    # wp_media_attach_action( $parent_id, 'detach' ) — post_parent → 0, per attachment the
    # actor may edit.
    def run_detach(assets)
      count = 0
      assets.each do |asset|
        next unless can?(Access::AssetPolicy, asset, :edit)

        asset.detach!
        count += 1
      end
      count
    end

    # wp_media_attach_action( $found_post_id ) — post_parent → the chosen post, per
    # attachment the actor may edit, when the target post exists.
    def run_attach(assets)
      target = Publishing::Post.find_by(id: params[:found_post_id])
      return 0 unless target

      count = 0
      assets.each do |asset|
        next unless can?(Access::AssetPolicy, asset, :edit)

        asset.attach!(target)
        count += 1
      end
      count
    end

    def confirm_bulk(assets)
      assets = assets.select { |a| can?(Access::AssetPolicy, a, :delete) }
      render_bulk_confirmation(
        title: "Media Library",
        prompt: "You are about to permanently delete #{assets.length} media item(s). This cannot be undone.",
        button: "Delete permanently",
        action: "delete",
        ids: assets.map(&:id),
        items: assets.map { |a| a.title.presence || a.file },
        post_path: bulk_path,
        cancel_path: list_path
      )
    end

    # The "Uploaded to" post titles for the page's assets, one query. attached_to_id is
    # deliberately not an association (Library note), so read the posts directly.
    def parents_for(assets)
      ids = assets.filter_map(&:attached_to_id).uniq
      return {} if ids.empty?

      Publishing::Post.where(id: ids).pluck(:id, :title).to_h
    end

    def list_path = "/console/media"
    def bulk_path = "/console/media/bulk"
  end
end
