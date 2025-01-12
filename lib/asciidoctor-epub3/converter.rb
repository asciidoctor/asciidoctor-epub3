# frozen_string_literal: true

require 'mime/types'
require 'open3'
require 'sass'
require_relative 'font_icon_map'

module Asciidoctor
  module Epub3
    # Public: The main converter for the epub3 backend that handles packaging the EPUB3 publication file.
    class Converter
      include ::Asciidoctor::Converter
      include ::Asciidoctor::Logging
      include ::Asciidoctor::Writer

      register_for 'epub3'

      def write(output, target)
        output.generate_epub target
        logger.debug %(Wrote to #{target})
        if @extract
          extract_dir = target.sub EPUB_EXTENSION_RX, ''
          ::FileUtils.remove_dir extract_dir if ::File.directory? extract_dir
          ::Dir.mkdir extract_dir
          ::Dir.chdir extract_dir do
            ::Zip::File.open target do |entries|
              entries.each do |entry|
                next unless entry.file?

                unless (entry_dir = ::File.dirname entry.name) == '.' || (::File.directory? entry_dir)
                  ::FileUtils.mkdir_p entry_dir
                end
                entry.extract entry.name
              end
            end
          end
          logger.debug %(Extracted to #{extract_dir})
        end

        return unless @validate

        validate_epub target
      end

      CSV_DELIMITED_RX = /\s*,\s*/.freeze

      DATA_DIR = ::File.expand_path ::File.join(__dir__, '..', '..', 'data')
      IMAGE_MACRO_RX = /^image::?(.*?)\[(.*?)\]$/.freeze
      IMAGE_SRC_SCAN_RX = /<img src="(.+?)"/.freeze
      SVG_IMG_SNIFF_RX = /<img src=".+?\.svg"/.freeze

      LF = "\n"
      NO_BREAK_SPACE = '&#xa0;'
      RIGHT_ANGLE_QUOTE = '&#x203a;'
      CALLOUT_START_NUM = %(\u2460)

      CHAR_ENTITY_RX = /&#(\d{2,6});/.freeze
      XML_ELEMENT_RX = %r{</?.+?>}.freeze
      TRAILING_PUNCT_RX = /[[:punct:]]$/.freeze

      FROM_HTML_SPECIAL_CHARS_MAP = {
        '&lt;' => '<',
        '&gt;' => '>',
        '&amp;' => '&'
      }.freeze

      FROM_HTML_SPECIAL_CHARS_RX = /(?:#{FROM_HTML_SPECIAL_CHARS_MAP.keys * '|'})/.freeze

      TO_HTML_SPECIAL_CHARS_MAP = {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;'
      }.freeze

      TO_HTML_SPECIAL_CHARS_RX = /[#{TO_HTML_SPECIAL_CHARS_MAP.keys.join}]/.freeze

      EPUB_EXTENSION_RX = /\.epub$/i.freeze

      # This is a workaround for https://github.com/asciidoctor/asciidoctor/issues/4380
      # Currently, there is no access to parent cell from inner document
      PARENT_CELL_FIELD_NAME = :@epub3_parent_cell

      QUOTE_TAGS = begin
        tags = {
          monospaced: ['<code>', '</code>', true],
          emphasis: ['<em>', '</em>', true],
          strong: ['<strong>', '</strong>', true],
          double: ['“', '”'],
          single: ['‘', '’'],
          mark: ['<mark>', '</mark>', true],
          superscript: ['<sup>', '</sup>', true],
          subscript: ['<sub>', '</sub>', true],
          asciimath: ['<code>', '</code>', true],
          latexmath: ['<code>', '</code>', true]
        }
        tags.default = ['', '']
        tags.freeze
      end

      def initialize(backend, opts = {})
        super

        @xrefs_seen = Set.new
        @media_files = {}
        @footnotes = []

        basebackend 'html'
        filetype 'epub'
        outfilesuffix '.epub'
        htmlsyntax 'xml'
        supports_templates true
      end

      def convert(node, name = nil, _opts = {})
        method_name = %(convert_#{name ||= node.node_name})
        if respond_to? method_name
          send method_name, node
        else
          logger.warn %(conversion missing in backend #{@backend} for #{name})
          nil
        end
      end

      # @param node [Asciidoctor::AbstractNode]
      # @return [String, nil]
      def get_chapter_filename(node)
        node.id if node.chapter?
      end

      def get_numbered_title(node)
        doc_attrs = node.document.attributes
        level = node.level
        if node.caption
          node.captioned_title
        elsif node.respond_to?(:numbered) && node.numbered && level <= (doc_attrs['sectnumlevels'] || 3).to_i
          if level < 2 && node.document.doctype == 'book'
            case node.sectname
            when 'chapter'
              %(#{(signifier = doc_attrs['chapter-signifier']) ? "#{signifier} " : ''}#{node.sectnum} #{node.title})
            when 'part'
              %(#{(signifier = doc_attrs['part-signifier']) ? "#{signifier} " : ''}#{node.sectnum nil,
                                                                                                  ':'} #{node.title})
            else
              %(#{node.sectnum} #{node.title})
            end
          else
            %(#{node.sectnum} #{node.title})
          end
        else
          node.title
        end
      end

      def icon_names
        @icon_names ||= []
      end

      def convert_document(node)
        @validate = node.attr? 'ebook-validate'
        @extract = node.attr? 'ebook-extract'
        @compress = node.attr 'ebook-compress'
        @epubcheck_path = node.attr 'ebook-epubcheck-path'

        @book = GEPUB::Book.new 'EPUB/package.opf'
        @book.epub_backward_compat = true
        @book.language node.attr('lang', 'en'), id: 'pub-language'

        if node.attr? 'uuid'
          @book.primary_identifier node.attr('uuid'), 'pub-identifier', 'uuid'
        else
          @book.primary_identifier node.id, 'pub-identifier', 'uuid'
        end
        # replace with next line once the attributes argument is supported
        # unique_identifier doc.id, 'pub-id', 'uuid', 'scheme' => 'xsd:string'

        # NOTE: we must use :plain_text here since gepub reencodes
        @book.add_title sanitize_doctitle_xml(node, :plain_text), id: 'pub-title'

        # see https://www.w3.org/publishing/epub3/epub-packages.html#sec-opf-dccreator
        (1..(node.attr 'authorcount', 1).to_i).map do |idx|
          author = node.attr(idx == 1 ? 'author' : %(author_#{idx}))
          @book.add_creator author, role: 'aut' unless author.nil_or_empty?
        end

        publisher = node.attr 'publisher'
        # NOTE: Use producer as both publisher and producer if publisher isn't specified
        publisher = node.attr 'producer' if publisher.nil_or_empty?
        @book.publisher = publisher unless publisher.nil_or_empty?

        if node.attr? 'reproducible'
          # We need to set lastmodified to some fixed value. Otherwise, gepub will set it to current date.
          @book.lastmodified = (::Time.at 0).utc
          # Is it correct that we do not populate dc:date when 'reproducible' is set?
        else
          if node.attr? 'revdate'
            begin
              @book.date = node.attr 'revdate'
            rescue ArgumentError => e
              logger.error %(#{::File.basename node.attr('docfile')}: failed to parse revdate: #{e})
              @book.date = node.attr 'docdatetime'
            end
          else
            @book.date = node.attr 'docdatetime'
          end
          @book.lastmodified = node.attr 'localdatetime'
        end

        @book.description = node.attr 'description' if node.attr? 'description'
        @book.source = node.attr 'source' if node.attr? 'source'
        @book.rights = node.attr 'copyright' if node.attr? 'copyright'

        (node.attr 'keywords', '').split(CSV_DELIMITED_RX).each do |s|
          @book.metadata.add_metadata 'subject', s
        end

        if node.attr? 'series-name'
          series_name = node.attr 'series-name'
          series_volume = node.attr 'series-volume', 1
          series_id = node.attr 'series-id'

          series_meta = @book.metadata.add_metadata 'meta', series_name, id: 'pub-collection',
                                                                         group_position: series_volume
          series_meta['property'] = 'belongs-to-collection'
          series_meta.refine 'dcterms:identifier', series_id unless series_id.nil?
          # Calibre only understands 'series'
          series_meta.refine 'collection-type', 'series'
        end

        # For list of supported landmark types see
        # https://idpf.github.io/epub-vocabs/structure/
        landmarks = []

        front_cover = add_cover_page node, 'front-cover'
        if front_cover.nil? && node.doctype == 'book'
          # TODO(#352): add textual front cover similar to PDF
        end

        landmarks << { type: 'cover', href: front_cover.href, title: 'Front Cover' } unless front_cover.nil?

        front_matter_page = add_front_matter_page node
        unless front_matter_page.nil?
          landmarks << { type: 'frontmatter', href: front_matter_page.href,
                         title: 'Front Matter' }
        end

        nav_item = @book.add_item('nav.xhtml', id: 'nav').nav

        toclevels = [(node.attr 'toclevels', 1).to_i, 0].max
        outlinelevels = [(node.attr 'outlinelevels', toclevels).to_i, 0].max

        if node.attr? 'toc'
          toc_item = @book.add_ordered_item 'toc.xhtml', id: 'toc'
          landmarks << { type: 'toc', href: toc_item.href, title: node.attr('toc-title') }
        else
          toc_item = nil
        end

        if node.doctype == 'book'
          toc_items = node.sections
          node.content
        else
          toc_items = [node]
          add_chapter node
        end

        _back_cover = add_cover_page node, 'back-cover'
        # TODO: add landmark for back cover? But what epub:type?

        unless toc_items.empty?
          landmarks << { type: 'bodymatter', href: %(#{get_chapter_filename toc_items[0]}.xhtml),
                         title: 'Start of Content' }
        end

        toc_items.each do |item|
          next unless %w[appendix bibliography glossary index preface].include? item.style

          landmarks << {
            type: item.style,
            href: %(#{get_chapter_filename item}.xhtml),
            title: item.title
          }
        end

        nav_item.add_content nav_doc(node, toc_items, landmarks, outlinelevels).to_ios
        # User is not supposed to see landmarks, so pass empty array here
        toc_item&.add_content nav_doc(node, toc_items, [], toclevels).to_ios

        # NOTE: gepub doesn't support building a ncx TOC with depth > 1, so do it ourselves
        toc_ncx = ncx_doc node, toc_items, outlinelevels
        @book.add_item 'toc.ncx', content: toc_ncx.to_ios, id: 'ncx'

        docimagesdir = (node.attr 'imagesdir', '.').chomp '/'
        docimagesdir = (docimagesdir == '.' ? nil : %(#{docimagesdir}/))

        @media_files.each do |name, file|
          if name.start_with? %(#{docimagesdir}jacket/cover.)
            logger.warn %(path is reserved for cover artwork: #{name}; skipping file found in content)
          elsif file[:path].nil? || File.readable?(file[:path])
            mime_types = MIME::Types.type_for name
            mime_types.delete_if { |x| x.media_type != file[:media_type] }
            preferred_mime_type = mime_types.empty? ? nil : mime_types[0].content_type
            @book.add_item name, content: file[:path], media_type: preferred_mime_type
          else
            logger.error %(#{File.basename node.attr('docfile')}: media file not found or not readable: #{file[:path]})
          end
        end

        # add_metadata 'ibooks:specified-fonts', true

        add_theme_assets node
        if node.doctype != 'book'
          usernames = [node].map { |item| item.attr 'username' }.compact.uniq
          add_profile_images node, usernames
        end

        @book
      end

      # FIXME: move to Asciidoctor::Helpers
      def sanitize_doctitle_xml(doc, content_spec)
        doctitle = doc.doctitle use_fallback: true
        sanitize_xml doctitle, content_spec
      end

      # FIXME: move to Asciidoctor::Helpers
      def sanitize_xml(content, content_spec)
        if content_spec != :pcdata && (content.include? '<') && ((content = (content.gsub XML_ELEMENT_RX,
                                                                                          '').strip).include? ' ')
          content = content.tr_s ' ', ' '
        end

        case content_spec
        when :attribute_cdata
          content = content.gsub '"', '&quot;' if content.include? '"'
        when :cdata, :pcdata
          # noop
        when :plain_text
          if content.include? ';'
            content = content.gsub(CHAR_ENTITY_RX) { [::Regexp.last_match(1).to_i].pack 'U*' } if content.include? '&#'
            content = content.gsub FROM_HTML_SPECIAL_CHARS_RX, FROM_HTML_SPECIAL_CHARS_MAP
          end
        else
          raise ::ArgumentError, %(Unknown content spec: #{content_spec})
        end
        content
      end

      # @param node [Asciidoctor::AbstractBlock]
      def add_chapter(node)
        filename = get_chapter_filename node
        return nil if filename.nil?

        chapter_item = @book.add_ordered_item %(#{filename}.xhtml)

        doctitle = node.document.doctitle partition: true, use_fallback: true
        chapter_title = doctitle.combined

        if node.context == :document && doctitle.subtitle?
          title = %(#{doctitle.main} )
          subtitle = doctitle.subtitle
        elsif node.title
          # HACK: until we get proper handling of title-only in CSS
          title = ''
          subtitle = get_numbered_title node
          chapter_title = subtitle
        else
          title = nil
          subtitle = nil
        end

        if node.document.doctype == 'book'
          byline = ''
        else
          author = node.attr 'author'
          username = node.attr 'username', 'default'
          imagesdir = (node.document.attr 'imagesdir', '.').chomp '/'
          imagesdir = imagesdir == '.' ? '' : %(#{imagesdir}/)
          byline = %(<p class="byline"><img src="#{imagesdir}avatars/#{username}.jpg"/> <b class="author">#{author}</b></p>#{LF})
        end

        mark_last_paragraph node unless node.document.doctype == 'book'

        @xrefs_seen.clear
        content = node.content

        # NOTE: must run after content is resolved
        # TODO perhaps create dynamic CSS file?
        if icon_names.empty?
          icon_css_head = ''
        else
          icon_defs = icon_names.map { |name|
            %(.i-#{name}::before { content: "#{FontIconMap.unicode name}"; })
          } * LF
          icon_css_head = %(<style>
#{icon_defs}
</style>
)
        end

        header = if title || subtitle
                   %(<header class="chapter-header">
#{byline}<h1 class="chapter-title">#{title}#{subtitle ? %(<small class="subtitle">#{subtitle}</small>) : ''}</h1>
</header>)
                 else
                   ''
                 end

        # We want highlighter CSS to be stored in a separate file
        # in order to avoid style duplication across chapter files
        linkcss = true

        lines = [%(<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xmlns:mml="http://www.w3.org/1998/Math/MathML" xml:lang="#{lang = node.document.attr 'lang',
                                                                                                                                                                          'en'}" lang="#{lang}">
<head>
<title>#{chapter_title}</title>
<link rel="stylesheet" type="text/css" href="styles/epub3.css"/>
<link rel="stylesheet" type="text/css" href="styles/epub3-css3-only.css" media="(min-device-width: 0px)"/>
#{icon_css_head}<script type="text/javascript"><![CDATA[
document.addEventListener('DOMContentLoaded', function(event, reader) {
  if (!(reader = navigator.epubReadingSystem)) {
    if (navigator.userAgent.indexOf(' calibre/') >= 0) reader = { name: 'calibre-desktop' };
    else if (window.parent == window || !(reader = window.parent.navigator.epubReadingSystem)) return;
  }
  document.body.setAttribute('class', reader.name.toLowerCase().replace(/ /g, '-'));
});
]]></script>)]

        syntax_hl = node.document.syntax_highlighter
        epub_type_attr = node.respond_to?(:section) && node.sectname != 'section' ? %( epub:type="#{node.sectname}") : ''

        if syntax_hl&.docinfo? :head
          lines << (syntax_hl.docinfo :head, node, linkcss: linkcss,
                                                   self_closing_tag_slash: '/')
        end

        lines << %(</head>
<body>
<section class="chapter" title=#{chapter_title.encode xml: :attr}#{epub_type_attr} id="#{filename}">
#{header}
        #{content})

        unless (fns = node.document.footnotes - @footnotes).empty?
          @footnotes += fns

          lines << '<footer class="chapter-footer">
<div class="footnotes">'
          fns.each do |footnote|
            lines << %(<aside id="note-#{footnote.index}" epub:type="footnote">
<p>#{footnote.text}</p>
</aside>)
          end
          lines << '</div>
</footer>'
        end

        lines << '</section>'

        if syntax_hl&.docinfo? :footer
          lines << (syntax_hl.docinfo :footer, node.document, linkcss: linkcss,
                                                              self_closing_tag_slash: '/')
        end

        lines << '</body>
</html>'

        chapter_item.add_content((lines * LF).to_ios)
        epub_properties = node.attr 'epub-properties'
        chapter_item.add_property 'svg' if epub_properties&.include? 'svg'

        # # QUESTION reenable?
        # #linear 'yes' if i == 0

        chapter_item
      end

      # @param node [Asciidoctor::Section]
      def convert_section(node)
        return unless add_chapter(node).nil?

        hlevel = node.level.clamp 1, 6
        epub_type_attr = node.sectname == 'section' ? '' : %( epub:type="#{node.sectname}")
        div_classes = [%(sect#{node.level}), node.role].compact
        title = get_numbered_title node
        %(<section class="#{div_classes * ' '}" title=#{title.encode xml: :attr}#{epub_type_attr}>
<h#{hlevel} id="#{node.id}">#{title}</h#{hlevel}>#{if (content = node.content).empty?
                                                     ''
                                                   else
                                                     %(
          #{content})
                                                   end}
</section>)
      end

      # NOTE: embedded is used for AsciiDoc table cell content
      def convert_embedded(node)
        node.content
      end

      # TODO: support use of quote block as abstract
      def convert_preamble(node)
        return unless add_chapter(node).nil?

        if ((first_block = node.blocks[0]) && first_block.style == 'abstract') ||
           # REVIEW: should we treat the preamble as an abstract in general?
           (first_block && node.blocks.size == 1)
          convert_abstract first_block
        else
          node.content
        end
      end

      def convert_open(node)
        id_attr = node.id ? %( id="#{node.id}") : nil
        class_attr = node.role ? %( class="#{node.role}") : nil
        if id_attr || class_attr
          %(<div#{id_attr}#{class_attr}>
#{output_content node}
</div>)
        else
          output_content node
        end
      end

      def convert_abstract(node)
        %(<div class="abstract" epub:type="preamble">
#{output_content node}
</div>)
      end

      def convert_paragraph(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        role = node.role
        # stack-head is the alternative to the default, inline-head (where inline means "run-in")
        head_stop = node.attr 'head-stop', (role && (node.has_role? 'stack-head') ? nil : '.')
        head = if node.title?
                 %(<strong class="head">#{title = node.title}#{head_stop && title !~ TRAILING_PUNCT_RX ? head_stop : ''}</strong> )
               else
                 ''
               end
        if role
          node.set_option 'hardbreaks' if node.has_role? 'signature'
          %(<p#{id_attr} class="#{role}">#{head}#{node.content}</p>)
        else
          %(<p#{id_attr}>#{head}#{node.content}</p>)
        end
      end

      def convert_pass(node)
        content = node.content
        if content == '<?hard-pagebreak?>'
          '<hr epub:type="pagebreak" class="pagebreak"/>'
        else
          content
        end
      end

      def convert_admonition(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        if node.title?
          title = node.title
          title_sanitized = xml_sanitize title
          title_attr = %( title="#{node.caption}: #{title_sanitized}")
          title_el = %(<h2>#{title}</h2>
)
        else
          title_attr = %( title="#{node.caption}")
          title_el = ''
        end

        type = node.attr 'name'
        epub_type = case type
                    when 'tip'
                      'tip'
                    when 'important', 'warning', 'caution', 'note'
                      'notice'
                    else
                      logger.warn %(unknown admonition type: #{type})
                      'notice'
                    end
        %(<aside#{id_attr} class="admonition #{type}#{(role = node.role) ? " #{role}" : ''}"#{title_attr} epub:type="#{epub_type}">
#{title_el}<div class="content">
#{output_content node}
</div>
</aside>)
      end

      def convert_example(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        title_div = if node.title?
                      %(<div class="example-title">#{node.title}</div>
)
                    else
                      ''
                    end
        %(<div#{id_attr} class="example">
#{title_div}<div class="example-content">
#{output_content node}
</div>
</div>)
      end

      def convert_floating_title(node)
        tag_name = %(h#{node.level + 1})
        id_attribute = node.id ? %( id="#{node.id}") : ''
        %(<#{tag_name}#{id_attribute} class="#{['discrete', node.role].compact * ' '}">#{node.title}</#{tag_name}>)
      end

      # @param node [Asciidoctor::Block]
      def convert_listing(node)
        id_attribute = node.id ? %( id="#{node.id}") : ''
        nowrap = (node.option? 'nowrap') || !(node.document.attr? 'prewrap')
        if node.style == 'source'
          lang = node.attr 'language'
          syntax_hl = node.document.syntax_highlighter
          if syntax_hl
            opts = if syntax_hl.highlight?
                     {
                       css_mode: ((doc_attrs = node.document.attributes)[%(#{syntax_hl.name}-css)] || :class).to_sym,
                       style: doc_attrs[%(#{syntax_hl.name}-style)]
                     }
                   else
                     {}
                   end
            opts[:nowrap] = nowrap
          else
            pre_open = %(<pre class="highlight#{nowrap ? ' nowrap' : ''}"><code#{lang ? %( class="language-#{lang}" data-lang="#{lang}") : ''}>)
            pre_close = '</code></pre>'
          end
        else
          pre_open = %(<pre#{nowrap ? ' class="nowrap"' : ''}>)
          pre_close = '</pre>'
          syntax_hl = nil
        end
        figure_classes = ['listing']
        figure_classes << 'coalesce' if node.option? 'unbreakable'
        title_div = node.title? ? %(<figcaption>#{node.captioned_title}</figcaption>) : ''
        %(<figure#{id_attribute} class="#{figure_classes * ' '}">#{title_div}
        #{syntax_hl ? (syntax_hl.format node, lang, opts) : pre_open + (node.content || '') + pre_close}
</figure>)
      end

      def convert_stem(node)
        return convert_listing node if node.style != 'asciimath' || !asciimath_available?

        id_attr = node.id ? %( id="#{node.id}") : ''
        title_element = node.title? ? %(<figcaption>#{node.captioned_title}</figcaption>) : ''
        equation_data = AsciiMath.parse(node.content).to_mathml 'mml:'

        %(<figure#{id_attr} class="#{prepend_space node.role}">
#{title_element}
<div class="content">
#{equation_data}
</div>
</figure>)
      end

      def asciimath_available?
        (@asciimath_status ||= load_asciimath) == :loaded
      end

      def load_asciimath
        Helpers.require_library('asciimath', true, :warn).nil? ? :unavailable : :loaded
      end

      def convert_literal(node)
        id_attribute = node.id ? %( id="#{node.id}") : ''
        title_element = node.title? ? %(<figcaption>#{node.captioned_title}</figcaption>) : ''
        %(<figure#{id_attribute} class="literalblock#{prepend_space node.role}">
#{title_element}
<div class="content"><pre class="screen">#{node.content}</pre></div>
</figure>)
      end

      def convert_page_break(_node)
        '<hr epub:type="pagebreak" class="pagebreak"/>'
      end

      def convert_thematic_break(_node)
        '<hr class="thematicbreak"/>'
      end

      def convert_quote(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        class_attr = (role = node.role) ? %( class="blockquote #{role}") : ' class="blockquote"'

        footer_content = []
        if (attribution = node.attr 'attribution')
          footer_content << attribution
        end

        if (citetitle = node.attr 'citetitle')
          citetitle_sanitized = xml_sanitize citetitle
          footer_content << %(<cite title="#{citetitle_sanitized}">#{citetitle}</cite>)
        end

        footer_content << %(<span class="context">#{node.title}</span>) if node.title?

        footer_tag = if footer_content.empty?
                       ''
                     else
                       %(
<footer>~ #{footer_content * ' '}</footer>)
                     end
        content = (output_content node).strip
        %(<div#{id_attr}#{class_attr}>
<blockquote>
#{content}#{footer_tag}
</blockquote>
</div>)
      end

      def convert_verse(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        class_attr = (role = node.role) ? %( class="verse #{role}") : ' class="verse"'

        footer_content = []
        if (attribution = node.attr 'attribution')
          footer_content << attribution
        end

        if (citetitle = node.attr 'citetitle')
          citetitle_sanitized = xml_sanitize citetitle
          footer_content << %(<cite title="#{citetitle_sanitized}">#{citetitle}</cite>)
        end

        footer_tag = if footer_content.empty?
                       ''
                     else
                       %(
<span class="attribution">~ #{footer_content * ', '}</span>)
                     end
        %(<div#{id_attr}#{class_attr}>
<pre>#{node.content}#{footer_tag}</pre>
</div>)
      end

      def convert_sidebar(node)
        id_attribute = node.id ? %( id="#{node.id}") : ''
        classes = ['sidebar']
        if node.title?
          classes << 'titled'
          title = node.title
          title_sanitized = xml_sanitize title
          title_attr = %( title="#{title_sanitized}")
          title_el = %(<h2>#{title}</h2>
)
        else
          title_attr = title_el = ''
        end

        %(<aside#{id_attribute} class="#{classes * ' '}"#{title_attr} epub:type="sidebar">
#{title_el}<div class="content">
#{output_content node}
</div>
</aside>)
      end

      def convert_table(node)
        lines = [%(<div class="table">)]
        lines << %(<div class="content">)
        table_id_attr = node.id ? %( id="#{node.id}") : ''
        table_classes = [
          'table',
          %(table-framed-#{node.attr 'frame', 'rows', 'table-frame'}),
          %(table-grid-#{node.attr 'grid', 'rows', 'table-grid'})
        ]
        if (role = node.role)
          table_classes << role
        end
        if (float = node.attr 'float')
          table_classes << float
        end
        table_styles = []
        if (autowidth = node.option? 'autowidth') && !(node.attr? 'width')
          table_classes << 'fit-content'
        else
          table_styles << %(width: #{node.attr 'tablepcwidth'}%;)
        end
        table_class_attr = %( class="#{table_classes * ' '}")
        table_style_attr = table_styles.empty? ? '' : %( style="#{table_styles * '; '}")

        lines << %(<table#{table_id_attr}#{table_class_attr}#{table_style_attr}>)
        lines << %(<caption>#{node.captioned_title}</caption>) if node.title?
        if (node.attr 'rowcount').positive?
          lines << '<colgroup>'
          if autowidth
            lines += (Array.new node.columns.size, %(<col/>))
          else
            node.columns.each do |col|
              lines << (col.option?('autowidth') ? %(<col/>) : %(<col style="width: #{col.attr 'colpcwidth'}%;" />))
            end
          end
          lines << '</colgroup>'
          %i[head body foot].reject { |tsec| node.rows[tsec].empty? }.each do |tsec|
            lines << %(<t#{tsec}>)
            node.rows[tsec].each do |row|
              lines << '<tr>'
              row.each do |cell|
                if tsec == :head
                  cell_content = cell.text
                else
                  case cell.style
                  when :asciidoc
                    cell.inner_document.instance_variable_set(PARENT_CELL_FIELD_NAME, cell)
                    cell_content = %(<div class="embed">#{cell.content}</div>)
                  when :verse
                    cell_content = %(<div class="verse">#{cell.text}</div>)
                  when :literal
                    cell_content = %(<div class="literal"><pre>#{cell.text}</pre></div>)
                  else
                    cell_content = ''
                    cell.content.each do |text|
                      cell_content = %(#{cell_content}<p class="tableblock">#{text}</p>)
                    end
                  end
                end

                cell_tag_name = tsec == :head || cell.style == :header ? 'th' : 'td'
                cell_classes = [
                  "halign-#{cell.attr 'halign'}",
                  "valign-#{cell.attr 'valign'}"
                ]
                cell_class_attr = cell_classes.empty? ? '' : %( class="#{cell_classes * ' '}")
                cell_colspan_attr = cell.colspan ? %( colspan="#{cell.colspan}") : ''
                cell_rowspan_attr = cell.rowspan ? %( rowspan="#{cell.rowspan}") : ''
                cell_style_attr = node.document.attr?('cellbgcolor') ? %( style="background-color: #{node.document.attr 'cellbgcolor'}") : ''
                lines << %(<#{cell_tag_name}#{cell_class_attr}#{cell_colspan_attr}#{cell_rowspan_attr}#{cell_style_attr}>#{cell_content}</#{cell_tag_name}>)
              end
              lines << '</tr>'
            end
            lines << %(</t#{tsec}>)
          end
        end
        lines << '</table>
</div>
</div>'
        lines * LF
      end

      def convert_colist(node)
        lines = ['<div class="callout-list">
<ol>']
        num = CALLOUT_START_NUM
        node.items.each_with_index do |item, i|
          lines << %(<li><i class="conum" data-value="#{i + 1}">#{num}</i> #{item.text}#{item.content if item.blocks?}</li>)
          num = num.next
        end
        lines << '</ol>
</div>'
      end

      # TODO: add complex class if list has nested blocks
      def convert_dlist(node)
        lines = []
        id_attribute = node.id ? %( id="#{node.id}") : ''

        classes = case node.style
                  when 'horizontal'
                    ['hdlist', node.role]
                  when 'itemized', 'ordered'
                    # QUESTION: should we just use itemized-list and ordered-list as the class here? or just list?
                    ['dlist', %(#{node.style}-list), node.role]
                  else
                    ['description-list']
                  end.compact

        class_attribute = %( class="#{classes.join ' '}")

        lines << %(<div#{id_attribute}#{class_attribute}>)
        lines << %(<div class="title">#{node.title}</div>) if node.title?

        case (style = node.style)
        when 'itemized', 'ordered'
          list_tag_name = style == 'itemized' ? 'ul' : 'ol'
          role = node.role
          subject_stop = node.attr 'subject-stop', (role && (node.has_role? 'stack') ? nil : ':')
          list_class_attr = node.option?('brief') ? ' class="brief"' : ''
          lines << %(<#{list_tag_name}#{list_class_attr}#{list_tag_name == 'ol' && (node.option? 'reversed') ? ' reversed="reversed"' : ''}>)
          node.items.each do |subjects, dd|
            # consists of one term (a subject) and supporting content
            subject = Array(subjects).first.text
            subject_plain = xml_sanitize subject, :plain
            subject_element = %(<strong class="subject">#{subject}#{subject_stop && subject_plain !~ TRAILING_PUNCT_RX ? subject_stop : ''}</strong>)
            lines << '<li>'
            if dd
              # NOTE: must wrap remaining text in a span to help webkit justify the text properly
              lines << %(<span class="principal">#{subject_element}#{dd.text? ? %( <span class="supporting">#{dd.text}</span>) : ''}</span>)
              lines << dd.content if dd.blocks?
            else
              lines << %(<span class="principal">#{subject_element}</span>)
            end
            lines << '</li>'
          end
          lines << %(</#{list_tag_name}>)
        when 'horizontal'
          lines << '<table>'
          if (node.attr? 'labelwidth') || (node.attr? 'itemwidth')
            lines << '<colgroup>'
            col_style_attribute = node.attr?('labelwidth') ? %( style="width: #{(node.attr 'labelwidth').chomp '%'}%;") : ''
            lines << %(<col#{col_style_attribute} />)
            col_style_attribute = node.attr?('itemwidth') ? %( style="width: #{(node.attr 'itemwidth').chomp '%'}%;") : ''
            lines << %(<col#{col_style_attribute} />)
            lines << '</colgroup>'
          end
          node.items.each do |terms, dd|
            lines << '<tr>'
            lines << %(<td class="hdlist1#{node.option?('strong') ? ' strong' : ''}">)
            first_term = true
            terms.each do |dt|
              lines << %(<br />) unless first_term
              lines << '<p>'
              lines << dt.text
              lines << '</p>'
              first_term = nil
            end
            lines << '</td>'
            lines << '<td class="hdlist2">'
            if dd
              lines << %(<p>#{dd.text}</p>) if dd.text?
              lines << dd.content if dd.blocks?
            end
            lines << '</td>'
            lines << '</tr>'
          end
          lines << '</table>'
        else
          lines << '<dl>'
          node.items.each do |terms, dd|
            Array(terms).each do |dt|
              lines << %(<dt>
<span class="term">#{dt.text}</span>
</dt>)
            end
            next unless dd

            lines << '<dd>'
            if dd.blocks?
              lines << %(<span class="principal">#{dd.text}</span>) if dd.text?
              lines << dd.content
            else
              lines << %(<span class="principal">#{dd.text}</span>)
            end
            lines << '</dd>'
          end
          lines << '</dl>'
        end

        lines << '</div>'
        lines * LF
      end

      def convert_olist(node)
        complex = false
        div_classes = ['ordered-list', node.style, node.role].compact
        ol_classes = [node.style, (node.option?('brief') ? 'brief' : nil)].compact
        ol_class_attr = ol_classes.empty? ? '' : %( class="#{ol_classes * ' '}")
        ol_start_attr = node.attr?('start') ? %( start="#{node.attr 'start'}") : ''
        id_attribute = node.id ? %( id="#{node.id}") : ''
        lines = [%(<div#{id_attribute} class="#{div_classes * ' '}">)]
        lines << %(<h3 class="list-heading">#{node.title}</h3>) if node.title?
        lines << %(<ol#{ol_class_attr}#{ol_start_attr}#{node.option?('reversed') ? ' reversed="reversed"' : ''}>)
        node.items.each do |item|
          li_classes = [item.role].compact
          li_class_attr = li_classes.empty? ? '' : %( class="#{li_classes * ' '}")
          lines << %(<li#{li_class_attr}>
<span class="principal">#{item.text}</span>)
          if item.blocks?
            lines << item.content
            complex = true unless item.blocks.size == 1 && item.blocks[0].is_a?(::Asciidoctor::List)
          end
          lines << '</li>'
        end
        if complex
          div_classes << 'complex'
          lines[0] = %(<div class="#{div_classes * ' '}">)
        end
        lines << '</ol>
</div>'
        lines * LF
      end

      def convert_ulist(node)
        complex = false
        div_classes = ['itemized-list', node.style, node.role].compact
        ul_classes = [node.style, (node.option?('brief') ? 'brief' : nil)].compact
        ul_class_attr = ul_classes.empty? ? '' : %( class="#{ul_classes * ' '}")
        id_attribute = node.id ? %( id="#{node.id}") : ''
        lines = [%(<div#{id_attribute} class="#{div_classes * ' '}">)]
        lines << %(<h3 class="list-heading">#{node.title}</h3>) if node.title?
        lines << %(<ul#{ul_class_attr}>)
        node.items.each do |item|
          li_classes = [item.role].compact
          li_class_attr = li_classes.empty? ? '' : %( class="#{li_classes * ' '}")
          lines << %(<li#{li_class_attr}>
<span class="principal">#{item.text}</span>)
          if item.blocks?
            lines << item.content
            complex = true unless item.blocks.size == 1 && item.blocks[0].is_a?(::Asciidoctor::List)
          end
          lines << '</li>'
        end
        if complex
          div_classes << 'complex'
          lines[0] = %(<div class="#{div_classes * ' '}">)
        end
        lines << '</ul>
</div>'
        lines * LF
      end

      def doc_option(document, key)
        loop do
          value = document.options[key]
          return value unless value.nil?

          document = document.parent_document
          break if document.nil?
        end
        nil
      end

      def root_document(document)
        document = document.parent_document until document.parent_document.nil?
        document
      end

      def register_media_file(node, target, media_type)
        if target.end_with?('.svg') || target.start_with?('data:image/svg+xml')
          chapter = get_enclosing_chapter node
          chapter.set_attr 'epub-properties', [] unless chapter.attr? 'epub-properties'
          epub_properties = chapter.attr 'epub-properties'
          epub_properties << 'svg' unless epub_properties.include? 'svg'
        end

        return if target.start_with? 'data:'

        if Asciidoctor::Helpers.uriish? target
          # We need to add both local and remote media files to manifest
          fs_path = nil
        else
          out_dir = node.attr('outdir', nil, true) || doc_option(node.document, :to_dir)
          fs_path = (::File.join out_dir, target)
          unless ::File.exist? fs_path
            base_dir = root_document(node.document).base_dir
            fs_path = ::File.join base_dir, target
          end
        end
        # We need *both* virtual and physical image paths. Unfortunately, references[:images] only has one of them.
        @media_files[target] ||= { path: fs_path, media_type: media_type }
      end

      # @param node [Asciidoctor::Block]
      # @return [Array<String>]
      def resolve_image_attrs(node)
        img_attrs = []

        unless (alt = encode_attribute_value(node.alt)).empty?
          img_attrs << %(alt="#{alt}")
        end

        # Unlike browsers, Calibre/Kindle *do* scale image if only height is specified
        # So, in order to match browser behavior, we just always omit height

        if (scaledwidth = node.attr 'scaledwidth')
          img_attrs << %(style="width: #{scaledwidth}")
        elsif (width = node.attr 'width')
          # HTML5 spec (and EPUBCheck) only allows pixels in width, but browsers also accept percents
          # and there are multiple AsciiDoc files in the wild that have width=percents%
          # So, for compatibility reasons, output percentage width as a CSS style
          img_attrs << if width[/^\d+%$/]
                         %(style="width: #{width}")
                       else
                         %(width="#{width}")
                       end
        end

        img_attrs
      end

      def convert_audio(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        target = node.media_uri node.attr 'target'
        register_media_file node, target, 'audio'
        title_element = node.title? ? %(\n<figcaption>#{node.captioned_title}</figcaption>) : ''

        autoplay_attr = node.option?('autoplay') ? ' autoplay="autoplay"' : ''
        controls_attr = node.option?('nocontrols') ? '' : ' controls="controls"'
        loop_attr = node.option?('loop') ? ' loop="loop"' : ''

        start_t = node.attr 'start'
        end_t = node.attr 'end'
        time_anchor = if start_t || end_t
                        %(#t=#{start_t || ''}#{end_t ? ",#{end_t}" : ''})
                      else
                        ''
                      end

        %(<figure#{id_attr} class="audioblock#{prepend_space node.role}">#{title_element}
<div class="content">
<audio src="#{target}#{time_anchor}"#{autoplay_attr}#{controls_attr}#{loop_attr}>
<div>Your Reading System does not support (this) audio.</div>
</audio>
</div>
</figure>)
      end

      # TODO: Support multiple video files in different formats for a single video
      def convert_video(node)
        id_attr = node.id ? %( id="#{node.id}") : ''
        target = node.media_uri node.attr 'target'
        register_media_file node, target, 'video'
        title_element = node.title? ? %(\n<figcaption>#{node.captioned_title}</figcaption>) : ''

        width_attr = node.attr?('width') ? %( width="#{node.attr 'width'}") : ''
        height_attr = node.attr?('height') ? %( height="#{node.attr 'height'}") : ''
        autoplay_attr = node.option?('autoplay') ? ' autoplay="autoplay"' : ''
        controls_attr = node.option?('nocontrols') ? '' : ' controls="controls"'
        loop_attr = node.option?('loop') ? ' loop="loop"' : ''

        start_t = node.attr 'start'
        end_t = node.attr 'end'
        time_anchor = if start_t || end_t
                        %(#t=#{start_t || ''}#{end_t ? ",#{end_t}" : ''})
                      else
                        ''
                      end

        if (poster = node.attr 'poster').nil_or_empty?
          poster_attr = ''
        else
          poster = node.media_uri poster
          register_media_file node, poster, 'image'
          poster_attr = %( poster="#{poster}")
        end

        %(<figure#{id_attr} class="video#{prepend_space node.role}#{prepend_space node.attr('float')}">#{title_element}
<div class="content">
<video src="#{target}#{time_anchor}"#{width_attr}#{height_attr}#{autoplay_attr}#{poster_attr}#{controls_attr}#{loop_attr}>
<div>Your Reading System does not support (this) video.</div>
</video>
</div>
</figure>)
      end

      # @param node [Asciidoctor::Block]
      # @return [String]
      def convert_image(node)
        target = node.image_uri node.attr 'target'
        register_media_file node, target, 'image'
        id_attr = node.id ? %( id="#{node.id}") : ''
        title_element = node.title? ? %(\n<figcaption>#{node.captioned_title}</figcaption>) : ''
        img_attrs = resolve_image_attrs node
        %(<figure#{id_attr} class="image#{prepend_space node.role}#{prepend_space node.attr('float')}">
<div class="content">
<img src="#{target}"#{prepend_space img_attrs * ' '} />
</div>#{title_element}
</figure>)
      end

      def get_enclosing_chapter(node)
        loop do
          return nil if node.nil?
          return node unless get_chapter_filename(node).nil?

          node = if node.instance_variable_defined?(PARENT_CELL_FIELD_NAME)
                   node.instance_variable_get(PARENT_CELL_FIELD_NAME)
                 else
                   node.parent
                 end
        end
      end

      def convert_inline_anchor(node)
        case node.type
        when :xref
          doc = node.document
          refid = node.attr('refid')
          target = node.target
          text = node.text
          id_attr = ''

          if (path = node.attributes['path'])
            # NOTE: non-nil path indicates this is an inter-document xref that's not included in current document
            text = node.text || path
          elsif refid == '#'
            logger.warn %(#{::File.basename doc.attr('docfile')}: <<chapter#>> xref syntax isn't supported anymore. Use either <<chapter>> or <<chapter#anchor>>)
          elsif refid
            ref = doc.references[:refs][refid]
            our_chapter = get_enclosing_chapter node
            ref_chapter = get_enclosing_chapter ref
            if ref_chapter
              ref_docname = get_chapter_filename ref_chapter
              if ref_chapter == our_chapter
                # ref within same chapter file
                id_attr = %( id="xref-#{refid}")
                target = %(##{refid})
              elsif refid == ref_docname
                # ref to top section of other chapter file
                id_attr = %( id="xref--#{refid}")
                target = %(#{refid}.xhtml)
              else
                # ref to section within other chapter file
                id_attr = %( id="xref--#{ref_docname}--#{refid}")
                target = %(#{ref_docname}.xhtml##{refid})
              end

              id_attr = '' unless @xrefs_seen.add? refid
              text ||= (ref.xreftext node.attr('xrefstyle', nil, true))
            else
              logger.warn %(#{::File.basename doc.attr('docfile')}: invalid reference to unknown anchor: #{refid})
            end
          end

          %(<a#{id_attr} href="#{target}" class="xref">#{text || "[#{refid}]"}</a>)
        when :ref
          # NOTE: id is used instead of target starting in Asciidoctor 2.0.0
          %(<a id="#{node.target || node.id}"></a>)
        when :link
          %(<a href="#{node.target}" class="link">#{node.text}</a>)
        when :bibref
          # NOTE: reftext is no longer enclosed in [] starting in Asciidoctor 2.0.0
          # NOTE id is used instead of target starting in Asciidoctor 2.0.0
          if (reftext = node.reftext)
            reftext = %([#{reftext}]) unless reftext.start_with? '['
          else
            reftext = %([#{node.target || node.id}])
          end
          %(<a id="#{node.target || node.id}"></a>#{reftext})
        else
          logger.warn %(unknown anchor type: #{node.type.inspect})
          nil
        end
      end

      def convert_inline_break(node)
        %(#{node.text}<br/>)
      end

      # @param node [Asciidoctor::Inline]
      # @return [String]
      def convert_inline_button(node)
        %(<b class="button">#{node.text}</b>)
      end

      def convert_inline_callout(node)
        num = CALLOUT_START_NUM
        int_num = node.text.to_i
        (int_num - 1).times { num = num.next }
        %(<i class="conum" data-value="#{int_num}">#{num}</i>)
      end

      # @param node [Asciidoctor::Inline]
      # @return [String]
      def convert_inline_footnote(node)
        if (index = node.attr 'index')
          attrs = []
          attrs << %(id="#{node.id}") if node.id

          %(<sup class="noteref">[<a#{prepend_space attrs * ' '}href="#note-#{index}" epub:type="noteref">#{index}</a>]</sup>)
        elsif node.type == :xref
          %(<mark class="noteref" title="Unresolved note reference">#{node.text}</mark>)
        end
      end

      def convert_inline_image(node)
        if node.type == 'icon'
          icon_names << (icon_name = node.target)
          i_classes = ['icon', %(i-#{icon_name})]
          i_classes << %(icon-#{node.attr 'size'}) if node.attr? 'size'
          i_classes << %(icon-flip-#{(node.attr 'flip')[0]}) if node.attr? 'flip'
          i_classes << %(icon-rotate-#{node.attr 'rotate'}) if node.attr? 'rotate'
          i_classes << node.role if node.role?
          i_classes << node.attr('float') if node.attr 'float'
          %(<i class="#{i_classes * ' '}"></i>)
        else
          target = node.image_uri node.target
          register_media_file node, target, 'image'

          img_attrs = resolve_image_attrs node
          img_attrs << %(class="inline#{prepend_space node.role}#{prepend_space node.attr('float')}")
          %(<img src="#{target}"#{prepend_space img_attrs * ' '}/>)
        end
      end

      def convert_inline_indexterm(node)
        node.type == :visible ? node.text : ''
      end

      def convert_inline_kbd(node)
        if (keys = node.attr 'keys').size == 1
          %(<kbd>#{keys[0]}</kbd>)
        else
          key_combo = keys.map { |key| %(<kbd>#{key}</kbd>) }.join '+'
          %(<span class="keyseq">#{key_combo}</span>)
        end
      end

      def convert_inline_menu(node)
        menu = node.attr 'menu'
        # NOTE: we swap right angle quote with chevron right from FontAwesome using CSS
        caret = %(#{NO_BREAK_SPACE}<span class="caret">#{RIGHT_ANGLE_QUOTE}</span> )
        if !(submenus = node.attr 'submenus').empty?
          submenu_path = submenus.map { |submenu| %(<span class="submenu">#{submenu}</span>#{caret}) }.join.chop
          %(<span class="menuseq"><span class="menu">#{menu}</span>#{caret}#{submenu_path} <span class="menuitem">#{node.attr 'menuitem'}</span></span>)
        elsif (menuitem = node.attr 'menuitem')
          %(<span class="menuseq"><span class="menu">#{menu}</span>#{caret}<span class="menuitem">#{menuitem}</span></span>)
        else
          %(<span class="menu">#{menu}</span>)
        end
      end

      def convert_inline_quoted(node)
        open, close, tag = QUOTE_TAGS[node.type]

        content = if node.type == :asciimath && asciimath_available?
                    AsciiMath.parse(node.text).to_mathml 'mml:'
                  else
                    node.text
                  end

        node.add_role 'literal' if %i[monospaced asciimath latexmath].include? node.type

        if node.id
          class_attr = class_string node
          if tag
            %(#{open.chop} id="#{node.id}"#{class_attr}>#{content}#{close})
          else
            %(<span id="#{node.id}"#{class_attr}>#{open}#{content}#{close}</span>)
          end
        elsif role_valid_class? node.role
          class_attr = class_string node
          if tag
            %(#{open.chop}#{class_attr}>#{content}#{close})
          else
            %(<span#{class_attr}>#{open}#{content}#{close}</span>)
          end
        else
          %(#{open}#{content}#{close})
        end
      end

      def output_content(node)
        node.content_model == :simple ? %(<p>#{node.content}</p>) : node.content
      end

      def encode_attribute_value(val)
        val.gsub '"', '&quot;'
      end

      # FIXME: merge into with xml_sanitize helper
      def xml_sanitize(value, target = :attribute)
        sanitized = value.include?('<') ? value.gsub(XML_ELEMENT_RX, '').strip.tr_s(' ', ' ') : value
        if target == :plain && (sanitized.include? ';')
          if sanitized.include? '&#'
            sanitized = sanitized.gsub(CHAR_ENTITY_RX) do
              [::Regexp.last_match(1).to_i].pack 'U*'
            end
          end
          sanitized = sanitized.gsub FROM_HTML_SPECIAL_CHARS_RX, FROM_HTML_SPECIAL_CHARS_MAP
        elsif target == :attribute
          sanitized = sanitized.gsub '"', '&quot;' if sanitized.include? '"'
        end
        sanitized
      end

      # TODO: make check for last content paragraph a feature of Asciidoctor
      def mark_last_paragraph(root)
        return unless (last_block = root.blocks[-1])

        last_block = last_block.blocks[-1] while last_block.context == :section && last_block.blocks?
        if last_block.context == :paragraph
          last_block.attributes['role'] = last_block.role? ? %(#{last_block.role} last) : 'last'
        end
        nil
      end

      # Prepend a space to the value if it's non-nil, otherwise return empty string.
      def prepend_space(value)
        value ? %( #{value}) : ''
      end

      def add_theme_assets(doc)
        workdir = if doc.attr? 'epub3-stylesdir'
                    stylesdir = doc.attr 'epub3-stylesdir'
                    # FIXME: make this work for Windows paths!!
                    if stylesdir.start_with? '/'
                      stylesdir
                    else
                      docdir = doc.attr 'docdir', '.'
                      docdir = '.' if docdir.empty?
                      ::File.join docdir, stylesdir
                    end
                  else
                    ::File.join DATA_DIR, 'styles'
                  end

        # TODO: improve design/UX of custom theme functionality, including custom fonts
        %w[epub3 epub3-css3-only].each do |f|
          css = load_css_file File.join(workdir, %(#{f}.scss))
          @book.add_item %(styles/#{f}.css), content: css.to_ios
        end

        syntax_hl = doc.syntax_highlighter
        if syntax_hl&.write_stylesheet? doc
          Dir.mktmpdir do |dir|
            syntax_hl.write_stylesheet doc, dir
            Pathname.glob("#{dir}/**/*").map do |filename|
              # Workaround for https://github.com/skoji/gepub/pull/117
              next unless filename.file?

              filename.open do |f|
                @book.add_item filename.basename.to_s, content: f
              end
            end
          end
        end

        font_files, font_css = select_fonts load_css_file(File.join(DATA_DIR, 'styles/epub3-fonts.scss')),
                                            (doc.attr 'scripts', 'latin')
        @book.add_item 'styles/epub3-fonts.css', content: font_css.to_ios
        unless font_files.empty?
          # NOTE: metadata property in oepbs package manifest doesn't work; must use proprietary iBooks file instead
          @book.add_optional_file 'META-INF/com.apple.ibooks.display-options.xml', '<?xml version="1.0" encoding="UTF-8"?>
<display_options>
<platform name="*">
<option name="specified-fonts">true</option>
</platform>
</display_options>'.to_ios

          font_files.each do |font_file|
            @book.add_item font_file, content: File.join(DATA_DIR, font_file)
          end
        end
        nil
      end

      # @param doc [Asciidoctor::Document]
      # @param name [String]
      # @return [GEPUB::Item, nil]
      def add_cover_page(doc, name)
        image_attr_name = %(#{name}-image)

        return nil if (image_path = doc.attr image_attr_name).nil?

        imagesdir = (doc.attr 'imagesdir', '.').chomp '/'
        imagesdir = (imagesdir == '.' ? '' : %(#{imagesdir}/))

        image_attrs = {}
        if (image_path.include? ':') && image_path =~ IMAGE_MACRO_RX
          logger.warn %(deprecated block macro syntax detected in :#{image_attr_name}: attribute) if image_path.start_with? 'image::'
          image_path = %(#{imagesdir}#{::Regexp.last_match(1)})
          unless ::Regexp.last_match(2).empty?
            (::Asciidoctor::AttributeList.new ::Regexp.last_match(2)).parse_into image_attrs,
                                                                                 %w[alt width
                                                                                    height]
          end
        end

        image_href = %(#{imagesdir}jacket/#{name}#{::File.extname image_path})

        workdir = doc.attr 'docdir'
        workdir = '.' if workdir.nil_or_empty?

        image_path = File.join workdir, image_path unless File.absolute_path? image_path

        begin
          @book.add_item(image_href, content: image_path).cover_image
        rescue StandardError => e
          logger.error %(#{::File.basename doc.attr('docfile')}: error adding cover image. Make sure that :#{image_attr_name}: attribute points to a valid image file. #{e})
          return nil
        end

        unless !image_attrs.empty? && (width = image_attrs['width']) && (height = image_attrs['height'])
          width = 1050
          height = 1600
        end

        # NOTE: SVG wrapper maintains aspect ratio and confines image to view box
        content = %(<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<head>
<title>#{sanitize_doctitle_xml doc, :cdata}</title>
<style type="text/css">
@page {
  margin: 0;
}
html {
  margin: 0 !important;
  padding: 0 !important;
}
body {
  margin: 0;
  padding: 0 !important;
  text-align: center;
}
body > svg {
  /* prevent bleed onto second page (removes descender space) */
  display: block;
}
</style>
</head>
<body epub:type="cover"><svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
  width="100%" height="100%" viewBox="0 0 #{width} #{height}" preserveAspectRatio="xMidYMid meet">
<image width="#{width}" height="#{height}" xlink:href="#{image_href}"/>
</svg></body>
</html>)

        @book.add_ordered_item %(#{name}.xhtml), content: content.to_ios, id: name
      end

      def get_frontmatter_files(doc, workdir)
        if doc.attr? 'epub3-frontmatterdir'
          fmdir = doc.attr 'epub3-frontmatterdir'
          fmglob = 'front-matter.*\.html'
          fm_path = File.join workdir, fmdir
          unless Dir.exist? fm_path
            logger.warn %(#{File.basename doc.attr('docfile')}: directory specified by 'epub3-frontmattderdir' doesn't exist! Ignoring ...)
            return []
          end
          fms = Dir.entries(fm_path).delete_if { |x| !x.match fmglob }.sort.map { |y| File.join fm_path, y }
          if fms && !fms.empty?
            fms
          else
            logger.warn %(#{File.basename doc.attr('docfile')}: directory specified by 'epub3-frontmattderdir' contains no suitable files! Ignoring ...)
            []
          end
        elsif File.exist? File.join workdir, 'front-matter.html'
          [File.join(workdir, 'front-matter.html')]
        else
          []
        end
      end

      def add_front_matter_page(doc)
        workdir = doc.attr 'docdir'
        workdir = '.' if workdir.nil_or_empty?

        result = nil
        get_frontmatter_files(doc, workdir).each do |front_matter|
          front_matter_content = ::File.read front_matter

          front_matter_file = File.basename front_matter, '.html'
          item = @book.add_ordered_item "#{front_matter_file}.xhtml", content: front_matter_content.to_ios
          item.add_property 'svg' if SVG_IMG_SNIFF_RX =~ front_matter_content
          # Store link to first frontmatter page
          result = item if result.nil?

          front_matter_content.scan IMAGE_SRC_SCAN_RX do
            @book.add_item ::Regexp.last_match(1),
                           content: File.join(File.dirname(front_matter), ::Regexp.last_match(1))
          end
        end

        result
      end

      def add_profile_images(doc, usernames)
        imagesdir = (doc.attr 'imagesdir', '.').chomp '/'
        imagesdir = (imagesdir == '.' ? nil : %(#{imagesdir}/))

        @book.add_item %(#{imagesdir}avatars/default.jpg), content: ::File.join(DATA_DIR, 'images/default-avatar.jpg')
        @book.add_item %(#{imagesdir}headshots/default.jpg),
                       content: ::File.join(DATA_DIR, 'images/default-headshot.jpg')

        workdir = '.' if (workdir = doc.attr 'docdir').nil_or_empty?

        usernames.each do |username|
          avatar = %(#{imagesdir}avatars/#{username}.jpg)
          if ::File.readable?(resolved_avatar = (::File.join workdir, avatar))
            @book.add_item avatar, content: resolved_avatar
          else
            logger.error %(avatar for #{username} not found or readable: #{avatar}; falling back to default avatar)
            @book.add_item avatar, content: ::File.join(DATA_DIR, 'images/default-avatar.jpg')
          end

          headshot = %(#{imagesdir}headshots/#{username}.jpg)
          if ::File.readable?(resolved_headshot = (::File.join workdir, headshot))
            @book.add_item headshot, content: resolved_headshot
          elsif doc.attr? 'builder', 'editions'
            logger.error %(headshot for #{username} not found or readable: #{headshot}; falling back to default headshot)
            @book.add_item headshot, content: ::File.join(DATA_DIR, 'images/default-headshot.jpg')
          end
        end
        nil
      end

      def nav_doc(doc, items, landmarks, depth)
        lines = [%(<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang = doc.attr 'lang',
                                                                                                                 'en'}" lang="#{lang}">
<head>
<title>#{sanitize_doctitle_xml doc, :cdata}</title>
<link rel="stylesheet" type="text/css" href="styles/epub3.css"/>
<link rel="stylesheet" type="text/css" href="styles/epub3-css3-only.css" media="(min-device-width: 0px)"/>
</head>
<body>
<section class="chapter">
<header class="chapter-header">
<h1 class="chapter-title"><small class="subtitle">#{doc.attr 'toc-title'}</small></h1>
</header>
<nav epub:type="toc" id="toc">)]
        lines << (nav_level items, [depth, 0].max)
        lines << '</nav>'

        unless landmarks.empty?
          lines << '
<nav epub:type="landmarks" id="landmarks" hidden="hidden">
<ol>'
          landmarks.each do |landmark|
            lines << %(<li><a epub:type="#{landmark[:type]}" href="#{landmark[:href]}">#{landmark[:title]}</a></li>)
          end
          lines << '
</ol>
</nav>'
        end
        lines << '
</section>
</body>
</html>'
        lines * LF
      end

      def nav_level(items, depth, state = {})
        lines = []
        lines << '<ol>'
        items.each do |item|
          # index = (state[:index] = (state.fetch :index, 0) + 1)
          if (chapter_filename = get_chapter_filename item).nil?
            item_label = sanitize_xml get_numbered_title(item), :pcdata
            item_href = %(#{state[:content_doc_href]}##{item.id})
          else
            # NOTE: we sanitize the chapter titles because we use formatting to control layout
            item_label = if item.context == :document
                           sanitize_doctitle_xml item, :cdata
                         else
                           sanitize_xml get_numbered_title(item), :cdata
                         end
            item_href = (state[:content_doc_href] = %(#{chapter_filename}.xhtml))
          end
          lines << %(<li><a href="#{item_href}">#{item_label}</a>)
          if depth.zero? || (child_sections = item.sections).empty?
            lines[-1] = %(#{lines[-1]}</li>)
          else
            lines << (nav_level child_sections, depth - 1, state)
            lines << '</li>'
          end
          state.delete :content_doc_href unless chapter_filename.nil?
        end
        lines << '</ol>'
        lines * LF
      end

      def ncx_doc(doc, items, depth)
        # TODO: populate docAuthor element based on unique authors in work
        lines = [%(<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="#{doc.attr 'lang', 'en'}">
<head>
<meta name="dtb:uid" content="#{@book.identifier}"/>
%<depth>s
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>#{sanitize_doctitle_xml doc, :cdata}</text></docTitle>
<navMap>)]
        lines << (ncx_level items, depth, state = {})
        lines[0] = lines[0].sub '%<depth>s', %(<meta name="dtb:depth" content="#{state[:max_depth]}"/>)
        lines << %(</navMap>
</ncx>)
        lines * LF
      end

      def ncx_level(items, depth, state = {})
        lines = []
        state[:max_depth] = (state.fetch :max_depth, 0) + 1
        items.each do |item|
          index = (state[:index] = (state.fetch :index, 0) + 1)
          item_id = %(nav_#{index})
          if (chapter_filename = get_chapter_filename item).nil?
            item_label = sanitize_xml get_numbered_title(item), :cdata
            item_href = %(#{state[:content_doc_href]}##{item.id})
          else
            item_label = if item.context == :document
                           sanitize_doctitle_xml item, :cdata
                         else
                           sanitize_xml get_numbered_title(item), :cdata
                         end
            item_href = (state[:content_doc_href] = %(#{chapter_filename}.xhtml))
          end
          lines << %(<navPoint id="#{item_id}" playOrder="#{index}">)
          lines << %(<navLabel><text>#{item_label}</text></navLabel>)
          lines << %(<content src="#{item_href}"/>)
          unless depth.zero? || (child_sections = item.sections).empty?
            lines << (ncx_level child_sections, depth - 1, state)
          end
          lines << %(</navPoint>)
          state.delete :content_doc_href unless chapter_filename.nil?
        end
        lines * LF
      end

      # Swap fonts in CSS based on the value of the document attribute 'scripts',
      # then return the list of fonts as well as the font CSS.
      def select_fonts(font_css, scripts = 'latin')
        font_css = font_css.gsub(/(?<=-)latin(?=\.ttf\))/, scripts) unless scripts == 'latin'

        # match CSS font urls in the forms of:
        # src: url(../fonts/notoserif-regular-latin.ttf);
        # src: url(../fonts/notoserif-regular-latin.ttf) format("truetype");
        font_list = font_css.scan(%r{url\(\.\./([^)]+?\.ttf)\)}).flatten

        [font_list, font_css]
      end

      def load_css_file(filename)
        template = File.read filename
        load_paths = [File.dirname(filename)]
        sass_engine = Sass::Engine.new template, syntax: :scss, cache: false, load_paths: load_paths, style: :compressed
        sass_engine.render
      end

      def build_epubcheck_command
        unless @epubcheck_path.nil?
          logger.debug %(Using ebook-epubcheck-path attribute: #{@epubcheck_path})
          return [@epubcheck_path]
        end

        unless (result = ENV.fetch('EPUBCHECK', nil)).nil?
          logger.debug %(Using EPUBCHECK env variable: #{result})
          return [result]
        end

        begin
          result = ::Gem.bin_path 'epubcheck-ruby', 'epubcheck'
          logger.debug %(Using EPUBCheck from gem: #{result})
          [::Gem.ruby, result]
        rescue ::Gem::Exception => e
          logger.debug %(#{e}; Using EPUBCheck from PATH)
          ['epubcheck']
        end
      end

      def validate_epub(epub_file)
        argv = build_epubcheck_command + ['-w', epub_file]
        begin
          out, err, res = Open3.capture3(*argv)
        rescue Errno::ENOENT => e
          raise 'Unable to run EPUBCheck. Either install epubcheck-ruby gem or place `epubcheck` executable on PATH or set EPUBCHECK environment variable with path to it',
                cause: e
        end

        out.each_line do |line|
          logger.info line
        end
        err.each_line do |line|
          log_line line
        end

        logger.error %(EPUB validation failed: #{epub_file}) unless res.success?
      end

      def log_line(line)
        line = line.strip

        case line
        when /^fatal/i
          logger.fatal line
        when /^error/i
          logger.error line
        when /^warning/i
          logger.warn line
        else
          logger.info line
        end
      end

      private

      def class_string(node)
        role = node.role

        return '' unless role_valid_class? role

        %( class="#{role}")
      end

      # Handles asciidoctor 1.5.6 quirk when role can be parent
      def role_valid_class?(role)
        role.is_a? String
      end
    end

    Extensions.register do
      if (document = @document).backend == 'epub3'
        document.set_attribute 'listing-caption', 'Listing'

        # TODO: bw theme for CodeRay
        document.set_attribute 'pygments-style', 'bw' unless document.attr? 'pygments-style'
        document.set_attribute 'rouge-style', 'bw' unless document.attr? 'rouge-style'

        # Backward compatibility for documents that were created before we dropped MOBI support
        document.set_attribute 'ebook-format', 'epub3'
        document.set_attribute 'ebook-format-epub3', ''

        # Enable generation of section ids because we use them for chapter filenames
        document.set_attribute 'sectids'
        treeprocessor do
          process do |doc|
            # :sectids: doesn't generate id for top-level section (why?), do it manually
            doc.id = Section.generate_id(doc.first_section&.title || doc.attr('docname') || 'document', doc) if doc.id.nil_or_empty?

            if (preamble = doc.blocks[0]) && preamble.context == :preamble && preamble.id.nil_or_empty?
              # :sectids: doesn't generate id for preamble (because it is not a section), do it manually
              preamble.id = Section.generate_id(preamble.title || 'preamble', doc)
            end

            nil
          end
        end
      end
    end
  end
end
