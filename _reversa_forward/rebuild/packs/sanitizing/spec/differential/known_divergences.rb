# frozen_string_literal: true

module Sanitizing
  # The catalogue of accepted differences between this port and the PHP oracle.
  #
  # handoff.md: "A known, documented divergence is acceptable output from this
  # task; an undocumented one is not." Every entry here has a matching section in
  # README.md, "Known divergences", with the reason it exists and what it costs.
  #
  # These predicates are deliberately narrow. A predicate that swallowed a whole
  # subject would turn the harness into decoration.
  module KnownDivergences
    # The kses entry points, which are the ones the legacy runs the `pre_kses`
    # filter chain in front of.
    KSES_SUBJECTS = %w[
      wp_kses_post wp_kses_data wp_kses_strip wp_kses_user_description
    ].freeze

    # An HTML comment token as wp_kses_split() tokenizes it.
    COMMENT_TOKEN = /<!--.*?(?:-->|\z)/m

    RULES = {
      'D-1 block-attribute pre-filter' => <<~WHY
        wp-includes/default-filters.php:308 registers wp_pre_kses_block_attributes()
        on `pre_kses`. It calls filter_block_content(), i.e. the block parser, which
        lives outside this pack (topology_decision.md option 3: zero dependencies).
        The block parser rewrites HTML comment tokens before kses ever sees them,
        because `<!-- wp:… -->` is the block delimiter syntax. The port therefore
        diverges on inputs whose *comment tokens* the block parser would rewrite,
        and only there: `<!------>` is emptied by PHP and preserved as `<!---->` here.
      WHY
    }.freeze

    module_function

    def known?(subject, input, php, ruby)
      block_comment_rewrite?(subject, input, php, ruby)
    end

    # D-1. Accept only when the entire difference lives inside comment tokens.
    def block_comment_rewrite?(subject, input, php, ruby)
      return false unless KSES_SUBJECTS.include?(subject)
      return false unless Bytes.binary(input).include?('<!--'.b)

      without_comments(php) == without_comments(ruby)
    end

    def without_comments(text)
      Bytes.binary(text).gsub(COMMENT_TOKEN, ''.b)
    end
  end
end
