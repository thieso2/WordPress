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
  # strings verbatim — "Menus", "Edit Menus", "Menu Name", "Create Menu", "Save Menu",
  # "Delete Menu", "Add to Menu", "Navigation Label", "URL", "Remove", "%s has been
  # updated.", "The menu has been successfully deleted."
  #
  # AD-04: :policy on `edit_theme_options` (nav-menus.php:23), a real capability.
  class MenusController < BaseController
    before_action :load_menus
    before_action :load_menu, only: %i[show update destroy add_item remove_item move_item]

    # GET /console/menus — the "Edit Menus" tab.
    def index
      @menu ||= (params[:menu_id].present? ? @menus.find { |m| m.id == params[:menu_id].to_i } : @menus.first)
      set_chrome
      render :index
    end

    # GET /console/menus/:id
    def show
      set_chrome
      render :index
    end

    # POST /console/menus — "Create Menu".
    def create
      set_chrome
      menu = Presentation::Menu.new(name: params[:menu_name].to_s, slug: menu_slug(params[:menu_name]))
      if menu.save
        flash[:success] = format("%s has been updated.", menu.name)
        redirect_to "/console/menus/#{menu.id}", status: :see_other
      else
        @menu = menu
        flash.now[:error] = menu.errors.full_messages.first
        render :index, status: :unprocessable_content
      end
    end

    # PATCH /console/menus/:id — "Save Menu": rename.
    def update
      set_chrome
      if @menu.update(name: params[:menu_name].presence || @menu.name)
        flash[:success] = format("%s has been updated.", @menu.name)
        redirect_to "/console/menus/#{@menu.id}", status: :see_other
      else
        flash.now[:error] = @menu.errors.full_messages.first
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
        flash.now[:error] = item.errors.full_messages.first
        render :index, status: :unprocessable_content
      end
    end

    private

    def set_chrome
      @page_title = "Menus"
      @screen = "console.nav-menus"
    end

    def load_menus = @menus = Presentation::Menu.order(:name).to_a

    def load_menu = @menu = Presentation::Menu.find(params[:id])

    # A custom URL, a post target, or a term target — exactly one, chosen by `kind`.
    def item_attributes
      base = { label: params[:label].to_s, title: params[:title].to_s,
               position: next_position, parent_id: params[:parent_id].presence }
      case params[:kind]
      when "post"
        base.merge(target_type: "Publishing::Post", target_id: params[:target_id])
      when "term"
        base.merge(target_type: "Classification::Term", target_id: params[:target_id])
      else # "custom"
        base.merge(url: params[:url].presence)
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
