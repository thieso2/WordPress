# frozen_string_literal: true

require "json"

module Egress
  # console.theme-install's install action. The legacy downloads a package, unpacks it
  # into wp-content/themes and registers it; here — AD-02 — a theme lives in tables, so an
  # install verifies the package, unpacks it IN MEMORY and writes the theme's data
  # (theme.json, its templates and parts) into PostgreSQL as an INACTIVE
  # Presentation::Theme plus its Composition rows. Activation is a separate step
  # (Console::ThemesController#activate), exactly as themes.php separates install from
  # switch_theme().
  #
  # ⚠️ The package is signature-verified BEFORE a single byte is unpacked, unconditionally
  # and for every host (Egress::Package / SignatureVerifier — the BC-14 inversion of the
  # legacy's soft-fail default). An unverified package raises Package::Rejected and
  # nothing is written.
  class ThemeInstaller
    class InvalidPackage < StandardError; end

    # Captures unpacked entries instead of touching disk: AD-02 means a theme install
    # writes ROWS, never files, so the parity invariant "never writes outside declared
    # storage paths" holds trivially — it writes to no path at all.
    class MemoryDestination
      attr_reader :files

      def initialize = @files = {}

      def write(name, bytes)
        @files[name] = bytes
        name
      end
    end

    def initialize(client: Client.new, trusted_keys: TrustedKeys.default)
      @client = client
      @trusted_keys = trusted_keys
    end

    # @param package_url [String] the `download_link` from the directory listing.
    # @return [Presentation::Theme] the newly-installed, inactive theme.
    def install(package_url)
      package = Package.download(package_url, client: @client, trusted_keys: @trusted_keys)
      destination = MemoryDestination.new
      package.install!(into: destination)   # verifies, THEN extracts; raises if unverified
      build_theme(destination.files)
    end

    private

    def build_theme(files)
      slug = top_directory(files)
      raise InvalidPackage, "the package has no theme directory" if slug.nil?

      theme_json = read_json(files, "#{slug}/theme.json")
      header = read_header(files["#{slug}/style.css"])
      raise InvalidPackage, "the package is not a theme (no style.css header)" if header["Theme Name"].blank?

      theme_json = theme_json.merge(
        "name" => header["Theme Name"],
        "screenshot" => files.key?("#{slug}/screenshot.png") ? "screenshot.png" : theme_json["screenshot"]
      ).compact

      Presentation::Theme.transaction do
        theme = Presentation::Theme.find_or_initialize_by(slug: slug)
        theme.version = header["Version"].presence || theme.version.presence || "0"
        theme.parent_slug = header["Template"].presence
        theme.theme_json = theme_json
        theme.active = false if theme.new_record?
        theme.save!

        load_templates(theme.slug, files)
        theme
      end
    end

    # The first path segment shared by the entries — the theme's own directory.
    def top_directory(files)
      files.keys.map { |name| name.split("/", 2).first }.uniq.compact.first
    end

    def read_json(files, name)
      raw = files[name]
      raise InvalidPackage, "the package is missing #{name}" if raw.nil?

      JSON.parse(raw)
    rescue JSON::ParserError
      raise InvalidPackage, "#{name} is not valid JSON"
    end

    # style.css's file header, class-wp-theme.php:53 — the fields the target has a use for.
    def read_header(css)
      header = css.to_s[0, 8192]
      %w[Theme\ Name Version Template].to_h do |field|
        [field, header[/^[ \t\/*#@]*#{Regexp.escape(field)}:(.*)$/, 1].to_s.strip]
      end
    end

    # get_block_templates() over the package: templates/*.html and parts/*.html become
    # Composition rows keyed by the theme's slug, which is how the render path (filtered
    # by theme_slug) will find them once the theme is activated.
    def load_templates(slug, files)
      Composition::Template.where(theme_slug: slug).delete_all
      files.each do |name, bytes|
        case name
        when %r{\A#{Regexp.escape(slug)}/templates/([^/]+)\.html\z}
          Composition::Template.create!(theme_slug: slug, kind: "template",
                                        slug: Regexp.last_match(1), area: nil,
                                        title: Regexp.last_match(1), content: bytes.to_s)
        when %r{\A#{Regexp.escape(slug)}/parts/([^/]+)\.html\z}
          Composition::Template.create!(theme_slug: slug, kind: "part",
                                        slug: Regexp.last_match(1), area: "uncategorized",
                                        title: Regexp.last_match(1), content: bytes.to_s)
        end
      end
    end
  end
end
