# frozen_string_literal: true

module Library
  # wp_upload_dir() / _wp_upload_dir(), wp-includes/functions.php — where an upload
  # lands. Under `uploads_use_yearmonth_folders` the subdirectory is `/YYYY/MM` of the
  # upload's TIME, which media_handle_sideload() (wp-admin/includes/media.php:465) takes
  # from the parent post's `post_date` when there is one and from current_time('mysql')
  # — the SITE's wall clock, not UTC — otherwise. That is why a file attached to a March
  # post lands in `2026/03` in August (verified against the oracle).
  #
  # The storage root is fixed at `wp-content/uploads`: the `upload_path` /
  # `upload_url_path` settings that relocate it in the legacy are an installation-era
  # feature this rebuild's Active Storage service replaces (see
  # lib/active_storage/service/uploads_service.rb). AD-01 removes the `upload_dir` filter.
  class UploadDirectory
    BASEURL = "/wp-content/uploads"

    attr_reader :subdir

    def self.for(time = nil)
      new(subdir_for(time))
    end

    # `$subdir = "/$y/$m"` from the first 4 and characters 5-6 of the MySQL datetime.
    def self.subdir_for(time)
      return "" unless yearmonth_folders?

      stamp = time.nil? ? site_now : time
      stamp = stamp.in_time_zone(site_time_zone) if stamp.respond_to?(:in_time_zone)
      text = stamp.respond_to?(:strftime) ? stamp.strftime("%Y-%m-%d %H:%M:%S") : stamp.to_s
      "/#{text[0, 4]}/#{text[5, 2]}"
    end

    # get_option( 'uploads_use_yearmonth_folders' ): '1' on every default install; a
    # missing setting reads as false in the legacy, and does here.
    def self.yearmonth_folders?
      value = Configuration::Setting["uploads_use_yearmonth_folders"]
      value = value.first if value.is_a?(Array)
      !(value.nil? || value == false || value.to_s == "" || value.to_s == "0")
    end

    # current_time( 'mysql' ): now, in the site's timezone (`timezone_string`, else
    # `gmt_offset` hours — wp-includes/functions.php current_time()).
    def self.site_now = Time.current.in_time_zone(site_time_zone)

    def self.site_time_zone
      name = Configuration::Setting["timezone_string"]
      name = nil unless name.is_a?(String) && !name.empty?
      zone = ActiveSupport::TimeZone[name] if name
      return zone if zone

      offset = Configuration::Setting["gmt_offset"]
      ActiveSupport::TimeZone[offset.to_s.to_f * 3600] || ActiveSupport::TimeZone["UTC"]
    end

    def initialize(subdir)
      @subdir = subdir.to_s
    end

    # `2026/08` — the prefix of every blob key in this directory; '' at the root.
    def prefix = subdir.delete_prefix("/")

    def key_for(filename) = prefix.empty? ? filename.to_s : "#{prefix}/#{filename}"

    def url_for(filename) = "#{BASEURL}#{subdir}/#{filename}"

    # What `scandir( $dir )` would have returned: the files physically in the service's
    # directory (including ones `assets:sync` copied in without a blob row) plus the
    # keys of every blob under the same prefix.
    def existing_names
      service = ActiveStorage::Blob.service
      on_disk = service.respond_to?(:existing_names) ? service.existing_names(prefix) : []
      pattern = prefix.empty? ? "%" : "#{prefix}/%"
      in_blobs = ActiveStorage::Blob.where("key LIKE ?", pattern).pluck(:key)
                                    .map { |k| k.delete_prefix(prefix.empty? ? "" : "#{prefix}/") }
                                    .reject { |k| k.include?("/") }
      (on_disk + in_blobs).uniq
    end
  end
end
