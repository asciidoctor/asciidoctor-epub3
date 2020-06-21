# frozen_string_literal: true

class Asciidoctor::Document
  class << self
    def supports_syntax_highlighter?
      if @supports_syntax_highlighter.nil?
        # Asciidoctor only got pluggable syntax highlighters since 2.0:
        # https://github.com/asciidoctor/asciidoctor/commit/23ddbaed6818025cbe74365fec7e8101f34eadca
        @supports_syntax_highlighter = method_defined? :syntax_highlighter
      end

      @supports_syntax_highlighter
    end
  end

  def syntax_highlighter
    nil
  end unless supports_syntax_highlighter?
end
