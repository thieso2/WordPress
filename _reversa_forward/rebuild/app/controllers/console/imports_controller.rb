# frozen_string_literal: true

module Console
  # console.import — wp-admin/import.php.
  #
  # ⚠️ WHAT THIS SCREEN IS, AND WHY IT IS NOT A PORT OF import.php's MARKUP.
  # Modern import.php renders a LIST OF PLUGINS to install: get_importers() over the
  # `$wp_importers` global, padded out with wp_get_popular_importers()'s wordpress.org
  # API response, each row a Thickbox link into the plugin installer. Its own help tab
  # says why: "In previous versions of WordPress, all importers were built-in. They have
  # been turned into plugins since most people only use them once or infrequently."
  # (import.php:26).
  #
  # AD-01 removed the extension system. There is no `$wp_importers`, no plugin installer
  # and no hook for an importer to register through, so a faithful port of that screen is
  # a page of dead links — the shell of a feature with the feature removed. The previous
  # pass said as much on console.tools ("Importers were plugins in the legacy; with no
  # hook system there is nothing for one to attach to"), which was honest but left the
  # capability `import` gating nothing.
  #
  # So this screen is the thing the plugin list existed to reach: a REAL, BUILT-IN reader
  # for WordPress eXtended RSS — the format wp-admin/export.php writes
  # (wp-admin/includes/export.php) and the one this system already emits at
  # /console/tools/export. Import and Export become one round trip rather than an export
  # with no way back in. The capability, the menu position and the refusal string are
  # import.php's; the screen's INFORMATION ARCHITECTURE is the WordPress Importer's own
  # three steps (upload → assign authors → results), which is what the operator knows.
  #
  # AD-04: `GET/POST console/imports#*` are declared `:authenticated`, with the `import`
  # capability enforced HERE — the same reasoning as every other tools screen. import.php
  # :14-16 refuses with a LITERAL wp_die() string, and a `:policy` route denial is a bare
  # 403 with no message. Console::Chrome#require_capability! renders the verbatim refusal.
  #
  # BR-CAP-05: the controller is the only layer that touches Access. The views ask
  # nothing.
  class ImportsController < BaseController
    include Chrome

    # import.php:15, verbatim.
    IMPORT_DENIED = "Sorry, you are not allowed to import content into this site."

    # wp_import_handle_upload(), wp-admin/includes/import.php:80-89 — LITERAL, with the
    # three placeholders already interpolated as the legacy interpolates them.
    EMPTY_FILE = "File is empty. Please upload something more substantial. This error " \
                 "could also be caused by uploads being disabled in your php.ini file or by " \
                 "post_max_size being defined as smaller than upload_max_filesize in php.ini."

    # ⚠️ NOT a legacy string: the WordPress Importer is a plugin and is not in the corpus,
    # so no wording for a malformed WXR exists to be copied. This is the rebuild's own,
    # and is marked as such rather than passed off as literal (DEV-009).
    NOT_WXR = "That file could not be read as a WordPress eXtended RSS (WXR) export."

    # The staged upload. wp_import_handle_upload() parks the file as a `private`
    # attachment and schedules `importer_scheduled_cleanup` a day out; AD-06 bars the job
    # queue and AD-02 says an import file is not media, so the staging area is a plain
    # directory swept on the way in. Same lifetime, no cron, nothing in the Media Library.
    STAGING = "tmp/imports"
    STAGING_TTL = 1.day
    TOKEN = /\A[0-9a-f]{32}\z/

    before_action :guard

    # GET /console/tools/import — step 1, the upload form.
    def show
      @page_title = "Import"
      @screen = "console.import"
      @step = :upload
      render :show
    end

    # POST /console/tools/import — step 2. The file is parsed but NOTHING is written:
    # the operator is shown what the export contains and asked how to assign its authors
    # first, which is the WordPress Importer's own second screen and the sequence
    # export.php's instructions describe (:507-509).
    def prepare
      @page_title = "Import"
      @screen = "console.import"
      upload = params[:import]

      return fail_upload(EMPTY_FILE) unless upload.respond_to?(:read)

      bytes = upload.read.to_s
      return fail_upload(EMPTY_FILE) if bytes.strip.empty?

      begin
        @document = Importing::Wxr.parse(bytes)
      rescue Importing::Wxr::MalformedError => e
        return fail_upload("#{NOT_WXR} #{e.message.capitalize}.")
      end

      @token = stage!(bytes)
      @filename = upload.try(:original_filename).to_s
      @authors = author_rows(@document)
      @users = assignable_users
      @step = :assign
      render :show
    end

    # POST /console/tools/import/run — step 3. Runs the import and renders the
    # per-record summary.
    def create
      @page_title = "Import"
      @screen = "console.import"
      bytes = staged(params[:token])

      return fail_upload(EMPTY_FILE) if bytes.nil?

      @document = Importing::Wxr.parse(bytes)
      @result = Importing::Run.new(
        @document,
        author_mapping: author_mapping,
        fetch_attachments: params[:fetch_attachments].present?,
        actor: current_actor
      ).call
      # wp_import_cleanup(): the staged file is removed as soon as the run is over.
      discard!(params[:token])
      @step = :done
      render :show
    rescue Importing::Wxr::MalformedError => e
      fail_upload("#{NOT_WXR} #{e.message.capitalize}.")
    end

    private

    def guard = require_capability!("import", IMPORT_DENIED)

    def fail_upload(message)
      flash.now[:error] = message
      @step = :upload
      render :show, status: :unprocessable_content
    end

    # One row per author the file names — declared in a wp:author block or referenced by
    # an item's dc:creator. `suggested` is the account already holding that login or
    # email, which is what makes re-importing an export of THIS site a no-op rather than
    # a second copy of every user.
    def author_rows(document)
      document.author_keys.map do |key|
        author = document.author_for(key)
        existing = Identity::User.find_by(login: key)
        existing ||= Identity::User.find_by(email: author.email) if author&.email.present?
        { key: key, label: author&.label || key, email: author&.email.to_s, suggested: existing }
      end
    end

    # The console never renders a user list a view had to assemble; the controller
    # resolves it, as with every other P-LIST-adjacent screen.
    def assignable_users
      Identity::User.order(:login).limit(500).map { |u| [u.id, u.login] }
    end

    # params[:authors] => { "<wxr login>" => { "mode" => …, "user_id" => … } }
    def author_mapping
      raw = params[:authors]
      return {} if raw.blank?

      raw.permit!.to_h.transform_values { |v| v.is_a?(Hash) ? v : {} }
    end

    # ── Staging ──────────────────────────────────────────────────────────────────

    def staging_dir
      dir = Rails.root.join(STAGING)
      FileUtils.mkdir_p(dir)
      dir
    end

    def stage!(bytes)
      sweep!
      token = SecureRandom.hex(16)
      File.binwrite(staging_dir.join("#{token}.xml"), bytes)
      token
    end

    def staged(token)
      return nil unless token.to_s.match?(TOKEN)

      path = staging_dir.join("#{token}.xml")
      File.exist?(path) ? File.binread(path) : nil
    end

    def discard!(token)
      return unless token.to_s.match?(TOKEN)

      FileUtils.rm_f(staging_dir.join("#{token}.xml"))
    end

    # The legacy's one-day `importer_scheduled_cleanup`, without a scheduler: a staged
    # file older than the TTL is removed on the next upload. An abandoned step 2 cannot
    # leave content on disk indefinitely.
    def sweep!
      Dir.glob(staging_dir.join("*.xml")).each do |path|
        FileUtils.rm_f(path) if File.mtime(path) < STAGING_TTL.ago
      end
    rescue StandardError
      nil
    end
  end
end
