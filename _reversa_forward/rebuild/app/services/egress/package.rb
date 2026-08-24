# frozen_string_literal: true

require "rubygems/package"
require "zlib"

module Egress
  # BR-MIGRATE-346 (BR-UPD-04) with BR-MIGRATE-338/340/341 (BR-FS-07/09/10):
  # a package fetched from a remote directory is signature-verified AFTER download and
  # BEFORE anything is written to disk.
  #
  # ⚠️ CONTINGENT (parity_specs.md, ambiguity P-4): these four rules survive only because
  # DEV-011 kept `console.theme-install`. Drop remote theme installation and all four go
  # VOID together, and this file with them.
  #
  # ⚠️ SECOND-ORDER DEVIATION, same direction as BR-HTTP-01 and reported with it. The
  # legacy's *unfiltered default* on this path is not what these rules describe:
  #   * WP_Upgrader::run() calls download_package($package, false, ...) --
  #     `$check_signatures = false` (class-wp-upgrader.php:849), so by default nothing is
  #     verified at all; and
  #   * `wp_signature_softfail` defaults to TRUE (file.php:1349), so even when a package
  #     IS verified and fails, download_url() keeps the file and WP_Upgrader "pretends
  #     this error didn't happen" (class-wp-upgrader.php:874); and
  #   * `wp_signature_hosts` limits verification to wordpress.org hosts (file.php:1287).
  # BC-14 inverts all three for the same reason it inverts BR-HTTP-01: verification is
  # unconditional, applies to every host, and a failure is fatal to the install.
  class Package
    # The legacy stores signatures in this header, one per line, or alongside the package
    # at `<package-url>.sig` (file.php:1293-1309).
    SIGNATURE_HEADER = "x-content-signature"
    SIGNATURE_SUFFIX = ".sig"
    SIGNABLE_EXTENSIONS = %w[.zip .tar.gz].freeze

    # Raised instead of returning a WP_Error. Carries the legacy's error code and its
    # message verbatim.
    class Rejected < StandardError
      attr_reader :error_code, :verification

      def initialize(verification)
        @verification = verification
        @error_code = verification.error_code
        super(verification.message)
      end
    end

    class PathEscape < StandardError; end

    # The default destination: a real directory. Kept as a collaborator rather than a
    # path so a caller -- including the parity suite -- can observe when the first byte
    # is written, which is how "before any file is extracted" is checkable from outside.
    #
    # It also carries the invariant parity_specs.md kept from the 8 deviated filesystem
    # rules: "the application never writes outside its declared storage paths."
    class DirectoryDestination
      attr_reader :root

      def initialize(root)
        @root = File.expand_path(root)
      end

      def write(name, bytes)
        target = File.expand_path(File.join(@root, name))
        raise PathEscape, name unless target == @root || target.start_with?("#{@root}#{File::SEPARATOR}")

        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, bytes)
        target
      end
    end

    attr_reader :url, :content, :signatures, :filename

    # The download goes through Egress::Client, so the package URL is subject to the same
    # single door as everything else -- including the sibling `.sig` fetch, which in the
    # legacy is the one call on this path that already used wp_safe_remote_get().
    def self.download(url, client:, trusted_keys: TrustedKeys.default)
      response = client.get(url)
      signatures = signatures_from(response) || signatures_alongside(url, client: client)
      new(url: url, content: response.body, signatures: signatures, trusted_keys: trusted_keys)
    end

    def self.signatures_from(response)
      header = response.header(SIGNATURE_HEADER)
      return nil if header.nil? || header.to_s.empty?

      Array(header).flat_map { |value| value.to_s.split("\n") }.map(&:strip).reject(&:empty?)
    end

    def self.signatures_alongside(url, client:)
      path = (URI.parse(url).path.to_s rescue "")
      return [] unless SIGNABLE_EXTENSIONS.any? { |ext| path.end_with?(ext) }

      response = client.get(url + SIGNATURE_SUFFIX)
      return [] unless response.success?

      response.body.to_s.split("\n").map(&:strip).reject(&:empty?)
    rescue UrlPolicy::Refused
      []
    end

    def initialize(url:, content:, signatures: [], trusted_keys: TrustedKeys.default, filename: nil)
      @url = url
      @content = content
      @signatures = Array(signatures)
      @trusted_keys = trusted_keys
      @filename = filename || File.basename((URI.parse(url.to_s).path.to_s rescue "")).presence || "package"
    end

    def verification
      @verification ||= SignatureVerifier.new(trusted_keys: @trusted_keys)
                                         .verify(content: @content, signatures: @signatures,
                                                 filename_for_errors: @filename)
    end

    def verified? = verification.verified?

    # Verify, then extract. Never the other way round, and never extract at all unless
    # verification returned true: `into` is not touched before `verification` has an
    # answer, which is what the parity scenario observes.
    def install!(into:)
      raise Rejected, verification unless verification.verified?

      extract(into)
    end

    private

    def extract(destination)
      written = []
      Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(@content))).each do |entry|
        next unless entry.file?

        written << destination.write(entry.full_name, entry.read.to_s)
      end
      written
    end
  end
end
