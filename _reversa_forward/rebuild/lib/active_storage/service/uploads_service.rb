# frozen_string_literal: true

require "active_storage/service/disk_service"

module ActiveStorage
  class Service
    # The uploads directory, served at the legacy URL shape.
    #
    # Every golden screen references files as `/wp-content/uploads/YYYY/MM/<name>` —
    # `wp_upload_dir()` (wp-includes/functions.php) plus `wp_get_attachment_url()`
    # (wp-includes/post.php). Active Storage's DiskService shards a key into
    # `<root>/ab/cd/abcd…`, which would put the file somewhere the URL does not point.
    # This service keeps the key AS the path: the blob key is the legacy relative upload
    # path (`2026/08/oracle-image.png`), the root is `public/wp-content/uploads`, and the
    # static file server answers the legacy URL without a controller in between.
    #
    # Everything else — upload, download, delete, checksum — is inherited unchanged.
    class UploadsService < DiskService
      def path_for(key) # :nodoc:
        File.join(root, key)
      end

      # A listing of the files that already exist under one relative directory, which is
      # what wp_unique_filename() (functions.php:2589) scans before naming a new upload.
      # Files copied in by `assets:sync` are visible here even though no blob row
      # describes them, exactly as the legacy sees a directory rather than a table.
      def existing_names(subdir)
        dir = File.join(root, subdir.to_s)
        return [] unless File.directory?(dir)

        Dir.children(dir)
      end

      # Blob keys are the path; `public: true` would only change URL generation, which
      # the routes below never use. Keys with `..` segments are refused here so a crafted
      # filename cannot escape the uploads root.
      def upload(key, io, checksum: nil, **)
        raise ArgumentError, "unsafe upload key #{key.inspect}" if key.to_s.split("/").include?("..")

        super
      end
    end
  end
end
