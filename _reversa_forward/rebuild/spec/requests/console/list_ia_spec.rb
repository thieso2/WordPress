# frozen_string_literal: true

require_relative "console_spec_helper"

# P-LIST information-architecture parity (owner ruling, 2026-08-24: match wp-admin's IA —
# what is on the screen, in what order, with what controls — while keeping the rebuild's
# own styling). The reference is WP_List_Table
# (wp-admin/includes/class-wp-list-table.php): display(), display_tablenav(),
# print_column_headers(), pagination(), views(), search_box(), row_actions().
#
# Every P-LIST screen renders through console/shared/_list, so the structure is asserted
# once here on the Posts list and spot-checked on a second screen (Users) to prove the
# per-screen strings — the search text, the screen-reader headings — really are per screen.
RSpec.describe "P-LIST information architecture (WP_List_Table)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  def publish!(title, author: actor("con_editor"))
    Publishing::Article.create!(author: author, title: title, status: :published, published_at: Time.current)
  end

  # Document order. Nokogiri's Node#<=> returns nil for nodes in different subtrees on
  # some libxml builds, so position is read off the document's own element sequence — and
  # off ONE parse, since `doc` re-parses the response on every call.
  def before_in_document?(first_selector, second_selector, document = doc)
    order = document.css("*").to_a
    first = first_selector.is_a?(String) ? document.at_css(first_selector) : first_selector
    second = second_selector.is_a?(String) ? document.at_css(second_selector) : second_selector
    expect(first).to be_present
    expect(second).to be_present
    order.index(first) < order.index(second)
  end

  describe "the Posts list" do
    before do
      publish!("Hello Jazz")
      login_as("con_editor")
      get "/console/posts"
    end

    # ── display_tablenav( 'top' ) and ( 'bottom' ) — :1130 ──────────────────────────
    it "renders the tablenav BOTH above and below the table" do
      expect(doc.css("div.tablenav.top").length).to eq(1)
      expect(doc.css("div.tablenav.bottom").length).to eq(1)
      expect(before_in_document?("div.tablenav.top", "table.wp-list-table")).to be(true)
      expect(before_in_document?("table.wp-list-table", "div.tablenav.bottom")).to be(true)
    end

    it "repeats the bulk actions and the pager in the bottom tablenav" do
      %w[top bottom].each do |which|
        nav = doc.at_css("div.tablenav.#{which}")
        expect(nav.at_css(".bulkactions select")).to be_present, "#{which} tablenav has no bulk select"
        expect(nav.at_css(".tablenav-pages")).to be_present, "#{which} tablenav has no pager"
      end
    end

    # ── bulk_actions( $which ) — :1035. Distinct ids at each end. ───────────────────
    it "pairs each bulk-action select with an Apply button under a unique id" do
      %w[top bottom].each do |which|
        select = doc.at_css("#bulk-action-selector-#{which}")
        expect(select).to be_present
        expect(select.at_css('option[value="-1"]').text).to eq("Bulk actions")
        label = doc.at_css("label[for='bulk-action-selector-#{which}']")
        expect(label.text).to eq("Select bulk action")
        expect(label["class"]).to include("screen-reader-text")
      end
      expect(doc.at_css("#doaction").text.strip).to eq("Apply")
      expect(doc.at_css("#doaction2").text.strip).to eq("Apply")
      ids = doc.css("[id]").map { |n| n["id"] }
      expect(ids).to eq(ids.uniq), "duplicate ids: #{ids.tally.select { |_, n| n > 1 }.keys.inspect}"
    end

    # ── print_column_headers' check column, once per thead and tfoot ($cb_counter) ──
    it "puts a labelled Select All checkbox in both the thead and the tfoot" do
      %w[cb-select-all-1 cb-select-all-2].each do |id|
        box = doc.at_css("##{id}")
        expect(box).to be_present
        expect(box["type"]).to eq("checkbox")
        expect(doc.at_css("label[for='#{id}'] .screen-reader-text").text).to eq("Select All")
      end
      expect(doc.at_css("thead #cb-select-all-1")).to be_present
      expect(doc.at_css("tfoot #cb-select-all-2")).to be_present
    end

    # ── display(): print_column_headers( false ) in the <tfoot> ─────────────────────
    it "repeats the column headers in the tfoot, without the thead's column ids" do
      expect(header_labels("tfoot")).to eq(header_labels("thead"))
      expect(doc.css("thead th[id]")).not_to be_empty
      expect(doc.css("tfoot th[id]")).to be_empty
      expect(doc.at_css("tfoot td.check-column")["id"]).to be_nil
    end

    # ── print_column_headers' sort state — :1240-1290 ───────────────────────────────
    it "marks the current sort column and gives every other sortable header an accessible name" do
      # The initial Posts view sorts by date descending (get_sortable_columns' initial order).
      date = doc.at_css("thead th.column-date")
      expect(date["class"].split).to include("sorted", "desc")
      expect(date["aria-sort"]).to eq("descending")
      expect(date.at_css(".sorting-indicators")).to be_present
      expect(date.at_css(".screen-reader-text")).to be_nil

      title = doc.at_css("thead th.column-title")
      expect(title["class"].split).to include("sortable")
      expect(title["aria-sort"]).to be_nil
      expect(title.at_css(".sorting-indicators")).to be_present
      expect(title.at_css(".screen-reader-text").text).to eq("Sort ascending.")
      expect(title.at_css("a")["href"]).to include("orderby=title").and include("order=asc")
    end

    it "flips the sorted column's own link and its aria-sort when the sort is reversed" do
      get "/console/posts?orderby=title&order=asc"
      title = doc.at_css("thead th.column-title")
      expect(title["class"].split).to include("sorted", "asc")
      expect(title["aria-sort"]).to eq("ascending")
      expect(title.at_css("a")["href"]).to include("order=desc")
    end

    # ── pagination( $which ) — :1004 ────────────────────────────────────────────────
    it "prints the item count and the disabled navspans when there is a single page" do
      pager = doc.at_css(".tablenav.top .tablenav-pages")
      expect(pager["class"].split).to include("one-page")
      expect(pager.at_css(".displaying-num").text.strip).to start_with("1 item")
    end

    it "renders '0 items' with no pager links on an empty screen" do
      get "/console/posts?status=draft"
      pager = doc.at_css(".tablenav.top .tablenav-pages")
      expect(pager["class"].split).to include("no-pages")
      expect(pager.text.strip).to eq("0 items")
      expect(doc.at_css(".tablenav.bottom")).to be_nil
    end

    it "omits the search box on an empty, unsearched list and keeps it on a searched one" do
      get "/console/posts?status=draft"
      expect(doc.at_css("p.search-box")).to be_nil
      get "/console/posts?status=draft&s=nothing"
      expect(doc.at_css("p.search-box")).to be_present
    end

    # ── views() ABOVE search_box() — edit.php:486-490 ───────────────────────────────
    it "puts the status tabs above the search box, with parenthesised counts" do
      tabs = doc.at_css("ul.subsubsub")
      expect(tabs).to be_present
      expect(doc.at_css("h2.screen-reader-text").text).to eq("Filter posts list")
      expect(tabs.at_css("li a .count").text).to match(/\(\d+\)/)
      expect(tabs.text).to include("|") if tabs.css("li").length > 1
      expect(before_in_document?("ul.subsubsub", "p.search-box")).to be(true)
    end

    # ── search_box( $text, $input_id ) — :1417 ──────────────────────────────────────
    it "labels the search input for screen readers and puts the screen's own text on the button" do
      box = doc.at_css("p.search-box")
      input = box.at_css("input[type=search]")
      expect(input["id"]).to eq("post-search-input")
      label = doc.at_css("label[for='post-search-input']")
      expect(label["class"]).to include("screen-reader-text")
      expect(label.text).to eq("Search Posts:")
      expect(box.at_css("#search-submit").text.strip).to eq("Search Posts")
    end

    # ── row_actions() — :582 ────────────────────────────────────────────────────────
    it "puts the row actions inside the primary column, separated by ' | '" do
      cell = doc.at_css("tbody tr td.column-primary")
      expect(cell["class"].split).to include("column-title", "has-row-actions")
      actions = cell.at_css(".row-actions")
      expect(actions).to be_present
      expect(actions.css("span").length).to be > 1
      expect(actions.text).to include(" | ")
      expect(actions.css("span").last.text).not_to include("|")
    end

    # ── edit.php:414-436 + display()'s heading_list ─────────────────────────────────
    it "renders the Add New button as a sibling of the h1 and a screen-reader h2 for the table" do
      h1 = doc.at_css("h1.wp-heading-inline")
      expect(h1.text).to eq("Posts")
      action = h1.next_element
      expect(action.name).to eq("a")
      expect(action["class"]).to include("page-title-action")
      expect(action.text).to eq("Add Post")
      expect(h1.parent).to eq(action.parent)
      expect(doc.at_css("hr.wp-header-end")).to be_present

      page = doc
      expect(page.css("h2.screen-reader-text").map(&:text)).to include("Posts list")
      heading = page.css("h2.screen-reader-text").find { |h| h.text == "Posts list" }
      expect(before_in_document?(heading, page.at_css("table.wp-list-table"), page)).to be(true)
    end

    it "gives the table body the id the legacy's display() gives it" do
      expect(doc.at_css("table.wp-list-table tbody")["id"]).to eq("the-list")
    end
  end

  describe "pagination across more than one page" do
    before do
      25.times { |i| publish!(format("Post %02d", i)) }
      login_as("con_editor")
      get "/console/posts"
    end

    it "renders first / previous / N of M / next / last, not just a next-prev pair" do
      pager = doc.at_css(".tablenav.top .pagination-links")
      expect(pager.css("span.tablenav-pages-navspan.disabled").length).to eq(2) # first + previous
      expect(pager.at_css("a.next-page .screen-reader-text").text).to eq("Next page")
      expect(pager.at_css("a.last-page .screen-reader-text").text).to eq("Last page")
      expect(doc.at_css(".tablenav.top .displaying-num").text.strip).to start_with("25 items")
      expect(pager.at_css("#current-page-selector")["value"]).to eq("1")
      expect(doc.at_css("label[for='current-page-selector']").text).to eq("Current Page")
      expect(pager.at_css(".total-pages").text).to eq("2")
      expect(pager.text).to include("of")
    end

    it "renders the bottom pager's current page as text under the #table-paging id" do
      bottom = doc.at_css(".tablenav.bottom .pagination-links")
      expect(bottom.at_css("#table-paging")).to be_present
      expect(bottom.at_css("#current-page-selector")).to be_nil
      expect(bottom.at_css(".paging-input").text).to include("1").and include("of")
    end

    it "enables first / previous and disables next / last on the last page" do
      get "/console/posts?paged=2"
      pager = doc.at_css(".tablenav.top .pagination-links")
      expect(pager.at_css("a.first-page .screen-reader-text").text).to eq("First page")
      expect(pager.at_css("a.prev-page .screen-reader-text").text).to eq("Previous page")
      expect(pager.at_css("a.next-page")).to be_nil
      expect(pager.css("span.tablenav-pages-navspan.disabled").length).to eq(2) # next + last
    end

    it "announces the pager to screen readers only at the top, only when it pages" do
      expect(doc.css("h2.screen-reader-text").map(&:text)).to include("Posts list navigation")
    end
  end

  describe "a second screen (Users)" do
    before do
      login_as("con_admin")
      get "/console/users"
    end

    it "carries its OWN search text, input id and screen-reader headings" do
      expect(doc.at_css("input[type=search]")["id"]).to eq("user-search-input")
      expect(doc.at_css("label[for='user-search-input']").text).to eq("Search Users:")
      expect(doc.at_css("#search-submit").text.strip).to eq("Search Users")
      headings = doc.css("h2.screen-reader-text").map(&:text)
      expect(headings).to include("Users list", "Filter users list")
    end

    it "still renders both tablenavs and both Select All checkboxes" do
      expect(doc.css("div.tablenav").length).to eq(2)
      expect(doc.at_css("#cb-select-all-1")).to be_present
      expect(doc.at_css("#cb-select-all-2")).to be_present
    end
  end
end
