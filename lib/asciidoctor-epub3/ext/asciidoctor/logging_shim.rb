# frozen_string_literal: true

module Asciidoctor
  module Logging
    class StubLogger
      class << self
        def debug message = nil
          puts %(asciidoctor: DEBUG: #{message || (block_given? ? yield : '???')}) if $VERBOSE
        end

        def info message = nil
          puts %(asciidoctor: INFO: #{message || (block_given? ? yield : '???')}) if $VERBOSE
        end

        def warn message = nil
          ::Kernel.warn %(asciidoctor: WARNING: #{message || (block_given? ? yield : '???')})
        end

        def error message = nil
          ::Kernel.warn %(asciidoctor: ERROR: #{message || (block_given? ? yield : '???')})
        end

        def fatal message = nil
          ::Kernel.warn %(asciidoctor: FATAL: #{message || (block_given? ? yield : '???')})
        end
      end
    end

    def logger
      StubLogger
    end
  end
end
