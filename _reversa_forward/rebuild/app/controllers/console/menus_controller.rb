# frozen_string_literal: true

module Console
  # console.nav-menus — nav-menus.php in modernized mode, over the AGG-Menu aggregate.
  # 🔑 BR-MENU-02: menu items are ROWS WITH COLUMNS now (the nine _menu_item_* postmeta
  # keys became real columns), and the menu_items_one_target CHECK makes the invariant the
  # legacy could not express — "an item targets exactly one of a content record, a term,
  # or a custom URL" — a database guarantee (MenuItem#exactly_one_target mirrors it for
  # the message).
  #
  # A server-side tree editor (DEV-012's React island is out of scope): add / move /
  # remove items, each through the model so the CHECK and the validations decide. LITERAL
  # strings verbatim — "Menus", "Edit Menus", "Manage Locations", "Menu Name", "Create
  # Menu", "Save Menu", "Delete Menu", "Add to Menu", "Navigation Label", "URL", "Remove",
  # "Menu Location", "Assigned Menu", "Menu locations updated.", "Please enter a valid menu
  # name.", "%s has been updated.", "The menu has been successfully deleted."
  #
  # AD-04: :policy on `edit_theme_options` (nav-menus.php:23), a real capability.
  class MenusController < BaseController
    # DEV-002: register_nav_menus() was hook-registered UI; here the set of theme menu
    # locations is DECLARED, not discovered from a registry. The seeded active theme
    # (twentytwentyfive) is a BLOCK theme and registers no classic nav menu locations, so
    # this is empty — and the Manage Locations sub-screen then redirects to Edit Menus,
    # exactly as nav-menus.php:514 does when $num_locations is 0. A theme that declares
    # locations populates this map { slug => human label } and the sub-screen renders.
    NAV_MENU_LOCATIONS = {}.freeze

    before_action :load_menus
    before_action :load_menu, only: %i[show update destroy add_item remove_item move_item]

    # GET /console/menus — the "Edit Menus" tab, or "Manage Locations" with ?tab=locations.
    def index
      @menu ||= (params[:menu_id].present? ? @menus.find { |m| m.id == params[:menu_id].to_i } : @menus.first)
      set_chrome
      return render_locations if locations_tab?

      load_add_item_sources
      render :index
    end

    # GET /console/menus/:id
    def show
      set_chrome
      load_add_item_sources
      render :index
    end

    # POST /console/menus — "Create Menu", or the "Manage Locations" save (single endpoint,
    # the way nav-menus.php POSTs both to itself and branches on the fields present).
    def create
      set_chrome
      return save_locations if params[:save_nav_menu_locations].present?

      name = params[:menu_name].to_s
      menu = Presentation::Menu.new(name: name, slug: menu_slug(name))
      if menu.save
        flash[:success] = format("%s has been updated.", menu.name)
        redirect_to "/console/menus/#{menu.id}", status: :see_other
      else
        @menu = menu
        load_add_item_sources
        flash.now[:error] = menu_name_error(menu)
        render :index, status: :unprocessable_content
      end
    end

    # PATCH /console/menus/:id — "Save Menu": rename.
    def update
      set_chrome
      if @menu.update(name: params[:menu_name].to_s)
        flash[:success] = format("%s has been updated.", @menu.name)
        redirect_to "/console/menus/#{@menu.id}", status: :see_other
      else
        load_add_item_sources
        flash.now[:error] = menu_name_error(@menu)
        render :index, status: :unprocessable_content
      end
    end

    # DELETE /console/menus/:id — "Delete Menu". The FK cascade removes the items (AGG-Menu:
    # the FK the legacy lacked, which is why it needed _menu_item_orphaned tombstones).
    def destroy
      @menu.destroy!
      flash[:success] = "The menu has been successfully deleted."
      redirect_to "/console/menus", status: :see_other
    end

    # POST /console/menus/:id/items — "Add to Menu". Exactly one target arm is taken.
    def add_item
      set_chrome
      item = @menu.menu_items.new(item_attributes)
      if item.save
        flash[:success] = format("%s has been updated.", @menu.name)
        redirect_to "/console/menus/#{@menu.id}", status: :see_other
      else
        @menu.reload
        load_add_item_sources
        flash.now[:error] = item.errors.full_messages.first
        render :index, status: :unprocessable_content
      end
    end

    # DELETE /console/menus/:id/items/:item_id — "Remove". Children cascade (dependent).
    def remove_item
      @menu.menu_items.find(params[:item_id]).destroy!
      flash[:success] = format("%s has been updated.", @menu.name)
      redirect_to "/console/menus/#{@menu.id}", status: :see_other
    end

    # PATCH /console/menus/:id/items/:item_id — move (reparent / reorder) or relabel.
    def move_item
      set_chrome
      item = @menu.menu_items.find(params[:item_id])
      item.assign_attributes(move_attributes)
      if item.save
        flash[:success] = format("%s has been updated.", @menu.name)
        redirect_to "/console/menus/#{@menu.id}", status: :see_other
      else
        @menu.reload
        load_add_item_sources
        flash.now[:error] = item.errors.full_messages.first
        render :index, status: :unprocessable_content
      end
    end

    private

    def set_chrome
      @page_title = "Menus"
      @screen = "console.nav-menus"
      @active_tab = locations_tab? ? "locations" : "edit"
    end

    def locations_tab? = params[:tab].to_s == "locations"

    # nav-menus.php:513 `case 'locations'`: with no registered theme locations, the legacy
    # redirects straight back to Edit Menus. Otherwise it renders the assignment table.
    def render_locations
      return redirect_to "/console/menus", status: :see_other if registered_locations.empty?

      @locations = registered_locations
      @assigned = menu_locations
      render :locations
    end

    # nav-menus.php:527 — the save arm of `case 'locations'`. Assign each registered
    # location to a menu (or clear it) and emit the verbatim notice. The assignment set is
    # the modernized stand-in for set_theme_mod('nav_menu_locations', …).
    def save_locations
      return redirect_to "/console/menus", status: :see_other if registered_locations.empty?

      submitted = params[:menu_locations] || {}
      assignments = registered_locations.keys.filter_map do |slug|
        value = submitted[slug].to_i
        [slug, value] if value.positive?
      end.to_h
      Configuration::Setting.set("nav_menu_locations", assignments)
      flash[:success] = "Menu locations updated." # nav-menus.php:530
      redirect_to "/console/menus?tab=locations", status: :see_other
    end

    def registered_locations = NAV_MENU_LOCATIONS

    def menu_locations
      stored = Configuration::Setting["nav_menu_locations"]
      stored.is_a?(Hash) ? stored : {}
    end

    def load_menus = @menus = Presentation::Menu.order(:name).to_a

    def load_menu = @menu = Presentation::Menu.find(params[:id])

    # The four initial add-item panels (nav-menu.php:233): Pages, Posts, Custom Links and
    # Categories. The Custom Links panel needs no source; the others are the content the
    # menu is actually built from — without these the screen's core purpose (a menu of
    # pages/posts/categories) is unreachable through the UI.
    def load_add_item_sources
      return unless @menu&.persisted?

      @pages = Publishing::Page.where(status: :published).order(:title).to_a
      @posts = Publishing::Article.where(status: :published).order(:title).to_a
      category = Classification::Taxonomy.find_by(name: "category")
      @categories = category ? Classification::Term.where(taxonomy_id: category.id).order(:name).to_a : []
    end

    # nav-menus.php:446/475 __( 'Please enter a valid menu name.' ) — the blank-name arm.
    # The model's presence validation would otherwise surface ActiveModel's default; this
    # maps the name error back to the legacy's exact string.
    def menu_name_error(menu)
      return "Please enter a valid menu name." if menu.errors[:name].present?

      menu.errors.full_messages.first
    end

    # A custom URL, a post target, or a term target — exactly one, chosen by `kind`. The
    # navigation label defaults to the target's own title/name when none is typed, exactly
    # as the legacy meta boxes seed the label from the object title.
    def item_attributes
      label = params[:label].to_s
      base = { title: params[:title].to_s, position: next_position, parent_id: params[:parent_id].presence }
      case params[:kind]
      when "post"
        target = Publishing::Post.find_by(id: params[:target_id])
        base.merge(target_type: "Publishing::Post", target_id: params[:target_id],
                   label: label.presence || target&.title.to_s)
      when "term"
        target = Classification::Term.find_by(id: params[:target_id])
        base.merge(target_type: "Classification::Term", target_id: params[:target_id],
                   label: label.presence || target&.name.to_s)
      else # "custom"
        base.merge(url: params[:url].presence, label: label)
      end
    end

    def move_attributes
      attrs = {}
      attrs[:parent_id] = params[:parent_id].presence if params.key?(:parent_id)
      attrs[:position] = params[:position].to_i if params.key?(:position)
      attrs[:label] = params[:label].to_s if params.key?(:label)
      attrs
    end

    def next_position
      (@menu.menu_items.where(parent_id: params[:parent_id].presence).maximum(:position) || -1) + 1
    end

    def menu_slug(name)
      base = name.to_s.parameterize.presence || "menu"
      slug = base
      n = 1
      slug = "#{base}-#{n += 1}" while Presentation::Menu.exists?(slug: slug)
      slug
    end
  end
end
