# frozen_string_literal: true

require 'json'

module Styling
  # BR-MIGRATE-206…210 — port of WP_Theme_JSON_Resolver,
  # wp-includes/class-wp-theme-json-resolver.php:21.
  #
  # Owns the four-origin cascade. paradigm_decision.md option 1: the
  # `wp_theme_json_data_default|blocks|theme|user` filters do not exist, so each
  # origin's data is exactly what its source declares. topology_decision.md
  # option 3: the origin data and the user-styles store are injected rather than
  # read from globals, and the per-request memo lives on the instance instead of
  # a class static.
  class ThemeJsonResolver
    # @param store [GlobalStylesStore]
    # @param stylesheet [String] the active theme's stylesheet slug
    # @param core_data [Hash] WordPress's own theme.json ('default' origin)
    # @param block_data [Hash] data contributed by block types ('blocks' origin)
    # @param theme_data [Hash] the active theme's theme.json ('theme' origin)
    # @param enforce_protected_properties [Boolean] BR-MIGRATE-210
    def initialize(store:, stylesheet:, core_data: {}, block_data: {}, theme_data: {},
                   enforce_protected_properties: true)
      @store = store
      @stylesheet = stylesheet
      @core_data = core_data
      @block_data = block_data
      @theme_data = theme_data
      @enforce_protected_properties = enforce_protected_properties
      @user_global_styles_id = nil
      @user = nil
    end

    # class-wp-theme-json-resolver.php:120.
    #
    # @return [ThemeJson] the 'default' origin
    def core_data
      ThemeJson.new(@core_data, 'default')
    end

    # class-wp-theme-json-resolver.php:392.
    #
    # @return [ThemeJson] the 'blocks' origin
    def block_data
      ThemeJson.new(@block_data, 'blocks')
    end

    # class-wp-theme-json-resolver.php:392 — the 'blocks' origin's DATA, derived
    # from what each block type declares. Two contributions, and only two:
    # `supports.__experimentalStyle`, and a `null` placeholder for a block that
    # names a default `blockGap` (:414 — the real value is decided at render).
    #
    # ⚠️ topology_decision.md option 3: the legacy reads the block registry
    # singleton. Here the definitions are an argument. AD-01: the
    # `wp_theme_json_data_blocks` filter (:423) is gone.
    #
    # @param block_definitions [Hash{String=>Hash}] block.json data per block name
    # @return [Hash] a theme.json document for the 'blocks' origin
    def self.block_data_from_definitions(block_definitions)
      config = { 'version' => ThemeJson::LATEST_SCHEMA }
      (block_definitions || {}).each do |block_name, block_type|
        supports = (block_type || {})['supports']
        next unless supports.is_a?(Hash)

        if supports.key?('__experimentalStyle')
          PhpCompat.array_set(config, ['styles', 'blocks', block_name],
                              remove_json_comments(supports['__experimentalStyle']))
        end

        default_gap = PhpCompat.array_get(supports, %w[spacing blockGap __experimentalDefault], nil)
        next if default_gap.nil?
        next unless PhpCompat.array_get(config, ['styles', 'blocks', block_name, 'spacing', 'blockGap'], :absent) == :absent

        PhpCompat.array_set(config, ['styles', 'blocks', block_name, 'spacing', 'blockGap'], nil)
      end
      config
    end

    # class-wp-theme-json-resolver.php:449 — block.json uses `"//"` for comments.
    #
    # @param value [Object]
    # @return [Object]
    def self.remove_json_comments(value)
      return value unless value.is_a?(Hash)

      value.reject { |k, _| k == '//' }.transform_values { |v| remove_json_comments(v) }
    end

    # class-wp-theme-json-resolver.php:330.
    #
    # @return [ThemeJson] the 'theme' origin
    def theme_data
      ThemeJson.new(@theme_data, 'theme')
    end

    # BR-MIGRATE-208/210 — class-wp-theme-json-resolver.php:543.
    # Reads the theme's single `wp_global_styles` record. The
    # `isGlobalStylesUserThemeJSON` flag must be present and truthy: without it
    # the content was never escaped and is not safe to trust.
    #
    # @return [ThemeJson] the 'custom' origin
    def user_data
      return @user unless @user.nil?

      config = {}
      record = @store.find_for_theme(@stylesheet)

      if record && record.key?('content')
        decoded = begin
          JSON.parse(record['content'].to_s)
        rescue JSON::ParserError
          nil
        end

        if decoded.is_a?(Hash) && decoded['isGlobalStylesUserThemeJSON']
          decoded = decoded.dup
          decoded.delete('isGlobalStylesUserThemeJSON')
          config = decoded
        end
      end

      # BR-MIGRATE-210: PROTECTED_PROPERTIES cannot be overridden by the user
      # origin. See README — 7.2-alpha declares the constant but no longer
      # applies it, so this is enforcement the target adds back.
      config = ThemeJson.remove_protected_properties(config) if @enforce_protected_properties

      @user = ThemeJson.new(config, 'custom')
    end

    # BR-MIGRATE-208, BR-MIGRATE-209 — class-wp-theme-json-resolver.php:678.
    # The record is created on first access, and the id is memoized for the
    # request (here: for the lifetime of this resolver instance, which the
    # application scopes to the request).
    #
    # @return [Object, nil] the record id
    def user_global_styles_id
      return @user_global_styles_id unless @user_global_styles_id.nil?

      record = @store.find_for_theme(@stylesheet) || @store.create_for_theme(@stylesheet)
      @user_global_styles_id = record['id'] if record.is_a?(Hash) && record.key?('id')
      @user_global_styles_id
    end

    # BR-MIGRATE-206, BR-MIGRATE-207 — class-wp-theme-json-resolver.php:644.
    # The four origins merge strictly in the order default, blocks, theme,
    # custom; naming an origin stops the cascade there, which is how
    # "what would the theme alone produce?" is asked.
    #
    # @param origin [String] 'default', 'blocks', 'theme' or 'custom'
    # @return [ThemeJson]
    def merged_data(origin = 'custom')
      result = ThemeJson.new
      result.merge(core_data)
      return result if origin == 'default'

      result.merge(block_data)
      return result if origin == 'blocks'

      result.merge(theme_data)
      return result if origin == 'theme'

      result.merge(user_data)
      result
    end
  end
end
