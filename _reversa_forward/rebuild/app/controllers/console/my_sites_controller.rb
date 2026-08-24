# frozen_string_literal: true

module Console
  # console.my-sites — wp-admin/my-sites.php, "the per-user list of sites they belong to".
  #
  # ⚠️ NOT a network-admin screen: my-sites.php gates on `read` (:19), the capability every
  # role holds, because it is the ordinary user's own view of their memberships. So it does
  # NOT descend from Console::Network::BaseController — it needs the multisite gate but not
  # the super-admin capability. It is still STRICTLY ADDITIVE: `require_network!` answers
  # 404 with my-sites.php:13's verbatim `Multisite support is not enabled.` on a single site,
  # so nothing about single-site behaviour changes.
  #
  # LITERAL strings verbatim from my-sites.php:
  #   'My Sites'                                                    (:41, :78)
  #   'Add New Site'                                                (:87)
  #   'You must be a member of at least one site to use this page.'  (:92)
  #   'Visit' / 'Dashboard'                                         (:139-144)
  #   'Primary Site' / 'Not available'          (includes/ms.php:767, :799)
  #   'The primary site you chose does not exist.'                   (:32)
  #   'Settings saved.'                                              (:68)
  #   'Multisite support is not enabled.'                            (:13)
  class MySitesController < BaseController
    include Console::Chrome

    NOT_MULTISITE = "Multisite support is not enabled."
    NO_SUCH_PRIMARY = "The primary site you chose does not exist."
    SAVED_NOTICE = "Settings saved."

    # ⚠️ PREPENDED — ahead of auth_redirect and ahead of AD-04, so the screen does not
    # exist at all on a single site rather than merely refusing.
    prepend_before_action :require_network!

    # GET /console/my-sites
    def show
      prepare
      render "console/my_sites/show"
    end

    # POST /console/my-sites — my-sites.php:26-36, `action=updateblogsettings`.
    def update
      prepare
      chosen = params[:primary_blog].to_i
      return deny!(NO_SUCH_PRIMARY) unless @sites.any? { |site| site.id == chosen }

      store_primary_site(chosen)
      redirect_after_submit("/console/my-sites", notice: SAVED_NOTICE)
    end

    private

    def require_network!
      return if Tenancy.enabled?

      @message = NOT_MULTISITE
      render "console/shared/not_found", status: :not_found
    end

    def prepare
      @page_title = "My Sites"
      @screen = "console.my-sites"

      # get_blogs_of_user( $current_user->ID ) — the sites this actor holds a role on.
      # Roles are ROWS scoped by site_id (T-03 / BR-MS-04), so membership is one join
      # rather than the legacy's scan of every `wp_{id}_capabilities` usermeta key.
      site_ids = Identity::RoleAssignment.where(user_id: current_actor&.id)
                                         .where.not(site_id: nil).distinct.pluck(:site_id)
      @sites = Tenancy::Site.where(id: site_ids).order(:domain, :path).to_a
      @primary_site_id = primary_site_id
      # my-sites.php:83 — the "Add New Site" action appears only when the network's
      # `registration` option admits site creation.
      @can_add_site = %w[all blog].include?(Tenancy::NetworkSetting["registration"].to_s)
      @site_urls = @sites.to_h { |site| [site.id, site_home_url(site)] }
      @site_admin_urls = @sites.to_h { |site| [site.id, "#{site_home_url(site).sub(%r{/\z}, '')}/console"] }
    end

    def site_home_url(site) = "#{request.protocol}#{site.domain}#{site.path}"

    # ⚠️ HONEST LIMITATION, reported rather than hidden. The legacy stores this in
    # `usermeta['primary_blog']`; AD-06 removed the meta table and Identity has no per-user
    # preference store yet, so the choice lives in ONE network option holding a
    # user_id => site_id map. That is the right OBSERVABLE behaviour and the wrong home:
    # a per-user preferences table is the proper destination and is recorded as deferred.
    PRIMARY_SITE_OPTION = "primary_blog"

    def primary_site_map = (Tenancy::NetworkSetting[PRIMARY_SITE_OPTION] || {}).to_h

    def primary_site_id = primary_site_map[current_actor&.id.to_s].to_i

    def store_primary_site(site_id)
      Tenancy::NetworkSetting[PRIMARY_SITE_OPTION] = primary_site_map.merge(current_actor.id.to_s => site_id)
    end
  end
end
