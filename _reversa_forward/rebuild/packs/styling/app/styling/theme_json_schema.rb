# frozen_string_literal: true

module Styling
  # BR-MIGRATE-215 — port of WP_Theme_JSON_Schema,
  # wp-includes/class-wp-theme-json-schema.php:21.
  #
  # Older theme.json documents are migrated forward to the latest schema at
  # load time (ThemeJson.new calls this first), so nothing downstream ever
  # sees a v1 or v2 tree.
  module ThemeJsonSchema
    module_function

    # class-wp-theme-json-schema.php:27.
    V1_TO_V2_RENAMED_PATHS = {
      'border.customRadius' => 'border.radius',
      'spacing.customMargin' => 'spacing.margin',
      'spacing.customPadding' => 'spacing.padding',
      'typography.customLineHeight' => 'typography.lineHeight'
    }.freeze

    # BR-MIGRATE-215 — class-wp-theme-json-schema.php:45.
    # A document with no `version` is discarded entirely and replaced with a
    # bare latest-schema document — verbatim legacy behaviour.
    #
    # @param theme_json [Hash]
    # @param origin [String] 'blocks', 'default', 'theme' or 'custom'
    # @return [Hash] the document at ThemeJson::LATEST_SCHEMA
    def migrate(theme_json, origin = 'theme')
      theme_json = { 'version' => ThemeJson::LATEST_SCHEMA } unless theme_json.is_a?(Hash) &&
                                                                    theme_json.key?('version') &&
                                                                    !theme_json['version'].nil?

      version = theme_json['version']
      version = version.to_i if version.is_a?(String) && PhpCompat.php_numeric?(version)

      case version
      when 1
        # Deliberate fall through: once migrated to v2, also migrate to v3.
        theme_json = migrate_v1_to_v2(theme_json)
        theme_json = migrate_v2_to_v3(theme_json, origin)
      when 2
        theme_json = migrate_v2_to_v3(theme_json, origin)
      end

      theme_json
    end

    # BR-MIGRATE-215 — class-wp-theme-json-schema.php:78.
    #
    # @param old [Hash]
    # @return [Hash]
    def migrate_v1_to_v2(old)
      new = PhpCompat.deep_dup(old)
      new['settings'] = rename_paths(old['settings'], V1_TO_V2_RENAMED_PATHS) if old.key?('settings')
      new['version'] = 2
      new
    end

    # BR-MIGRATE-215 — class-wp-theme-json-schema.php:108.
    #
    # @param old [Hash]
    # @param origin [String]
    # @return [Hash]
    def migrate_v2_to_v3(old, origin)
      new = PhpCompat.deep_dup(old)
      new['version'] = 3

      # Remaining changes do not apply to the custom origin; it takes on the
      # value of the theme origin.
      return new if origin == 'custom'

      unless PhpCompat.array_get(old, %w[settings typography fontSizes]).nil?
        PhpCompat.array_set(new, %w[settings typography defaultFontSizes], false)
      end

      if !PhpCompat.array_get(old, %w[settings spacing spacingSizes]).nil? ||
         !PhpCompat.array_get(old, %w[settings spacing spacingScale]).nil?
        PhpCompat.array_set(new, %w[settings spacing defaultSpacingSizes], false)
      end

      # v3 merges spacingSizes with the generated spacingScale sizes instead of
      # replacing them; v2 documents keep the old ("bugged") behaviour.
      unless PhpCompat.array_get(old, %w[settings spacing spacingSizes]).nil?
        new.dig('settings', 'spacing')&.delete('spacingScale')
      end

      new
    end

    # BR-MIGRATE-215 — class-wp-theme-json-schema.php:173.
    #
    # @param settings [Hash]
    # @param paths_to_rename [Hash{String=>String}]
    # @return [Hash]
    def rename_paths(settings, paths_to_rename)
      new_settings = PhpCompat.deep_dup(settings)
      return new_settings unless new_settings.is_a?(Hash)

      rename_settings(new_settings, paths_to_rename)

      if new_settings['blocks'].is_a?(Hash)
        new_settings['blocks'].each_value do |block_settings|
          rename_settings(block_settings, paths_to_rename) if block_settings.is_a?(Hash)
        end
      end

      new_settings
    end

    # BR-MIGRATE-215 — class-wp-theme-json-schema.php:197. Mutates `settings`.
    #
    # @param settings [Hash]
    # @param paths_to_rename [Hash{String=>String}]
    # @return [void]
    def rename_settings(settings, paths_to_rename)
      paths_to_rename.each do |original, renamed|
        original_path = original.split('.')
        renamed_path = renamed.split('.')
        current_value = PhpCompat.array_get(settings, original_path, nil)
        next if current_value.nil?

        PhpCompat.array_set(settings, renamed_path, current_value)
        unset_by_path(settings, original_path)
      end
      nil
    end

    # BR-MIGRATE-215 — class-wp-theme-json-schema.php:218.
    #
    # @param settings [Hash]
    # @param path [Array<String>]
    # @return [void]
    def unset_by_path(settings, path)
      cursor = settings
      path[0..-2].each do |key|
        cursor = cursor[key]
        return nil unless cursor.is_a?(Hash)
      end
      cursor.delete(path[-1])
      nil
    end
  end
end
