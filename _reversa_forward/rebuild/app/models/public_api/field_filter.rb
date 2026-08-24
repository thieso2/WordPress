# frozen_string_literal: true

module PublicApi
  # `_fields` — rest_filter_response_fields() and rest_is_field_included()
  # (wp-includes/rest-api.php:1543 / :1607).
  #
  # Two of Gutenberg's 24 preloaded paths carry it (`/wp/v2/users/1?_fields=id,name` and
  # the root request's `_fields=description,gmt_offset,home,…`), and api-fetch adds it to
  # most of its own reads, so it is part of the boot contract rather than a nicety.
  #
  # Three properties are observable and all three are reproduced:
  #   1. the ORDER is the response's own, not the request's — `_fields=id,title,link`
  #      answers `{id, link, title}`, because the filter INTERSECTS the prepared array;
  #   2. a name that is not a field is silently dropped (`_fields=id,bogus` -> `{id}`);
  #   3. `_links` is emitted ONLY when it is asked for (:2140, the `rest_is_field_included`
  #      guard around prepare_links) — which is why a `_fields` request is smaller than
  #      the same request without it, links included.
  # Dotted paths select INTO an object (`title.rendered`), and naming a parent selects
  # the whole subtree (`title` keeps `title.raw` too).
  module FieldFilter
    module_function

    # wp_parse_list() + array_map('trim'). Returns nil when `_fields` was absent or
    # empty, which every caller reads as "no filtering".
    def parse(raw)
      list = Array(raw).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?)
      list.empty? ? nil : list
    end

    # rest_is_field_included(), :1607. True when `field` is named outright, when a
    # PARENT of it is named (`title` includes `title.rendered`), or when a CHILD of it is
    # named (`title.rendered` includes `title`, so the parent survives to be pruned).
    def included?(field, fields)
      return true if fields.nil?

      field = field.to_s
      fields.any? do |candidate|
        candidate == field ||
          candidate.start_with?("#{field}.") ||
          field.start_with?("#{candidate}.")
      end
    end

    # _rest_array_intersect_key_recursive(), :1596, over the keyed hierarchy
    # rest_filter_response_fields() builds from the dotted names.
    def apply(data, fields)
      return data if fields.nil?

      intersect(data, keyed(fields))
    end

    # "Create nested array of accepted field hierarchy" (:1567-1587). `true` means "this
    # whole subtree"; a Hash means "these children of it". A child named after a parent
    # that is already `true` is skipped, so `_fields=title,title.raw` keeps all of title.
    def keyed(fields)
      root = {}
      fields.each do |field|
        parts = field.to_s.split(".")
        ref = root
        skip = false
        while parts.length > 1
          key = parts.shift
          if ref[key] == true
            skip = true
            break
          end
          ref[key] = {} unless ref[key].is_a?(Hash)
          ref = ref[key]
        end
        next if skip

        ref[parts.shift] = true
      end
      root
    end

    def intersect(data, keyed)
      return data unless data.is_a?(Hash)

      data.each_with_object({}) do |(key, value), out|
        name = key.to_s
        wanted = keyed[name]
        next if wanted.nil?

        out[key] = wanted == true ? value : intersect(value, wanted)
      end
    end
  end
end
