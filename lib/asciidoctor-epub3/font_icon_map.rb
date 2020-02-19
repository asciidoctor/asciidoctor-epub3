# frozen_string_literal: true

require 'yaml'

module Asciidoctor
  module Epub3
    # Map of Font Awesome icon names to unicode characters
    class FontIconMap
      class << self
        FONT_AWESOME_DIR = File.join __dir__, '..', '..', 'data', 'fonts', 'awesome'

        def icons
          @icons ||= YAML.load_file File.join(FONT_AWESOME_DIR, 'icons.yml')
        end

        def shims
          @shims ||= YAML.load_file File.join(FONT_AWESOME_DIR, 'shims.yml')
        end

        def unicode icon_name
          shim = shims[icon_name]
          icon_name = shim['name'] unless shim.nil?
          icon_data = icons[icon_name]
          icon_data.nil? ? '' : %(\\#{icon_data['unicode']})
        end
      end
    end
  end
end
