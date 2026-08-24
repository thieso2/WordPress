# frozen_string_literal: true

module Styling
  # BR-MIGRATE-219 — verbatim transcription of
  # WP_Style_Engine::BLOCK_STYLE_DEFINITIONS_METADATA,
  # wp-includes/style-engine/class-wp-style-engine.php:54.
  #
  # For every definition:
  #   'classnames'    => class name => `true` (always) or the preset property to match
  #   'css_vars'      => preset property => CSS custom-property pattern
  #   'property_keys' => 'default' / 'individual' CSS property names
  #   'path'          => path to the value inside the block style object
  #   'value_func'    => symbol naming a StyleEngine value parser
  module BlockStyleDefinitions
    METADATA = {
      'background' => {
        'backgroundImage' => {
          'property_keys' => { 'default' => 'background-image' },
          'value_func' => :url_or_value_css_declaration,
          'path' => %w[background backgroundImage]
        },
        'backgroundPosition' => {
          'property_keys' => { 'default' => 'background-position' },
          'path' => %w[background backgroundPosition]
        },
        'backgroundRepeat' => {
          'property_keys' => { 'default' => 'background-repeat' },
          'path' => %w[background backgroundRepeat]
        },
        'backgroundSize' => {
          'property_keys' => { 'default' => 'background-size' },
          'path' => %w[background backgroundSize]
        },
        'backgroundAttachment' => {
          'property_keys' => { 'default' => 'background-attachment' },
          'path' => %w[background backgroundAttachment]
        },
        'gradient' => {
          'property_keys' => { 'default' => 'background-image' },
          'css_vars' => { 'gradient' => '--wp--preset--gradient--$slug' },
          'path' => %w[background gradient],
          'classnames' => { 'has-background' => true }
        }
      },
      'color' => {
        'text' => {
          'property_keys' => { 'default' => 'color' },
          'path' => %w[color text],
          'css_vars' => { 'color' => '--wp--preset--color--$slug' },
          'classnames' => { 'has-text-color' => true, 'has-$slug-color' => 'color' }
        },
        'background' => {
          'property_keys' => { 'default' => 'background-color' },
          'path' => %w[color background],
          'css_vars' => { 'color' => '--wp--preset--color--$slug' },
          'classnames' => { 'has-background' => true, 'has-$slug-background-color' => 'color' }
        },
        'gradient' => {
          'property_keys' => { 'default' => 'background' },
          'path' => %w[color gradient],
          'css_vars' => { 'gradient' => '--wp--preset--gradient--$slug' },
          'classnames' => { 'has-background' => true, 'has-$slug-gradient-background' => 'gradient' }
        }
      },
      'border' => {
        'color' => {
          'property_keys' => { 'default' => 'border-color', 'individual' => 'border-%s-color' },
          'path' => %w[border color],
          'classnames' => { 'has-border-color' => true, 'has-$slug-border-color' => 'color' }
        },
        'radius' => {
          'property_keys' => { 'default' => 'border-radius', 'individual' => 'border-%s-radius' },
          'path' => %w[border radius],
          'css_vars' => { 'border-radius' => '--wp--preset--border-radius--$slug' }
        },
        'style' => {
          'property_keys' => { 'default' => 'border-style', 'individual' => 'border-%s-style' },
          'path' => %w[border style]
        },
        'width' => {
          'property_keys' => { 'default' => 'border-width', 'individual' => 'border-%s-width' },
          'path' => %w[border width]
        },
        'top' => {
          'value_func' => :individual_property_css_declarations,
          'path' => %w[border top],
          'css_vars' => { 'color' => '--wp--preset--color--$slug' }
        },
        'right' => {
          'value_func' => :individual_property_css_declarations,
          'path' => %w[border right],
          'css_vars' => { 'color' => '--wp--preset--color--$slug' }
        },
        'bottom' => {
          'value_func' => :individual_property_css_declarations,
          'path' => %w[border bottom],
          'css_vars' => { 'color' => '--wp--preset--color--$slug' }
        },
        'left' => {
          'value_func' => :individual_property_css_declarations,
          'path' => %w[border left],
          'css_vars' => { 'color' => '--wp--preset--color--$slug' }
        }
      },
      'shadow' => {
        'shadow' => {
          'property_keys' => { 'default' => 'box-shadow' },
          'path' => %w[shadow],
          'css_vars' => { 'shadow' => '--wp--preset--shadow--$slug' }
        }
      },
      'dimensions' => {
        'aspectRatio' => {
          'property_keys' => { 'default' => 'aspect-ratio' },
          'path' => %w[dimensions aspectRatio],
          'classnames' => { 'has-aspect-ratio' => true }
        },
        'height' => {
          'property_keys' => { 'default' => 'height' },
          'path' => %w[dimensions height],
          'css_vars' => { 'dimension' => '--wp--preset--dimension--$slug' }
        },
        'minHeight' => {
          'property_keys' => { 'default' => 'min-height' },
          'path' => %w[dimensions minHeight],
          'css_vars' => { 'dimension' => '--wp--preset--dimension--$slug' }
        },
        'minWidth' => {
          'property_keys' => { 'default' => 'min-width' },
          'path' => %w[dimensions minWidth],
          'css_vars' => { 'dimension' => '--wp--preset--dimension--$slug' }
        },
        'objectFit' => {
          'property_keys' => { 'default' => 'object-fit' },
          'path' => %w[dimensions objectFit]
        },
        'width' => {
          'property_keys' => { 'default' => 'width' },
          'path' => %w[dimensions width],
          'css_vars' => { 'dimension' => '--wp--preset--dimension--$slug' }
        }
      },
      'spacing' => {
        'padding' => {
          'property_keys' => { 'default' => 'padding', 'individual' => 'padding-%s' },
          'path' => %w[spacing padding],
          'css_vars' => { 'spacing' => '--wp--preset--spacing--$slug' }
        },
        'margin' => {
          'property_keys' => { 'default' => 'margin', 'individual' => 'margin-%s' },
          'path' => %w[spacing margin],
          'css_vars' => { 'spacing' => '--wp--preset--spacing--$slug' }
        }
      },
      'typography' => {
        'fontSize' => {
          'property_keys' => { 'default' => 'font-size' },
          'path' => %w[typography fontSize],
          'css_vars' => { 'font-size' => '--wp--preset--font-size--$slug' },
          'classnames' => { 'has-$slug-font-size' => 'font-size' }
        },
        'fontFamily' => {
          'property_keys' => { 'default' => 'font-family' },
          'css_vars' => { 'font-family' => '--wp--preset--font-family--$slug' },
          'path' => %w[typography fontFamily],
          'classnames' => { 'has-$slug-font-family' => 'font-family' }
        },
        'fontStyle' => {
          'property_keys' => { 'default' => 'font-style' },
          'path' => %w[typography fontStyle]
        },
        'fontWeight' => {
          'property_keys' => { 'default' => 'font-weight' },
          'path' => %w[typography fontWeight]
        },
        'lineHeight' => {
          'property_keys' => { 'default' => 'line-height' },
          'path' => %w[typography lineHeight]
        },
        'textColumns' => {
          'property_keys' => { 'default' => 'column-count' },
          'path' => %w[typography textColumns]
        },
        'textDecoration' => {
          'property_keys' => { 'default' => 'text-decoration' },
          'path' => %w[typography textDecoration]
        },
        'textIndent' => {
          'property_keys' => { 'default' => 'text-indent' },
          'path' => %w[typography textIndent]
        },
        'textTransform' => {
          'property_keys' => { 'default' => 'text-transform' },
          'path' => %w[typography textTransform]
        },
        'letterSpacing' => {
          'property_keys' => { 'default' => 'letter-spacing' },
          'path' => %w[typography letterSpacing]
        },
        'writingMode' => {
          'property_keys' => { 'default' => 'writing-mode' },
          'path' => %w[typography writingMode]
        }
      }
    }.freeze
  end
end
