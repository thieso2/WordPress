# frozen_string_literal: true

module Library
  # AGG-Asset — target_domain_model.md § AGG-Asset.
  #
  # This aggregate exists BECAUSE AD-02 split it out of wp_posts. In the legacy its
  # whole model lived in four _wp_attachment* / _thumbnail_id postmeta keys precisely
  # because the post shape did not fit it.
  #
  # Wave 3 makes the blob real. `original` is the uploaded bytes — exactly one, never
  # rewritten. `scaled` and every Library::Variant are DERIVED from it and regenerable
  # (AGG-Asset invariant); `metadata` is the legacy `_wp_attachment_metadata` shape so the
  # Wave 2 read path (srcset, attachment redirect) keeps reading what it read.
  class Asset < ApplicationRecord
    self.table_name = "assets"

    belongs_to :uploader, class_name: "Identity::User", optional: true
    # ⚠️ Deliberately NOT `belongs_to :attached_to`. Owner ruling 2026-08-22: this column
    # records the legacy `post_parent` — the post being edited when the file was uploaded —
    # which is provenance, not structure. Declaring the association would put a
    # Library -> Publishing edge back into the graph and re-form the cycle that AD-03's
    # posts.featured_asset_id already creates in the other direction.
    # Query from the Publishing side, or read the raw column.
    has_many :variants, class_name: "Library::Variant", dependent: :destroy

    # ⚠️ Deliberately NO `has_many :featured_on` and no `has_many :assignments`.
    # target_architecture.md's intended graph has Classification -> Library and
    # Publishing -> Library; declaring the inverses here would add the back-edges
    # Library -> Classification and Library -> Publishing for no gain. Both FKs
    # (posts.featured_asset_id, term_assignments.classifiable_*) already carry the
    # relationship, with ON DELETE SET NULL / CASCADE doing the dependent work.

    # The one original blob. `_wp_attached_file` pointed at the file on disk; the blob key
    # IS that relative path (`2026/08/oracle-image.png`), served at /wp-content/uploads/.
    has_one_attached :original, dependent: false
    # wp_create_image_subsizes() (wp-admin/includes/image.php:240): an original wider or
    # taller than BIG_IMAGE_SIZE_THRESHOLD is scaled, and the `-scaled` copy becomes the
    # "full" size `metadata['file']` names while `metadata['original_image']` keeps the
    # upload's name. Same for an EXIF-rotated `-rotated` copy. Regenerable, so not a
    # second original.
    has_one_attached :scaled, dependent: false

    # AGG-Asset accepted command `delete`: the files go with the row, now, not later.
    before_destroy :purge_blobs

    # BR-MIGRATE-088: every upload generates one file per registered subsize. These are
    # WordPress's registered subsizes, read from the oracle
    # (`wp_get_registered_image_subsizes()`), with `medium_large`'s unconstrained
    # height (768x0) preserved exactly as the legacy registers it.
    #
    # AD-01: the legacy assembles this list through `add_image_size()` plus the
    # `intermediate_image_sizes_advanced` filter. There is no hook system here, so the
    # registry is a stated constant — the pre-filter default, permanently — and the four
    # option-backed entries read their dimensions from Configuration (`registered_sizes`).
    REGISTERED_SIZES = {
      "thumbnail"   => { width: 150,  height: 150,  crop: true  },
      "medium"      => { width: 300,  height: 300,  crop: false },
      "medium_large" => { width: 768, height: 0,    crop: false },
      "large"       => { width: 1024, height: 1024, crop: false },
      "1536x1536"   => { width: 1536, height: 1536, crop: false },
      "2048x2048"   => { width: 2048, height: 2048, crop: false }
    }.freeze

    # get_intermediate_image_sizes() (media.php:895): the four names whose dimensions
    # live in options. The other two come from `_wp_add_additional_image_sizes()`.
    OPTION_BACKED_SIZES = %w[thumbnail medium medium_large large].freeze

    # _wp_make_subsizes() (image.php:497): "sort the image sub-sizes in order of
    # priority when creating them", so that a failure part-way leaves the useful ones.
    SIZE_PRIORITY = %w[medium large thumbnail medium_large].freeze

    # wp_unique_post_slug() (post.php:5602): an attachment slug may not be a feed name
    # (`$wp_rewrite->feeds`, class-wp-rewrite.php) or `embed`.
    RESERVED_SLUGS = %w[feed rdf rss rss2 atom embed].freeze

    # _truncate_post_slug( $slug, 200 - ( strlen( $suffix ) + 1 ) ), post.php:5609.
    SLUG_MAX_BYTES = 200

    # BR-MIGRATE-033: attachment slugs are unique across ALL types in the legacy, which
    # is why this is a plain unique index rather than one scoped to a parent.
    validates :slug, presence: true, uniqueness: true
    validates :mime_type, :byte_size, presence: true

    # wp_get_registered_image_subsizes(), wp-includes/media.php:930. Each option-backed
    # size reads `{name}_size_w`, `{name}_size_h` and `{name}_crop`; a size with neither
    # width nor height is dropped (:958). Missing settings fall back to the registry above.
    def self.registered_sizes
      REGISTERED_SIZES.each_with_object({}) do |(name, default), out|
        spec = default.dup
        if OPTION_BACKED_SIZES.include?(name)
          w = setting_int("#{name}_size_w")
          h = setting_int("#{name}_size_h")
          spec[:width] = w unless w.nil?
          spec[:height] = h unless h.nil?
          crop = Configuration::Setting["#{name}_crop"]
          spec[:crop] = !(crop == false || crop.to_s == "" || crop.to_s == "0") unless crop == false && !Configuration::Setting.exists?(name: "#{name}_crop")
        end
        next if spec[:width].to_i.zero? && spec[:height].to_i.zero?

        out[name] = spec
      end
    end

    def self.setting_int(name)
      return nil unless Configuration::Setting.exists?(name: name)

      Configuration::Setting[name].to_s.to_i
    end

    # AGG-Asset accepted command `upload` — media_handle_sideload() (wp-admin/includes/
    # media.php:465) end to end: _wp_handle_upload() (file.php:809) decides whether the
    # bytes may be stored and under what name, wp_insert_attachment() (post.php:6778)
    # records the row, wp_generate_attachment_metadata() (image.php:579) derives the rest.
    #
    # The filename is used for the title, the slug and the stored name — after
    # sanitize_file_name() and the content check have had their say — and for NOTHING
    # else: the MIME type and the dimensions come out of the bytes. That is the
    # invariant, expressed as a call signature.
    #
    #   io              the upload (IO, Pathname or String of bytes)
    #   filename        the client's name
    #   sizes           registered sub-sizes; defaults to `registered_sizes`
    #   uploader        Identity::User (post_author)
    #   attached_to_id  legacy post_parent
    #   time            the parent's post_date, else now (decides /YYYY/MM)
    #   title           `$desc` — overrides the filename-derived title
    #   unfiltered_html whether the uploader may store HTML/JS files (functions.php:3698)
    #
    # Raises Library::UploadError with the legacy's verbatim message when refused.
    def self.upload!(io:, filename:, sizes: nil, uploader: nil, attached_to_id: nil, time: nil,
                     title: nil, unfiltered_html: false, **attributes)
      bytes = read_all(io)
      # file.php:946 — "A non-empty file will pass this test."
      raise UploadError, UploadError::EMPTY if bytes.empty?

      # file.php:958 — wp_check_filetype_and_ext(); a corrected name replaces the
      # client's. Nobody holds `unfiltered_upload` (it is granted by no role and AD-01
      # leaves no way to grant it), so the refusal is unconditional.
      verdict = FileTypeCheck.call(bytes, filename, unfiltered_html: unfiltered_html)
      raise UploadError, UploadError::FORBIDDEN_TYPE unless verdict.allowed?

      client_name = verdict.proper_filename || filename.to_s
      directory = UploadDirectory.for(time)
      stored_name = FileName.unique(client_name, existing: directory.existing_names)

      # media.php:491 — the title is the stored name without its extension...
      derived_title = stored_name.sub(/\.[^.]+\z/, "")
      alt = attributes.fetch(:alt_text, "").to_s
      # ...unless the image carries a usable EXIF/IPTC title (:498), and the EXIF alt
      # becomes the alt text when none was given (:535).
      image_meta = ImageMetadata.read(bytes, verdict.type)
      if image_meta
        exif_title = image_meta["title"].to_s.strip
        if !exif_title.empty? && !numeric_slug?(Sanitizing::Formatting.sanitize_title(exif_title))
          derived_title = exif_title
        end
        alt = Sanitizing::Formatting.strip_tags(image_meta["alt"]).strip if alt.empty? && !image_meta["alt"].to_s.strip.empty?
      end
      final_title = title.nil? ? derived_title : title.to_s

      transaction do
        asset = create!(
          title: final_title,
          slug: allocate_slug(final_title),
          mime_type: verdict.type,
          byte_size: bytes.bytesize,
          uploader: uploader,
          attached_to_id: attached_to_id,
          alt_text: alt,
          caption: attributes.fetch(:caption, "").to_s,
          metadata: { "file" => directory.key_for(stored_name) },
          **attributes.except(:alt_text, :caption)
        )
        asset.original.attach(store_blob(bytes, stored_name, directory.key_for(stored_name), verdict.type))
        asset.generate_metadata!(sizes)
        asset
      end
    end

    # "MIME type is determined from content, not from the filename extension alone."
    # target_domain_model.md § AGG-Asset invariants. The full verdict — including the
    # rename — is Library::FileTypeCheck; this is the bare content sniff for callers
    # that only need the type (the oracle agrees: a PNG named `parity_test.jpg` reports
    # image/png from wp_check_filetype_and_ext(), image/jpeg from the name-only check).
    def self.sniff_mime_type(bytes_or_io)
      data = read_all(bytes_or_io)
      FileTypeCheck.image_mime(data) || Fileinfo.mime(data)
    end

    # Active Storage uploads an attached IO only after COMMIT; the bytes are needed inside
    # the transaction (to derive the sub-sizes), so the blob is written up front and the
    # attachment points at it. The key is the legacy relative path.
    def self.store_blob(bytes, filename, key, content_type)
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: filename, key: key,
                                             content_type: content_type, identify: false)
    end

    def self.read_all(io)
      return File.binread(io) if io.is_a?(Pathname)
      return io.b unless io.respond_to?(:read)

      io.rewind if io.respond_to?(:rewind)
      io.read.to_s.b
    end

    # wp_insert_post() → sanitize_title( $post_title ) → wp_unique_post_slug() for
    # post_type 'attachment' (post.php:5597): unique across ALL attachments, never a feed
    # name or `embed`, `-2`, `-3`… appended within the 200-byte budget. The unique index
    # is what actually guarantees it (AD-05); this only picks a candidate that will not
    # collide.
    #
    # ⚠️ The legacy's "all types" also spans posts and pages, which live in a different
    # table here (AD-02). Library cannot read Publishing without re-forming the
    # Publishing <-> Library cycle, so the scope of this uniqueness is the assets table.
    def self.allocate_slug(title)
      base = Sanitizing::Formatting.sanitize_title(title.to_s).presence || "asset"
      return base unless exists?(slug: base) || RESERVED_SLUGS.include?(base)

      suffix = 2
      loop do
        candidate = "#{truncate_slug(base, SLUG_MAX_BYTES - (suffix.to_s.length + 1))}-#{suffix}"
        return candidate unless exists?(slug: candidate)

        suffix += 1
      end
    end

    # _truncate_post_slug(), post.php:5702: a byte budget that never splits a
    # percent-encoded sequence.
    def self.truncate_slug(slug, length)
      return slug if slug.bytesize <= length

      decoded = URI.decode_www_form_component(slug) rescue slug
      if decoded == slug
        slug.byteslice(0, length).to_s.scrub("")
      else
        Sanitizing::Formatting.utf8_uri_encode(decoded, length)
      end.sub(/-+\z/, "")
    end

    def self.numeric_slug?(slug) = slug.to_s.match?(/\A\d+\z/)

    def image? = mime_type.to_s.start_with?("image/")

    def attached? = attached_to_id.present?

    # `_wp_attached_file` — the relative upload path of the "full" file.
    def file = metadata.to_h["file"].to_s

    # wp_get_attachment_url() (post.php:7191): uploads baseurl + the attached file's path.
    def url = file.empty? ? nil : "#{UploadDirectory::BASEURL}/#{file}"

    # AGG-Asset accepted commands `attach` / `detach`. Detaching is not deletion: the
    # asset outlives the record that displayed it, which is the whole reason
    # `assets.attached_to_id` is ON DELETE SET NULL rather than ON DELETE CASCADE.
    def attach!(record)
      update!(attached_to_id: record&.id)
    end

    def detach! = update!(attached_to_id: nil)

    # AGG-Asset invariant: "variants are derivable and may be regenerated without data
    # loss." Regeneration is therefore destructive-and-rebuild by design, and the only
    # thing it is allowed to consume is the original blob — or, for a corpus row that
    # arrived without one (lib/seeding/pipeline.rb), the original's recorded geometry.
    #
    # BR-MIGRATE-088 generates one variant per registered size; BR-MIGRATE-079 is what
    # makes that "one per size that would not be an upscale".
    def regenerate_variants!(sizes = nil)
      transaction do
        variants.each(&:destroy)
        variants.reset
        if original.attached?
          scaled.purge if scaled.attached?
          generate_metadata!(sizes)
        else
          variant_geometry(sizes || self.class.registered_sizes).each do |size_name, rect|
            variants.create!(size_name: size_name, width: rect.width, height: rect.height,
                             mime_type: mime_type)
          end
        end
      end
      variants.reset
      self
    end

    # Which subsizes this asset's original supports, and at what dimensions. Separated
    # out so the decision is inspectable without writing rows.
    def variant_geometry(sizes = self.class.registered_sizes)
      return {} unless image? && width.to_i.positive? && height.to_i.positive?

      sizes.each_with_object({}) do |(size_name, spec), out|
        rect = Geometry.resize(width, height, spec[:width], spec[:height], spec[:crop])
        out[size_name.to_s] = rect if rect
      end
    end

    # wp_generate_attachment_metadata(), wp-admin/includes/image.php:579, then
    # wp_update_attachment_metadata(). Images get sub-sizes (BR-MIGRATE-088); everything
    # else records its size. Video/audio ID3 reading (wp_read_video_metadata) and the
    # Imagick PDF preview have no counterpart — the oracle itself, without Imagick,
    # stores `{"filesize": N}` for a PDF, and that is what this stores.
    def generate_metadata!(sizes = nil)
      raise ArgumentError, "no original blob to derive from" unless original.attached?

      bytes = original.download
      directory = UploadDirectory.new(File.dirname(original.key) == "." ? "" : "/#{File.dirname(original.key)}")
      meta = {}
      meta = create_image_subsizes!(bytes, directory, sizes || self.class.registered_sizes) if image? && ImageEditor.displayable?(mime_type)

      # `_wp_attached_file` rides in metadata['file'] here (target_data_model.md: assets
      # have no separate column), so it is recorded for non-images too.
      meta["file"] ||= original.key
      meta["filesize"] ||= bytes.bytesize
      update!(metadata: meta, width: meta["width"], height: meta["height"], byte_size: meta["filesize"])
      variants.reset
      self
    end

    private

    # wp_create_image_subsizes() + _wp_make_subsizes(), image.php:240 / :469.
    def create_image_subsizes!(bytes, directory, sizes)
      dims = ImageProbe.dimensions(bytes)
      editor = ImageEditor.open(bytes, mime_type)
      dims ||= [editor.width, editor.height] if editor
      return {} if dims.nil? || dims[0].to_i <= 0 # wp_getimagesize() false: not an image

      meta = { "width" => dims[0], "height" => dims[1], "file" => original.key,
               "filesize" => bytes.bytesize, "sizes" => {} }
      exif_meta = ImageMetadata.read(bytes, mime_type)
      meta["image_meta"] = exif_meta if exif_meta

      base = FileName.php_filename(original.filename.to_s)
      ext = FileName.php_extension(original.filename.to_s).downcase
      threshold = ImageEditor::BIG_IMAGE_SIZE_THRESHOLD
      scale_down = meta["width"] > threshold || meta["height"] > threshold
      orientation = exif_meta ? exif_meta["orientation"].to_i : 0

      if scale_down
        return meta unless editor # "This image cannot be edited." :301

        editor.resize!(threshold, threshold)
        rotated = exif_meta ? editor.rotate! : false
        saved = editor.save
        store_full!(saved, "#{base}-scaled.#{ext}", directory, meta)
        meta["image_meta"]["orientation"] = "1" if rotated && meta.dig("image_meta", "orientation").present?
      elsif orientation > 1 && editor
        # Rotate the whole original when EXIF says so, as `-rotated`. :371
        if editor.rotate!
          saved = editor.save
          store_full!(saved, "#{base}-rotated.#{ext}", directory, meta)
          meta["image_meta"]["orientation"] = "1" if meta.dig("image_meta", "orientation").present?
        end
      end

      # _wp_make_subsizes(): sub-sizes come from the ORIGINAL (for best quality), rotated
      # when stored EXIF data says so. :516
      editor = ImageEditor.open(bytes, mime_type)
      return meta unless editor

      editor.rotate! if meta["image_meta"].present?
      ordered = SIZE_PRIORITY.filter_map { |n| [n, sizes[n]] if sizes[n] }.to_h.merge(sizes.reject { |n, _| SIZE_PRIORITY.include?(n) })
      ordered.each do |size_name, spec|
        rect = Geometry.resize(editor.width, editor.height, spec[:width], spec[:height], spec[:crop])
        next unless rect # image_resize_dimensions() false → WP_Error → size skipped

        saved = editor.make_subsize(rect)
        filename = "#{base}-#{saved.width}x#{saved.height}.#{ext}"
        variant = variants.create!(size_name: size_name.to_s, width: saved.width, height: saved.height,
                                   mime_type: saved.mime_type)
        variant.file.attach(self.class.store_blob(saved.bytes, filename, directory.key_for(filename), saved.mime_type))
        meta["sizes"][size_name.to_s] = {
          "file" => filename, "width" => saved.width, "height" => saved.height,
          "mime-type" => saved.mime_type, "filesize" => saved.bytes.bytesize
        }
      end
      meta
    end

    # _wp_image_meta_replace_original(), image.php:206.
    def store_full!(saved, filename, directory, meta)
      scaled.attach(self.class.store_blob(saved.bytes, filename, directory.key_for(filename), saved.mime_type))
      meta["width"] = saved.width
      meta["height"] = saved.height
      meta["file"] = directory.key_for(filename)
      meta["filesize"] = saved.bytes.bytesize
      meta["original_image"] = original.filename.to_s
    end

    def purge_blobs
      scaled.purge if scaled.attached?
      original.purge if original.attached?
    end
  end
end
