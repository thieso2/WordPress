# frozen_string_literal: true

module Styling
  # `wp_get_layout_definitions()`, wp-includes/block-supports/layout.php:284.
  # 
  # The function is a literal: it builds the array and returns it with no filter and no
  # branch (layout.php:284-456). Transcribed as a constant because that is what it is.
  # BR-MIGRATE-211's `body` root selector is what `get_layout_styles()` tests against
  # when it chooses between the two selector formats.
  module LayoutDefinitions
    ALL = {
        "default" => {
          "name" => "default",
          "slug" => "flow",
          "className" => "is-layout-flow",
          "baseStyles" => [
            {
              "selector" => " > .alignleft",
              "rules" => {
                "float" => "left",
                "margin-inline-start" => "0",
                "margin-inline-end" => "2em"
              }
            },
            {
              "selector" => " > .alignright",
              "rules" => {
                "float" => "right",
                "margin-inline-start" => "2em",
                "margin-inline-end" => "0"
              }
            },
            {
              "selector" => " > .aligncenter",
              "rules" => {
                "margin-left" => "auto !important",
                "margin-right" => "auto !important"
              }
            }
          ],
          "spacingStyles" => [
            {
              "selector" => " > :first-child",
              "rules" => {
                "margin-block-start" => "0"
              }
            },
            {
              "selector" => " > :last-child",
              "rules" => {
                "margin-block-end" => "0"
              }
            },
            {
              "selector" => " > *",
              "rules" => {
                "margin-block-start" => nil,
                "margin-block-end" => "0"
              }
            }
          ]
        },
        "constrained" => {
          "name" => "constrained",
          "slug" => "constrained",
          "className" => "is-layout-constrained",
          "baseStyles" => [
            {
              "selector" => " > .alignleft",
              "rules" => {
                "float" => "left",
                "margin-inline-start" => "0",
                "margin-inline-end" => "2em"
              }
            },
            {
              "selector" => " > .alignright",
              "rules" => {
                "float" => "right",
                "margin-inline-start" => "2em",
                "margin-inline-end" => "0"
              }
            },
            {
              "selector" => " > .aligncenter",
              "rules" => {
                "margin-left" => "auto !important",
                "margin-right" => "auto !important"
              }
            },
            {
              "selector" => " > :where(:not(.alignleft):not(.alignright):not(.alignfull))",
              "rules" => {
                "max-width" => "var(--wp--style--global--content-size)",
                "margin-left" => "auto !important",
                "margin-right" => "auto !important"
              }
            },
            {
              "selector" => " > .alignwide",
              "rules" => {
                "max-width" => "var(--wp--style--global--wide-size)"
              }
            }
          ],
          "spacingStyles" => [
            {
              "selector" => " > :first-child",
              "rules" => {
                "margin-block-start" => "0"
              }
            },
            {
              "selector" => " > :last-child",
              "rules" => {
                "margin-block-end" => "0"
              }
            },
            {
              "selector" => " > *",
              "rules" => {
                "margin-block-start" => nil,
                "margin-block-end" => "0"
              }
            }
          ]
        },
        "flex" => {
          "name" => "flex",
          "slug" => "flex",
          "className" => "is-layout-flex",
          "displayMode" => "flex",
          "baseStyles" => [
            {
              "selector" => "",
              "rules" => {
                "flex-wrap" => "wrap",
                "align-items" => "center"
              }
            },
            {
              "selector" => " > :is(*, div)",
              "rules" => {
                "margin" => "0"
              }
            }
          ],
          "spacingStyles" => [
            {
              "selector" => "",
              "rules" => {
                "gap" => nil
              }
            }
          ]
        },
        "grid" => {
          "name" => "grid",
          "slug" => "grid",
          "className" => "is-layout-grid",
          "displayMode" => "grid",
          "baseStyles" => [
            {
              "selector" => " > :is(*, div)",
              "rules" => {
                "margin" => "0"
              }
            }
          ],
          "spacingStyles" => [
            {
              "selector" => "",
              "rules" => {
                "gap" => nil
              }
            }
          ]
        }
      }.freeze
  end
end
