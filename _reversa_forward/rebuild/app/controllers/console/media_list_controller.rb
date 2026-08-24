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

      relation = ordered(Library::Asset.all)
      page = list_page(relation, strategy: :estimated)
      @parents_for = parents_for(page.records)
      @list = build_list(page)
      render "console/media_list/index"
    end

    # POST /console/media/bulk
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      assets = Library::Asset.where(id: bulk_ids).to_a

      if action == "delete" && !bulk_confirmed?
        return confirm_bulk(assets)
      end

      count = run_bulk(action, assets)
      redirect_to list_path, notice: "#{count} media item(s) permanently deleted.", status: :see_other
    end

    private

    SORTABLE = %w[title date].freeze

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
        tabs: [],
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
          "author" => ERB::Util.html_escape(asset.uploader&.display_name.presence || asset.uploader&.login.to_s),
          "parent" => parent_cell(asset),
          "date" => asset.created_at&.strftime("%Y/%m/%d").to_s
        },
        actions: row_actions(asset)
      )
    end

    def title_cell(asset)
      name = asset.title.presence || asset.file.presence || "(unnamed)"
      %(<strong><a href="/console/media/#{asset.id}/edit">#{ERB::Util.html_escape(name)}</a></strong>).html_safe
    end

    def parent_cell(asset)
      title = @parents_for[asset.attached_to_id]
      return "(Unattached)".html_safe if title.nil?

      %(<a href="/console/posts/#{asset.attached_to_id}/edit">#{ERB::Util.html_escape(title)}</a>).html_safe
    end

    def row_actions(asset)
      actions = []
      actions << ListModel::RowAction.new(label: "Edit", path: "/console/media/#{asset.id}/edit", method: :get, key: "edit") if can?(Access::AssetPolicy, asset, :edit)
      if can?(Access::AssetPolicy, asset, :delete)
        actions << ListModel::RowAction.new(label: "Delete Permanently", path: bulk_path, method: :post,
                                            params: { bulk_action: "delete", confirmed: "0", "ids[]" => asset.id },
                                            destructive: true, key: "delete")
      end
      actions
    end

    def run_bulk(action, assets)
      return 0 unless action == "delete"

      count = 0
      assets.each do |asset|
        next unless can?(Access::AssetPolicy, asset, :delete)

        asset.destroy!
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
