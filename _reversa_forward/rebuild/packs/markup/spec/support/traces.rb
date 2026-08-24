# frozen_string_literal: true

require "base64"

# Canonical token traces used by the differential specs.
#
# `MarkupTraces.trace` produces exactly the structure that spec/support/dump_tokens.php produces
# from the legacy PHP, so the two can be compared field for field.
module MarkupTraces
  GUARD = 5000

  def self.trace(html)
    tree = tree_trace(html)
    mutation = mutation_trace(html)
    full = full_trace(html)
    {
      "tags" => tag_trace(html),
      "paused" => paused?(html),
      "tree" => tree[:tree],
      "error" => tree[:error],
      "message" => tree[:message],
      "mutated" => mutation[:mutated],
      "prefixes" => mutation[:prefixes],
      "full" => full[:tree],
      "full_error" => full[:error],
      "full_message" => full[:message],
      "seek" => seek_trace(html)
    }
  end

  # A bookmark set on the second tag, then returned to after the whole document has been
  # scanned. Backwards seeking has to unwind and replay tree construction, so this
  # exercises BR-MIGRATE-221 inside BR-MIGRATE-223 for both a fragment (which restarts at
  # its context element) and a whole document (which restarts at byte zero).
  def self.seek_trace(html)
    %w[fragment full].each_with_object({}) do |kind, result|
      processor = kind == "fragment" ? Markup::Processor.create_fragment(html)
                                     : Markup::Processor.create_full_parser(html)
      if processor.nil?
        result[kind] = "could-not-create"
        next
      end

      marked = nil
      count = 0
      guard = 0
      while processor.next_tag && (guard += 1) < 2000
        # Bookmark the second tag that actually appears in the text; virtual nodes cannot
        # carry a bookmark.
        next unless marked.nil? && processor.set_bookmark("probe")

        count += 1
        next unless count == 2

        processor.set_bookmark("target")
        marked = processor.get_breadcrumbs.dup
      end

      if marked.nil? || !processor.has_bookmark?("target")
        result[kind] = "no-bookmark"
        next
      end

      result[kind] = {
        "ok" => processor.seek("target"),
        "before" => marked,
        "after" => processor.get_breadcrumbs.dup,
        "tag" => processor.get_tag,
        "error" => processor.get_last_error
      }
    end
  end

  # Whole-document parsing, which reaches the insertion modes a BODY fragment never
  # visits: initial, before html, before head, in head, after head, frameset, after body.
  # BR-MIGRATE-223 / BR-MIGRATE-224 (no context element: the document is the context).
  def self.full_trace(html)
    processor = Markup::Processor.create_full_parser(html)
    return { tree: [], error: "could-not-create", message: nil } if processor.nil?

    tree = []
    guard = 0
    while processor.next_token && (guard += 1) < GUARD
      tree << {
        "name" => processor.get_token_name,
        "type" => processor.get_token_type,
        "closer" => processor.tag_closer?,
        "crumbs" => processor.get_breadcrumbs.dup
      }
    end

    { tree: tree, error: processor.get_last_error,
      message: processor.get_unsupported_exception&.message }
  end

  # Exercises BR-MIGRATE-220 (byte-level edits applied on get_updated_html),
  # BR-MIGRATE-221 (set_bookmark/seek) and BR-MIGRATE-222 (prefix discovery, including
  # attributes that are enqueued but not yet written).
  def self.mutation_trace(html)
    processor = Markup::TagProcessor.new(html)
    i = 0
    prefixes = []
    guard = 0
    while processor.next_tag && (guard += 1) < 2000
      i += 1
      processor.set_bookmark("first") if i == 1
      processor.set_attribute("data-n", i.to_s)
      processor.add_class("c#{i % 3}")
      if (i % 2).zero?
        processor.remove_class("c1")
        processor.remove_attribute("id")
      end
      prefixes << processor.get_attribute_names_with_prefix("data-")
    end

    if processor.has_bookmark?("first") && processor.seek("first")
      processor.set_attribute("data-seek", "yes")
      processor.remove_attribute("data-n")
    end

    { mutated: Base64.strict_encode64(processor.get_updated_html), prefixes: prefixes }
  end

  def self.tag_trace(html)
    processor = Markup::TagProcessor.new(html)
    trace = []
    guard = 0
    while processor.next_token && (guard += 1) < GUARD
      names = processor.get_attribute_names_with_prefix("")
      attrs = []
      names&.each do |name|
        value = processor.get_attribute(name)
        attrs << [name, value == true ? true : Base64.strict_encode64(value)]
      end

      doctype = processor.get_doctype_info
      full_comment = processor.get_full_comment_text

      trace << {
        "type" => processor.get_token_type,
        "name" => processor.get_token_name,
        "closer" => processor.tag_closer?,
        "self" => processor.has_self_closing_flag?,
        "comment" => processor.get_comment_type,
        "text" => Base64.strict_encode64(processor.get_modifiable_text),
        "attrs" => attrs,
        "ns" => processor.get_namespace,
        "classes" => processor.class_list.to_a,
        "has_test" => processor.has_class?("test"),
        "has_a" => processor.has_class?("a"),
        "full_comment" => full_comment.nil? ? nil : Base64.strict_encode64(full_comment),
        "doctype" => doctype.nil? ? nil : [doctype.name, doctype.public_identifier,
                                           doctype.system_identifier,
                                           doctype.indicated_compatibility_mode]
      }
    end
    trace
  end

  def self.paused?(html)
    processor = Markup::TagProcessor.new(html)
    guard = 0
    nil while processor.next_token && (guard += 1) < GUARD
    processor.paused_at_incomplete_token?
  end

  def self.tree_trace(html)
    processor = Markup::Processor.create_fragment(html)
    return { tree: [], error: "could-not-create", message: nil } if processor.nil?

    tree = []
    guard = 0
    while processor.next_token && (guard += 1) < GUARD
      tree << {
        "name" => processor.get_token_name,
        "type" => processor.get_token_type,
        "closer" => processor.tag_closer?,
        "crumbs" => processor.get_breadcrumbs.dup,
        "depth" => processor.get_current_depth
      }
    end

    { tree: tree, error: processor.get_last_error,
      message: processor.get_unsupported_exception&.message }
  end
end
