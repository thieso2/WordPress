# frozen_string_literal: true

require "digest"

module PublicApi
  # get_avatar_url() / rest_get_avatar_urls(), wp-includes/link-template.php. WordPress
  # 6.x hashes the email with SHA-256 (the historic MD5 was retired), lower-cased and
  # trimmed; the defaults are d=mm (mystery-person) and r=g. Sizes 24/48/96 are
  # rest_get_avatar_sizes()'s set.
  module Avatar
    SIZES = [24, 48, 96].freeze

    module_function

    def urls(email)
      hash = Digest::SHA256.hexdigest(email.to_s.strip.downcase)
      SIZES.to_h { |s| [s.to_s, "https://secure.gravatar.com/avatar/#{hash}?s=#{s}&d=mm&r=g"] }
    end
  end
end
