# frozen_string_literal: true

module Library
  # The subsize geometry of AGG-Asset, transcribed from wp-includes/media.php
  # (`image_resize_dimensions()` / `wp_constrain_dimensions()`).
  #
  # AD-01: the legacy runs this through three filters — `image_resize_dimensions`,
  # `wp_constrain_dimensions` and `wp_image_resize_identical_dimensions`. Every one of
  # them is discarded; what is implemented here is the pre-filter default, and it is
  # the permanent, only behaviour.
  #
  # Pure arithmetic on purpose. Deciding WHICH variants exist and how large they are is
  # a domain rule (BR-MIGRATE-079..082, 088); painting the pixels is infrastructure.
  module Geometry
    # BR-MIGRATE-082: aspect-ratio matching tolerates a 1-pixel difference, because
    # integer rounding during resize makes exact matches rare.
    FUZZ = 1

    # One computed subsize. Cropping carries a source rectangle; scaling does not.
    Rect = Struct.new(:width, :height, :source_x, :source_y, :source_width, :source_height,
                      keyword_init: true)

    module_function

    # wp_constrain_dimensions(). A zero max on either axis means "unconstrained there"
    # — which is how the registered `medium_large` size (768x0) is expressed.
    def constrain(current_w, current_h, max_w, max_h)
      max_w = max_w.to_i
      max_h = max_h.to_i
      return [current_w, current_h] if max_w.zero? && max_h.zero?

      width_ratio  = 1.0
      height_ratio = 1.0
      did_width    = false
      did_height   = false

      if max_w.positive? && current_w.positive? && current_w > max_w
        width_ratio = max_w.fdiv(current_w)
        did_width   = true
      end

      if max_h.positive? && current_h.positive? && current_h > max_h
        height_ratio = max_h.fdiv(current_h)
        did_height   = true
      end

      smaller_ratio = [width_ratio, height_ratio].min
      larger_ratio  = [width_ratio, height_ratio].max

      ratio =
        if round_half_up(current_w * larger_ratio) > max_w ||
           round_half_up(current_h * larger_ratio) > max_h
          # The larger ratio would overflow the bounding box.
          smaller_ratio
        else
          larger_ratio
        end

      # Very small dimensions may round to 0; 1 is the minimum.
      w = [1, round_half_up(current_w * ratio)].max
      h = [1, round_half_up(current_h * ratio)].max

      # A result one pixel shy of the max is bumped up, so that constraining the result
      # of a constraint yields the same result again.
      w = max_w if did_width && w == max_w - 1
      h = max_h if did_height && h == max_h - 1

      [w, h]
    end

    # image_resize_dimensions(). Returns nil where the legacy returns false — i.e.
    # "generate no file for this size, use the original".
    #
    # BR-MIGRATE-079: WordPress never upscales.
    # BR-MIGRATE-080: cropping uses max() of the two ratios — a cover fit, not a letterbox.
    # BR-MIGRATE-081: an invalid crop position falls back to ['center', 'center'].
    # BR-MIGRATE-082: a result within one pixel of the original is not generated.
    def resize(orig_w, orig_h, dest_w, dest_h, crop = false)
      orig_w = orig_w.to_i
      orig_h = orig_h.to_i
      dest_w = dest_w.to_i
      dest_h = dest_h.to_i

      return nil if orig_w <= 0 || orig_h <= 0
      return nil if dest_w <= 0 && dest_h <= 0

      # BR-MIGRATE-079 — stop if the destination is larger than the original.
      if dest_h.zero?
        return nil if orig_w < dest_w
      elsif dest_w.zero?
        return nil if orig_h < dest_h
      elsif orig_w < dest_w && orig_h < dest_h
        return nil
      end

      rect = crop ? crop_rect(orig_w, orig_h, dest_w, dest_h, crop) : scale_rect(orig_w, orig_h, dest_w, dest_h)

      # BR-MIGRATE-082 — virtually the same dimensions as the original: no subsize.
      return nil if fuzzy_match?(rect.width, orig_w) && fuzzy_match?(rect.height, orig_h)

      rect
    end

    def fuzzy_match?(expected, actual, precision = FUZZ)
      (expected - actual).abs <= precision
    end

    # PHP's round() is half away from zero; Ruby's Float#round agrees for the
    # non-negative values that occur here.
    def round_half_up(value) = value.round.to_i

    # ── internals ──────────────────────────────────────────────────────────────

    def scale_rect(orig_w, orig_h, dest_w, dest_h)
      new_w, new_h = constrain(orig_w, orig_h, dest_w, dest_h)
      Rect.new(width: new_w, height: new_h, source_x: 0, source_y: 0,
               source_width: orig_w, source_height: orig_h)
    end

    def crop_rect(orig_w, orig_h, dest_w, dest_h, crop)
      aspect_ratio = orig_w.fdiv(orig_h)
      new_w = [dest_w, orig_w].min
      new_h = [dest_h, orig_h].min

      new_w = round_half_up(new_h * aspect_ratio) if new_w.zero?
      new_h = round_half_up(new_w / aspect_ratio) if new_h.zero?

      # BR-MIGRATE-080 — max(), so the source rectangle covers the target box.
      size_ratio = [new_w.fdiv(orig_w), new_h.fdiv(orig_h)].max
      crop_w = round_half_up(new_w / size_ratio)
      crop_h = round_half_up(new_h / size_ratio)

      x, y = crop_position(crop)

      s_x =
        case x
        when "left"  then 0
        when "right" then orig_w - crop_w
        else ((orig_w - crop_w) / 2.0).floor
        end

      s_y =
        case y
        when "top"    then 0
        when "bottom" then orig_h - crop_h
        else ((orig_h - crop_h) / 2.0).floor
        end

      Rect.new(width: new_w, height: new_h, source_x: s_x.to_i, source_y: s_y.to_i,
               source_width: crop_w, source_height: crop_h)
    end

    # BR-MIGRATE-081 — anything that is not a two-element pair is center/center.
    def crop_position(crop)
      return %w[center center] unless crop.is_a?(Array) && crop.length == 2

      crop.map(&:to_s)
    end
  end
end
