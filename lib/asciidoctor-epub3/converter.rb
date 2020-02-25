# frozen_string_literal: true

require 'open3'
require_relative 'font_icon_map'

module Asciidoctor
  module Epub3
    # Public: The main converter for the epub3 backend that handles packaging the
    # EPUB3 or KF8 publication file.
    class Converter
      include ::Asciidoctor::Converter
      include ::Asciidoctor::Logging
      include ::Asciidoctor::Writer

      register_for 'epub3'

      def write output, target
        epub_file = @format == :kf8 ? %(#{::Asciidoctor::Helpers.rootname target}-kf8.epub) : target
        output.generate_epub epub_file
        logger.debug %(Wrote #{@format.upcase} to #{epub_file})
        if @extract
          extract_dir = epub_file.sub EpubExtensionRx, ''
          ::FileUtils.remove_dir extract_dir if ::File.directory? extract_dir
          ::Dir.mkdir extract_dir
          ::Dir.chdir extract_dir do
            ::Zip::File.open epub_file do |entries|
              entries.each do |entry|
                next unless entry.file?
                unless (entry_dir = ::File.dirname entry.name) == '.' || (::File.directory? entry_dir)
                  ::FileUtils.mkdir_p entry_dir
                end
                entry.extract
              end
            end
          end
          logger.debug %(Extracted #{@format.upcase} to #{extract_dir})
        end

        if @format == :kf8
          # QUESTION shouldn't we validate this epub file too?
          distill_epub_to_mobi epub_file, target, @compress, @kindlegen_path
        elsif @validate
          validate_epub epub_file, @epubcheck_path
        end
      end

      CsvDelimiterRx = /\s*,\s*/

      DATA_DIR = ::File.expand_path ::File.join(__dir__, '..', '..', 'data')
      ImageMacroRx = /^image::?(.*?)\[(.*?)\]$/
      ImgSrcScanRx = /<img src="(.+?)"/
      SvgImgSniffRx = /<img src=".+?\.svg"/

      LF = ?\n
      NoBreakSpace = '&#xa0;'
      RightAngleQuote = '&#x203a;'
      CalloutStartNum = %(\u2460)

      CharEntityRx = /&#(\d{2,6});/
      XmlElementRx = /<\/?.+?>/
      TrailingPunctRx = /[[:punct:]]$/

      FromHtmlSpecialCharsMap = {
        '&lt;' => '<',
        '&gt;' => '>',
        '&amp;' => '&',
      }

      FromHtmlSpecialCharsRx = /(?:#{FromHtmlSpecialCharsMap.keys * '|'})/

      ToHtmlSpecialCharsMap = {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
      }

      ToHtmlSpecialCharsRx = /[#{ToHtmlSpecialCharsMap.keys.join}]/

      EpubExtensionRx = /\.epub$/i
      KindlegenCompression = ::Hash['0', '-c0', '1', '-c1', '2', '-c2', 'none', '-c0', 'standard', '-c1', 'huffdic', '-c2']

      (QUOTE_TAGS = {
        monospaced: ['<code>', '</code>', true],
        emphasis: ['<em>', '</em>', true],
        strong: ['<strong>', '</strong>', true],
        double: ['“', '”'],
        single: ['‘', '’'],
        mark: ['<mark>', '</mark>', true],
        superscript: ['<sup>', '</sup>', true],
        subscript: ['<sub>', '</sub>', true],
        asciimath: ['<code>', '</code>', true],
        latexmath: ['<code>', '</code>', true],
      }).default = ['', '']

      def initialize backend, opts = {}
        super
        basebackend 'html'
        outfilesuffix '.epub' # dummy outfilesuffix since it may be .mobi
        htmlsyntax 'xml'
      end

      def convert node, name = nil, _opts = {}
        method_name = %(convert_#{name ||= node.node_name})
        if respond_to? method_name
          send method_name, node
        else
          logger.warn %(conversion missing in backend #{@backend} for #{name})
        end
      end

      def convert_document node
        @format = node.attr('ebook-format').to_sym

        @validate = node.attr? 'ebook-validate'
        @extract = node.attr? 'ebook-extract'
        @compress = node.attr 'ebook-compress'
        @kindlegen_path = node.attr 'ebook-kindlegen-path'
        @epubcheck_path = node.attr 'ebook-epubcheck-path'
        @xrefs_seen = ::Set.new
        @in_chapter = false
        @icon_names = []
        @images = []
        @footnotes = []

        @book = GEPUB::Book.new 'EPUB/package.opf'
        @book.epub_backward_compat = @format != :kf8
        @book.language node.attr('lang', 'en'), id: 'pub-language'

        if node.attr? 'uuid'
          @book.primary_identifier node.attr('uuid'), 'pub-identifier', 'uuid'
        else
          @book.primary_identifier node.id, 'pub-identifier', 'uuid'
        end
        # replace with next line once the attributes argument is supported
        #unique_identifier doc.id, 'pub-id', 'uuid', 'scheme' => 'xsd:string'

        # NOTE we must use :plain_text here since gepub reencodes
        @book.add_title sanitize_doctitle_xml(node, :plain_text), id: 'pub-title'

        # see https://www.w3.org/publishing/epub3/epub-packages.html#sec-opf-dccreator
        (1..(node.attr 'authorcount', 1).to_i).map do |idx|
          author = node.attr(idx == 1 ? 'author' : %(author_#{idx}))
          @book.add_creator author, role: 'aut' unless author.nil_or_empty?
        end

        publisher = node.attr 'publisher'
        # NOTE Use producer as both publisher and producer if publisher isn't specified
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

        (node.attr 'keywords', '').split(CsvDelimiterRx).each do |s|
          @book.metadata.add_metadata 'subject', s
        end

        add_cover_image node
        add_front_matter_page node

        if node.doctype == 'book'
          toc_items = []
          node.sections.each do |section|
            # Mark top-level sections as separate chapter files
            section.set_attr 'ebook-chapter', section.id
            toc_items << section
            section.sections.each do |subsection|
              # See https://asciidoctor.org/docs/user-manual/#book-parts-and-chapters
              next if subsection.level > 1
              subsection.set_attr 'ebook-chapter', subsection.id
              toc_items << subsection
            end
          end
          # Mark preamble as chapter (if it exists)
          node.blocks[0].set_attr 'ebook-chapter', (node.blocks[0].id || 'preamble') if !node.blocks.empty? && node.blocks[0].context == :preamble
          node.content
        else
          toc_items = [node]
          node.set_attr 'ebook-chapter', node.attr('docname')
          add_chapter node
        end

        nav_xhtml = @book.add_item 'nav.xhtml', content: postprocess_xhtml(nav_doc(node, toc_items)), id: 'nav'
        nav_xhtml.nav

        # NOTE gepub doesn't support building a ncx TOC with depth > 1, so do it ourselves
        toc_ncx = ncx_doc node, toc_items
        @book.add_item 'toc.ncx', content: toc_ncx.to_ios, id: 'ncx'

        docimagesdir = (node.attr 'imagesdir', '.').chomp '/'
        docimagesdir = (docimagesdir == '.' ? nil : %(#{docimagesdir}/))

        @images.each do |image|
          if image[:name].start_with? %(#{docimagesdir}jacket/cover.)
            logger.warn %(image path is reserved for cover artwork: #{image[:name]}; skipping image found in content)
          elsif ::File.readable? image[:path]
            @book.add_item image[:name], content: image[:path]
          else
            logger.error %(#{File.basename node.attr('docfile')}: image not found or not readable: #{image[:path]})
          end
        end

        #add_metadata 'ibooks:specified-fonts', true

        add_theme_assets node
        if node.doctype != 'book'
          usernames = [node].map {|item| item.attr 'username' }.compact.uniq
          add_profile_images node, usernames
        end

        @book
      end

      # FIXME: move to Asciidoctor::Helpers
      def sanitize_doctitle_xml doc, content_spec
        doctitle = doc.doctitle use_fallback: true
        sanitize_xml doctitle, content_spec
      end

      # FIXME: move to Asciidoctor::Helpers
      def sanitize_xml content, content_spec
        if content_spec != :pcdata && (content.include? '<')
          if (content = (content.gsub XmlElementRx, '').strip).include? ' '
            content = content.tr_s ' ', ' '
          end
        end

        case content_spec
        when :attribute_cdata
          content = content.gsub '"', '&quot;' if content.include? '"'
        when :cdata, :pcdata
          # noop
        when :plain_text
          if content.include? ';'
            content = content.gsub(CharEntityRx) { [$1.to_i].pack 'U*' } if content.include? '&#'
            content = content.gsub FromHtmlSpecialCharsRx, FromHtmlSpecialCharsMap
          end
        else
          raise ::ArgumentError, %(Unknown content spec: #{content_spec})
        end
        content
      end

      def add_chapter node
        docid = node.attr 'ebook-chapter'
        chapter_item = @book.add_ordered_item %(#{docid}.xhtml)

        if node.context == :document && (doctitle = node.doctitle partition: true, use_fallback: true).subtitle?
          title = %(#{doctitle.main} )
          subtitle = doctitle.subtitle
        elsif node.title
          # HACK: until we get proper handling of title-only in CSS
          title = ''
          subtitle = node.title
        else
          title = nil
          subtitle = nil
        end

        doctitle_sanitized = (node.document.doctitle sanitize: true, use_fallback: true).to_s

        # By default, Kindle does not allow the line height to be adjusted.
        # But if you float the elements, then the line height disappears and can be restored manually using margins.
        # See https://github.com/asciidoctor/asciidoctor-epub3/issues/123
        subtitle_formatted = subtitle ? subtitle.split.map {|w| %(<b>#{w}</b>) } * ' ' : nil

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

        # NOTE must run after content is resolved
        # TODO perhaps create dynamic CSS file?
        if @icon_names.empty?
          icon_css_head = ''
        else
          icon_defs = @icon_names.map {|name|
            %(.i-#{name}::before { content: "#{FontIconMap.unicode name}"; })
          } * LF
          icon_css_head = %(<style>
#{icon_defs}
</style>
)
        end

        header = (title || subtitle) ? %(<header>
<div class="chapter-header">
#{byline}<h1 class="chapter-title">#{title}#{subtitle ? %(<small class="subtitle">#{subtitle_formatted}</small>) : ''}</h1>
</div>
</header>) : ''

        # NOTE kindlegen seems to mangle the <header> element, so we wrap its content in a div
        lines = [%(<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang = node.document.attr 'lang', 'en'}" lang="#{lang}">
<head>
<meta charset="UTF-8"/>
<title>#{doctitle_sanitized}</title>
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
]]></script>
</head>
<body>
<section class="chapter" title="#{doctitle_sanitized.gsub '"', '&quot;'}" epub:type="chapter" id="#{docid}">
#{header}
#{content})]

        unless (fns = node.document.footnotes - @footnotes).empty?
          @footnotes += fns

          # NOTE kindlegen seems to mangle the <footer> element, so we wrap its content in a div
          lines << '<footer>
<div class="chapter-footer">
<div class="footnotes">'
          fns.each do |footnote|
            lines << %(<aside id="note-#{footnote.index}" epub:type="footnote">
<p><sup class="noteref"><a href="#noteref-#{footnote.index}">#{footnote.index}</a></sup> #{footnote.text}</p>
</aside>)
          end
          lines << '</div>
</div>
</footer>'
        end

        lines << '</section>
</body>
</html>'

        chapter_item.add_content postprocess_xhtml lines * LF
        epub_properties = node.attr 'epub-properties'
        chapter_item.add_property 'svg' if epub_properties&.include? 'svg'

        # # QUESTION reenable?
        # #linear 'yes' if i == 0
      end

      def convert_section node
        if node.attr? 'ebook-chapter'
          add_chapter node
        else
          hlevel = node.level
          epub_type_attr = node.special ? %( epub:type="#{node.sectname}") : ''
          div_classes = [%(sect#{node.level}), node.role].compact
          title = node.title
          title_sanitized = xml_sanitize title
          %(<section class="#{div_classes * ' '}" title="#{title_sanitized}"#{epub_type_attr}>
<h#{hlevel} id="#{node.id}">#{title}</h#{hlevel}>#{(content = node.content).empty? ? '' : %(
          #{content})}
</section>)
        end
      end

      # NOTE embedded is used for AsciiDoc table cell content
      def convert_embedded node
        node.content
      end

      # TODO: support use of quote block as abstract
      def convert_preamble node
        if @in_chapter
          if (first_block = node.blocks[0]) && first_block.style == 'abstract'
            convert_abstract first_block
            # REVIEW: should we treat the preamble as an abstract in general?
          elsif first_block && node.blocks.size == 1
            convert_abstract first_block
          else
            node.content
          end
        else
          # TODO: we're bypassing `convert_abstract` here
          add_chapter node
        end
      end

      def convert_open node
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

      def convert_abstract node
        %(<div class="abstract" epub:type="preamble">
#{output_content node}
</div>)
      end

      def convert_paragraph node
        role = node.role
        # stack-head is the alternative to the default, inline-head (where inline means "run-in")
        head_stop = node.attr 'head-stop', (role && (node.has_role? 'stack-head') ? nil : '.')
        head = node.title? ? %(<strong class="head">#{title = node.title}#{head_stop && title !~ TrailingPunctRx ? head_stop : ''}</strong> ) : ''
        if role
          node.set_option 'hardbreaks' if node.has_role? 'signature'
          %(<p class="#{role}">#{head}#{node.content}</p>)
        else
          %(<p>#{head}#{node.content}</p>)
        end
      end

      def convert_pass node
        content = node.content
        if content == '<?hard-pagebreak?>'
          '<hr epub:type="pagebreak" class="pagebreak"/>'
        else
          content
        end
      end

      def convert_admonition node
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
                      'help'
                    when 'note'
                      'note'
                    when 'important', 'warning', 'caution'
                      'warning'
                    else
                      logger.warn %(unknown admonition type: #{type})
                      'note'
                    end
        %(<aside#{id_attr} class="admonition #{type}"#{title_attr} epub:type="#{epub_type}">
#{title_el}<div class="content">
#{output_content node}
</div>
</aside>)
      end

      def convert_example node
        id_attr = node.id ? %( id="#{node.id}") : ''
        title_div = node.title? ? %(<div class="example-title">#{node.title}</div>
) : ''
        %(<div#{id_attr} class="example">
#{title_div}<div class="example-content">
#{output_content node}
</div>
</div>)
      end

      def convert_floating_title node
        tag_name = %(h#{node.level + 1})
        id_attribute = node.id ? %( id="#{node.id}") : ''
        %(<#{tag_name}#{id_attribute} class="#{['discrete', node.role].compact * ' '}">#{node.title}</#{tag_name}>)
      end

      def convert_listing node
        figure_classes = ['listing']
        figure_classes << 'coalesce' if node.option? 'unbreakable'
        pre_classes = node.style == 'source' ? ['source', %(language-#{node.attr 'language'})] : ['screen']
        title_div = node.title? ? %(<figcaption>#{node.captioned_title}</figcaption>
) : ''
        %(<figure class="#{figure_classes * ' '}">
#{title_div}<pre class="#{pre_classes * ' '}"><code>#{node.content}</code></pre>
</figure>)
      end

      # TODO: implement proper stem support. See https://github.com/asciidoctor/asciidoctor-epub3/issues/10
      alias convert_stem convert_listing

      # QUESTION should we wrap the <pre> in either <div> or <figure>?
      def convert_literal node
        %(<pre class="screen">#{node.content}</pre>)
      end

      def convert_page_break _node
        '<hr epub:type="pagebreak" class="pagebreak"/>'
      end

      def convert_thematic_break _node
        '<hr class="thematicbreak"/>'
      end

      def convert_quote node
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

        footer_tag = footer_content.empty? ? '' : %(
<footer>~ #{footer_content * ' '}</footer>)
        content = (output_content node).strip
        %(<div#{id_attr}#{class_attr}>
<blockquote>
#{content}#{footer_tag}
</blockquote>
</div>)
      end

      def convert_verse node
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

        footer_tag = !footer_content.empty? ? %(
<span class="attribution">~ #{footer_content * ', '}</span>) : ''
        %(<div#{id_attr}#{class_attr}>
<pre>#{node.content}#{footer_tag}</pre>
</div>)
      end

      def convert_sidebar node
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

        %(<aside class="#{classes * ' '}"#{title_attr} epub:type="sidebar">
#{title_el}<div class="content">
#{output_content node}
</div>
</aside>)
      end

      def convert_table node
        lines = [%(<div class="table">)]
        lines << %(<div class="content">)
        table_id_attr = node.id ? %( id="#{node.id}") : ''
        frame_class = {
          'all' => 'table-framed',
          'topbot' => 'table-framed-topbot',
          'sides' => 'table-framed-sides',
          'none' => '',
        }
        grid_class = {
          'all' => 'table-grid',
          'rows' => 'table-grid-rows',
          'cols' => 'table-grid-cols',
          'none' => '',
        }
        table_classes = %W[table #{frame_class[node.attr 'frame'] || frame_class['topbot']} #{grid_class[node.attr 'grid'] || grid_class['rows']}]
        if (role = node.role)
          table_classes << role
        end
        table_class_attr = %( class="#{table_classes * ' '}")
        table_styles = []
        table_styles << %(width: #{node.attr 'tablepcwidth'}%) unless (node.option? 'autowidth') && !(node.attr? 'width', nil, false)
        table_style_attr = !table_styles.empty? ? %( style="#{table_styles * '; '}") : ''

        lines << %(<table#{table_id_attr}#{table_class_attr}#{table_style_attr}>)
        lines << %(<caption>#{node.captioned_title}</caption>) if node.title?
        if (node.attr 'rowcount') > 0
          lines << '<colgroup>'
          #if node.option? 'autowidth'
          tag = %(<col/>)
          node.columns.size.times do
            lines << tag
          end
          #else
          #  node.columns.each do |col|
          #    lines << %(<col style="width: #{col.attr 'colpcwidth'}%"/>)
          #  end
          #end
          lines << '</colgroup>'
          [:head, :body, :foot].reject {|tsec| node.rows[tsec].empty? }.each do |tsec|
            lines << %(<t#{tsec}>)
            node.rows[tsec].each do |row|
              lines << '<tr>'
              row.each do |cell|
                if tsec == :head
                  cell_content = cell.text
                else
                  case cell.style
                  when :asciidoc
                    cell_content = %(<div class="embed">#{cell.content}</div>)
                  when :verse
                    cell_content = %(<div class="verse">#{cell.text}</div>)
                  when :literal
                    cell_content = %(<div class="literal"><pre>#{cell.text}</pre></div>)
                  else
                    cell_content = ''
                    cell.content.each do |text|
                      cell_content = %(#{cell_content}<p>#{text}</p>)
                    end
                  end
                end

                cell_tag_name = tsec == :head || cell.style == :header ? 'th' : 'td'
                cell_classes = []
                if (halign = cell.attr 'halign') && halign != 'left'
                  cell_classes << 'halign-left'
                end
                if (halign = cell.attr 'valign') && halign != 'top'
                  cell_classes << 'valign-top'
                end
                cell_class_attr = !cell_classes.empty? ? %( class="#{cell_classes * ' '}") : ''
                cell_colspan_attr = cell.colspan ? %( colspan="#{cell.colspan}") : ''
                cell_rowspan_attr = cell.rowspan ? %( rowspan="#{cell.rowspan}") : ''
                cell_style_attr = (node.document.attr? 'cellbgcolor') ? %( style="background-color: #{node.document.attr 'cellbgcolor'}") : ''
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

      def convert_colist node
        lines = ['<div class="callout-list">
<ol>']
        num = CalloutStartNum
        node.items.each_with_index do |item, i|
          lines << %(<li><i class="conum" data-value="#{i + 1}">#{num}</i> #{item.text}</li>)
          num = num.next
        end
        lines << '</ol>
</div>'
      end

      # TODO: add complex class if list has nested blocks
      def convert_dlist node
        lines = []
        case (style = node.style)
        when 'itemized', 'ordered'
          list_tag_name = style == 'itemized' ? 'ul' : 'ol'
          role = node.role
          subject_stop = node.attr 'subject-stop', (role && (node.has_role? 'stack') ? nil : ':')
          # QUESTION should we just use itemized-list and ordered-list as the class here? or just list?
          div_classes = [%(#{style}-list), role].compact
          list_class_attr = (node.option? 'brief') ? ' class="brief"' : ''
          lines << %(<div class="#{div_classes * ' '}">
<#{list_tag_name}#{list_class_attr}#{list_tag_name == 'ol' && (node.option? 'reversed') ? ' reversed="reversed"' : ''}>)
          node.items.each do |subjects, dd|
            # consists of one term (a subject) and supporting content
            subject = [*subjects].first.text
            subject_plain = xml_sanitize subject, :plain
            subject_element = %(<strong class="subject">#{subject}#{subject_stop && subject_plain !~ TrailingPunctRx ? subject_stop : ''}</strong>)
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
          lines << %(</#{list_tag_name}>
</div>)
        else
          lines << '<div class="description-list">
<dl>'
          node.items.each do |terms, dd|
            [*terms].each do |dt|
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
          lines << '</dl>
</div>'
        end
        lines * LF
      end

      def convert_olist node
        complex = false
        div_classes = ['ordered-list', node.style, node.role].compact
        ol_classes = [node.style, ((node.option? 'brief') ? 'brief' : nil)].compact
        ol_class_attr = ol_classes.empty? ? '' : %( class="#{ol_classes * ' '}")
        ol_start_attr = (node.attr? 'start') ? %( start="#{node.attr 'start'}") : ''
        id_attribute = node.id ? %( id="#{node.id}") : ''
        lines = [%(<div#{id_attribute} class="#{div_classes * ' '}">)]
        lines << %(<h3 class="list-heading">#{node.title}</h3>) if node.title?
        lines << %(<ol#{ol_class_attr}#{ol_start_attr}#{(node.option? 'reversed') ? ' reversed="reversed"' : ''}>)
        node.items.each do |item|
          lines << %(<li>
<span class="principal">#{item.text}</span>)
          if item.blocks?
            lines << item.content
            complex = true unless item.blocks.size == 1 && ::Asciidoctor::List === item.blocks[0]
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

      def convert_ulist node
        complex = false
        div_classes = ['itemized-list', node.style, node.role].compact
        ul_classes = [node.style, ((node.option? 'brief') ? 'brief' : nil)].compact
        ul_class_attr = ul_classes.empty? ? '' : %( class="#{ul_classes * ' '}")
        id_attribute = node.id ? %( id="#{node.id}") : ''
        lines = [%(<div#{id_attribute} class="#{div_classes * ' '}">)]
        lines << %(<h3 class="list-heading">#{node.title}</h3>) if node.title?
        lines << %(<ul#{ul_class_attr}>)
        node.items.each do |item|
          lines << %(<li>
<span class="principal">#{item.text}</span>)
          if item.blocks?
            lines << item.content
            complex = true unless item.blocks.size == 1 && ::Asciidoctor::List === item.blocks[0]
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

      def doc_option document, key
        loop do
          value = document.options[key]
          return value unless value.nil?
          document = document.parent_document
          break if document.nil?
        end
        nil
      end

      def root_document document
        document = document.parent_document until document.parent_document.nil?
        document
      end

      def register_image node, target
        if target.end_with? '.svg'
          chapter = get_enclosing_chapter node
          chapter.set_attr 'epub-properties', [] unless chapter.attr? 'epub-properties'
          epub_properties = chapter.attr 'epub-properties'
          epub_properties << 'svg' unless epub_properties.include? 'svg'
        end

        out_dir = node.attr('outdir', nil, true) || doc_option(node.document, :to_dir)
        fs_path = (::File.join out_dir, target)
        unless ::File.exist? fs_path
          base_dir = root_document(node.document).base_dir
          fs_path = ::File.join base_dir, target
        end
        # We need *both* virtual and physical image paths. Unfortunately, references[:images] only has one of them.
        @images << { name: target, path: fs_path }
      end

      def resolve_image_attrs node
        img_attrs = []
        img_attrs << %(alt="#{node.attr 'alt'}") if node.attr? 'alt'

        width = node.attr 'scaledwidth'
        width = node.attr 'width' if width.nil?

        # Unlike browsers, Calibre/Kindle *do* scale image if only height is specified
        # So, in order to match browser behavior, we just always omit height
        img_attrs << %(width="#{width}") unless width.nil?

        img_attrs
      end

      def convert_image node
        target = node.image_uri node.attr 'target'
        register_image node, target
        id_attr = node.id ? %( id="#{node.id}") : ''
        img_attrs = resolve_image_attrs node
        %(<figure#{id_attr} class="image#{prepend_space node.role}">
<div class="content">
<img src="#{target}"#{prepend_space img_attrs * ' '} />
</div>#{node.title? ? %(
<figcaption>#{node.captioned_title}</figcaption>) : ''}
</figure>)
      end

      def get_enclosing_chapter node
        loop do
          return nil if node.nil?
          return node if node.attr? 'ebook-chapter'
          node = node.parent
        end
      end

      def convert_inline_anchor node
        case node.type
        when :xref
          doc, refid, target, text = node.document, node.attr('refid'), node.target, node.text
          id_attr = ''

          if (path = node.attributes['path'])
            # NOTE non-nil path indicates this is an inter-document xref that's not included in current document
            text = node.text || path
          elsif refid == '#'
            logger.warn %(#{::File.basename doc.attr('docfile')}: <<chapter#>> xref syntax isn't supported anymore. Use either <<chapter>> or <<chapter#anchor>>)
          elsif refid
            ref = doc.references[:refs][refid]
            our_chapter = get_enclosing_chapter node
            ref_chapter = get_enclosing_chapter ref
            if ref_chapter
              ref_docname = ref_chapter.attr 'ebook-chapter'
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
              text = (ref.xreftext node.attr('xrefstyle', nil, true))
            else
              logger.warn %(#{::File.basename doc.attr('docfile')}: invalid reference to unknown anchor: #{refid})
            end
          end

          %(<a#{id_attr} href="#{target}" class="xref">#{text || "[#{refid}]"}</a>)
        when :ref
          # NOTE id is used instead of target starting in Asciidoctor 2.0.0
          %(<a id="#{node.target || node.id}"></a>)
        when :link
          %(<a href="#{node.target}" class="link">#{node.text}</a>)
        when :bibref
          # NOTE reftext is no longer enclosed in [] starting in Asciidoctor 2.0.0
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

      def convert_inline_break node
        %(#{node.text}<br/>)
      end

      def convert_inline_button node
        %(<b class="button">[<span class="label">#{node.text}</span>]</b>)
      end

      def convert_inline_callout node
        num = CalloutStartNum
        int_num = node.text.to_i
        (int_num - 1).times { num = num.next }
        %(<i class="conum" data-value="#{int_num}">#{num}</i>)
      end

      def convert_inline_footnote node
        if (index = node.attr 'index')
          %(<sup class="noteref">[<a id="noteref-#{index}" href="#note-#{index}" epub:type="noteref">#{index}</a>]</sup>)
        elsif node.type == :xref
          %(<mark class="noteref" title="Unresolved note reference">#{node.text}</mark>)
        end
      end

      def convert_inline_image node
        if node.type == 'icon'
          @icon_names << (icon_name = node.target)
          i_classes = ['icon', %(i-#{icon_name})]
          i_classes << %(icon-#{node.attr 'size'}) if node.attr? 'size'
          i_classes << %(icon-flip-#{(node.attr 'flip')[0]}) if node.attr? 'flip'
          i_classes << %(icon-rotate-#{node.attr 'rotate'}) if node.attr? 'rotate'
          i_classes << node.role if node.role?
          %(<i class="#{i_classes * ' '}"></i>)
        else
          target = node.image_uri node.target
          register_image node, target

          img_attrs = resolve_image_attrs node
          img_attrs << %(class="inline#{prepend_space node.role}")
          %(<img src="#{target}"#{prepend_space img_attrs * ' '}/>)
        end
      end

      def convert_inline_indexterm node
        node.type == :visible ? node.text : ''
      end

      def convert_inline_kbd node
        if (keys = node.attr 'keys').size == 1
          %(<kbd>#{keys[0]}</kbd>)
        else
          key_combo = keys.map {|key| %(<kbd>#{key}</kbd>) }.join '+'
          %(<span class="keyseq">#{key_combo}</span>)
        end
      end

      def convert_inline_menu node
        menu = node.attr 'menu'
        # NOTE we swap right angle quote with chevron right from FontAwesome using CSS
        caret = %(#{NoBreakSpace}<span class="caret">#{RightAngleQuote}</span> )
        if !(submenus = node.attr 'submenus').empty?
          submenu_path = submenus.map {|submenu| %(<span class="submenu">#{submenu}</span>#{caret}) }.join.chop
          %(<span class="menuseq"><span class="menu">#{menu}</span>#{caret}#{submenu_path} <span class="menuitem">#{node.attr 'menuitem'}</span></span>)
        elsif (menuitem = node.attr 'menuitem')
          %(<span class="menuseq"><span class="menu">#{menu}</span>#{caret}<span class="menuitem">#{menuitem}</span></span>)
        else
          %(<span class="menu">#{menu}</span>)
        end
      end

      def convert_inline_quoted node
        open, close, tag = QUOTE_TAGS[node.type]

        # TODO: implement proper stem support. See https://github.com/asciidoctor/asciidoctor-epub3/issues/10
        node.add_role 'literal' if [:monospaced, :asciimath, :latexmath].include? node.type

        if node.id
          class_attr = class_string node
          if tag
            %(#{open.chop} id="#{node.id}"#{class_attr}>#{node.text}#{close})
          else
            %(<span id="#{node.id}"#{class_attr}>#{open}#{node.text}#{close}</span>)
          end
        elsif role_valid_class? node.role
          class_attr = class_string node
          if tag
            %(#{open.chop}#{class_attr}>#{node.text}#{close})
          else
            %(<span#{class_attr}>#{open}#{node.text}#{close}</span>)
          end
        else
          %(#{open}#{node.text}#{close})
        end
      end

      def output_content node
        node.content_model == :simple ? %(<p>#{node.content}</p>) : node.content
      end

      # FIXME: merge into with xml_sanitize helper
      def xml_sanitize value, target = :attribute
        sanitized = (value.include? '<') ? value.gsub(XmlElementRx, '').strip.tr_s(' ', ' ') : value
        if target == :plain && (sanitized.include? ';')
          sanitized = sanitized.gsub(CharEntityRx) { [$1.to_i].pack 'U*' } if sanitized.include? '&#'
          sanitized = sanitized.gsub FromHtmlSpecialCharsRx, FromHtmlSpecialCharsMap
        elsif target == :attribute
          sanitized = sanitized.gsub '"', '&quot;' if sanitized.include? '"'
        end
        sanitized
      end

      # TODO: make check for last content paragraph a feature of Asciidoctor
      def mark_last_paragraph root
        return unless (last_block = root.blocks[-1])
        last_block = last_block.blocks[-1] while last_block.context == :section && last_block.blocks?
        if last_block.context == :paragraph
          last_block.attributes['role'] = last_block.role? ? %(#{last_block.role} last) : 'last'
        end
        nil
      end

      # Prepend a space to the value if it's non-nil, otherwise return empty string.
      def prepend_space value
        value ? %( #{value}) : ''
      end

      def add_theme_assets doc
        format = @format
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

        if format == :kf8
          # NOTE add layer of indirection so Kindle Direct Publishing (KDP) doesn't strip font-related CSS rules
          @book.add_item 'styles/epub3.css', content: '@import url("epub3-proxied.css");'.to_ios
          @book.add_item 'styles/epub3-css3-only.css', content: '@import url("epub3-css3-only-proxied.css");'.to_ios
          @book.add_item 'styles/epub3-proxied.css', content: (postprocess_css_file ::File.join(workdir, 'epub3.css'), format)
          @book.add_item 'styles/epub3-css3-only-proxied.css', content: (postprocess_css_file ::File.join(workdir, 'epub3-css3-only.css'), format)
        else
          @book.add_item 'styles/epub3.css', content: (postprocess_css_file ::File.join(workdir, 'epub3.css'), format)
          @book.add_item 'styles/epub3-css3-only.css', content: (postprocess_css_file ::File.join(workdir, 'epub3-css3-only.css'), format)
        end

        font_files, font_css = select_fonts ::File.join(DATA_DIR, 'styles/epub3-fonts.css'), (doc.attr 'scripts', 'latin')
        @book.add_item 'styles/epub3-fonts.css', content: font_css
        unless font_files.empty?
          # NOTE metadata property in oepbs package manifest doesn't work; must use proprietary iBooks file instead
          #(@book.metadata.add_metadata 'meta', 'true')['property'] = 'ibooks:specified-fonts' unless format == :kf8
          @book.add_optional_file 'META-INF/com.apple.ibooks.display-options.xml', '<?xml version="1.0" encoding="UTF-8"?>
<display_options>
<platform name="*">
<option name="specified-fonts">true</option>
</platform>
</display_options>'.to_ios unless format == :kf8

          font_files.each do |font_file|
            item = @book.add_item font_file, content: File.join(DATA_DIR, font_file)
          end
        end
        nil
      end

      def add_cover_image doc
        return if (image_path = doc.attr 'front-cover-image').nil?

        imagesdir = (doc.attr 'imagesdir', '.').chomp '/'
        imagesdir = (imagesdir == '.' ? '' : %(#{imagesdir}/))

        image_attrs = {}
        if (image_path.include? ':') && image_path =~ ImageMacroRx
          logger.warn %(deprecated block macro syntax detected in front-cover-image attribute) if image_path.start_with? 'image::'
          image_path = %(#{imagesdir}#{$1})
          (::Asciidoctor::AttributeList.new $2).parse_into image_attrs, %w(alt width height) unless $2.empty?
        end

        image_href = %(#{imagesdir}jacket/cover#{::File.extname image_path})

        workdir = doc.attr 'docdir'
        workdir = '.' if workdir.nil_or_empty?

        unless ::File.readable? ::File.join(workdir, image_path)
          logger.error %(#{::File.basename doc.attr('docfile')}: front cover image not found or readable: #{::File.expand_path image_path, workdir})
          return
        end

        unless !image_attrs.empty? && (width = image_attrs['width']) && (height = image_attrs['height'])
          width, height = 1050, 1600
        end

        @book.add_item(image_href, content: File.join(workdir, image_path)).cover_image

        unless @format == :kf8
          # NOTE SVG wrapper maintains aspect ratio and confines image to view box
          content = %(<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<head>
<meta charset="UTF-8"/>
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
</html>).to_ios

          # Gitden expects a cover.xhtml, so add it to the spine
          @book.add_ordered_item 'cover.xhtml', content: content, id: 'cover'
        end
        nil
      end

      def get_frontmatter_files doc, workdir
        if doc.attr? 'epub3-frontmatterdir'
          fmdir = doc.attr 'epub3-frontmatterdir'
          fmglob = 'front-matter.*\.html'
          fm_path = File.join workdir, fmdir
          unless Dir.exist? fm_path
            logger.warn %(#{File.basename doc.attr('docfile')}: directory specified by 'epub3-frontmattderdir' doesn't exist! Ignoring ...)
            return []
          end
          fms = Dir.entries(fm_path).delete_if {|x| !x.match fmglob }.sort.map {|y| File.join fm_path, y }
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

      def add_front_matter_page doc
        workdir = doc.attr 'docdir'
        workdir = '.' if workdir.nil_or_empty?

        get_frontmatter_files(doc, workdir).each do |front_matter|
          front_matter_content = ::File.read front_matter

          front_matter_file = File.basename front_matter, '.html'
          item = @book.add_ordered_item "#{front_matter_file}.xhtml", content: (postprocess_xhtml front_matter_content)
          item.add_property 'svg' if SvgImgSniffRx =~ front_matter_content

          front_matter_content.scan ImgSrcScanRx do
            @book.add_item $1, content: File.join(File.dirname(front_matter), $1)
          end
        end

        nil
      end

      def add_profile_images doc, usernames
        imagesdir = (doc.attr 'imagesdir', '.').chomp '/'
        imagesdir = (imagesdir == '.' ? nil : %(#{imagesdir}/))

        @book.add_item %(#{imagesdir}avatars/default.jpg), content: ::File.join(DATA_DIR, 'images/default-avatar.jpg')
        @book.add_item %(#{imagesdir}headshots/default.jpg), content: ::File.join(DATA_DIR, 'images/default-headshot.jpg')

        workdir = (workdir = doc.attr 'docdir').nil_or_empty? ? '.' : workdir

        usernames.each do |username|
          avatar = %(#{imagesdir}avatars/#{username}.jpg)
          if ::File.readable? (resolved_avatar = (::File.join workdir, avatar))
            @book.add_item avatar, content: resolved_avatar
          else
            logger.error %(avatar for #{username} not found or readable: #{avatar}; falling back to default avatar)
            @book.add_item avatar, content: ::File.join(DATA_DIR, 'images/default-avatar.jpg')
          end

          headshot = %(#{imagesdir}headshots/#{username}.jpg)
          if ::File.readable? (resolved_headshot = (::File.join workdir, headshot))
            @book.add_item headshot, content: resolved_headshot
          elsif doc.attr? 'builder', 'editions'
            logger.error %(headshot for #{username} not found or readable: #{headshot}; falling back to default headshot)
            @book.add_item headshot, content: ::File.join(DATA_DIR, 'images/default-headshot.jpg')
          end
        end
        nil
      end

      # TODO: aggregate authors of chapters into authors attribute(s) on main document
      def nav_doc doc, items
        lines = [%(<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang = doc.attr 'lang', 'en'}" lang="#{lang}">
<head>
<meta charset="UTF-8"/>
<title>#{sanitize_doctitle_xml doc, :cdata}</title>
<link rel="stylesheet" type="text/css" href="styles/epub3.css"/>
<link rel="stylesheet" type="text/css" href="styles/epub3-css3-only.css" media="(min-device-width: 0px)"/>
</head>
<body>
<h1>#{sanitize_doctitle_xml doc, :pcdata}</h1>
<nav epub:type="toc" id="toc">
<h2>#{doc.attr 'toc-title'}</h2>)]
        lines << (nav_level items, [(doc.attr 'toclevels', 1).to_i, 0].max)
        lines << %(</nav>
</body>
</html>)
        lines * LF
      end

      def nav_level items, depth, state = {}
        lines = []
        lines << '<ol>'
        items.each do |item|
          #index = (state[:index] = (state.fetch :index, 0) + 1)
          if item.attr? 'ebook-chapter'
            # NOTE we sanitize the chapter titles because we use formatting to control layout
            if item.context == :document
              item_label = sanitize_doctitle_xml item, :cdata
            else
              item_label = sanitize_xml item.title, :cdata
            end
            item_href = (state[:content_doc_href] = %(#{item.attr 'ebook-chapter'}.xhtml))
          else
            item_label = sanitize_xml item.title, :pcdata
            item_href = %(#{state[:content_doc_href]}##{item.id})
          end
          lines << %(<li><a href="#{item_href}">#{item_label}</a>)
          if depth == 0 || (child_sections = item.sections).empty?
            lines[-1] = %(#{lines[-1]}</li>)
          else
            lines << (nav_level child_sections, depth - 1, state)
            lines << '</li>'
          end
          state.delete :content_doc_href if item.attr? 'ebook-chapter'
        end
        lines << '</ol>'
        lines * LF
      end

      def ncx_doc doc, items
        # TODO: populate docAuthor element based on unique authors in work
        lines = [%(<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="#{doc.attr 'lang', 'en'}">
<head>
<meta name="dtb:uid" content="#{@book.identifier}"/>
%{depth}
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>#{sanitize_doctitle_xml doc, :cdata}</text></docTitle>
<navMap>)]
        lines << (ncx_level items, [(doc.attr 'toclevels', 1).to_i, 0].max, state = {})
        lines[0] = lines[0].sub '%{depth}', %(<meta name="dtb:depth" content="#{state[:max_depth]}"/>)
        lines << %(</navMap>
</ncx>)
        lines * LF
      end

      def ncx_level items, depth, state = {}
        lines = []
        state[:max_depth] = (state.fetch :max_depth, 0) + 1
        items.each do |item|
          index = (state[:index] = (state.fetch :index, 0) + 1)
          item_id = %(nav_#{index})
          if item.attr? 'ebook-chapter'
            if item.context == :document
              item_label = sanitize_doctitle_xml item, :cdata
            else
              item_label = sanitize_xml item.title, :cdata
            end
            item_href = (state[:content_doc_href] = %(#{item.attr 'ebook-chapter'}.xhtml))
          else
            item_label = sanitize_xml item.title, :cdata
            item_href = %(#{state[:content_doc_href]}##{item.id})
          end
          lines << %(<navPoint id="#{item_id}" playOrder="#{index}">)
          lines << %(<navLabel><text>#{item_label}</text></navLabel>)
          lines << %(<content src="#{item_href}"/>)
          unless depth == 0 || (child_sections = item.sections).empty?
            lines << (ncx_level child_sections, depth - 1, state)
          end
          lines << %(</navPoint>)
          state.delete :content_doc_href if item.attr? 'ebook-chapter'
        end
        lines * LF
      end

      # Swap fonts in CSS based on the value of the document attribute 'scripts',
      # then return the list of fonts as well as the font CSS.
      def select_fonts filename, scripts = 'latin'
        font_css = ::File.read filename
        font_css = font_css.gsub(/(?<=-)latin(?=\.ttf\))/, scripts) unless scripts == 'latin'

        # match CSS font urls in the forms of:
        # src: url(../fonts/notoserif-regular-latin.ttf);
        # src: url(../fonts/notoserif-regular-latin.ttf) format("truetype");
        font_list = font_css.scan(/url\(\.\.\/([^)]+\.ttf)\)/).flatten

        [font_list, font_css.to_ios]
      end

      def postprocess_css_file filename, format
        return filename unless format == :kf8
        postprocess_css ::File.read(filename), format
      end

      def postprocess_css content, format
        return content.to_ios unless format == :kf8
        # TODO: convert regular expressions to constants
        content
          .gsub(/^  -webkit-column-break-.*\n/, '')
          .gsub(/^  max-width: .*\n/, '')
          .to_ios
      end

      # NOTE Kindle requires that
      #      <meta charset="utf-8"/>
      #      be converted to
      #      <meta http-equiv="Content-Type" content="application/xml+xhtml; charset=UTF-8"/>
      def postprocess_xhtml content
        return content.to_ios unless @format == :kf8
        # TODO: convert regular expressions to constants
        content
          .gsub(/<meta charset="(.+?)"\/>/, '<meta http-equiv="Content-Type" content="application/xml+xhtml; charset=\1"/>')
          .gsub(/<img([^>]+) style="width: (\d\d)%;"/, '<img\1 style="width: \2%; height: \2%;"')
          .gsub(/<script type="text\/javascript">.*?<\/script>\n?/m, '')
          .to_ios
      end

      def get_kindlegen_command kindlegen_path
        unless kindlegen_path.nil?
          logger.debug %(Using ebook-kindlegen-path attribute: #{kindlegen_path})
          return [kindlegen_path]
        end

        unless (result = ENV['KINDLEGEN']).nil?
          logger.debug %(Using KINDLEGEN env variable: #{result})
          return [result]
        end

        begin
          require 'kindlegen' unless defined? ::Kindlegen
          result = ::Kindlegen.command.to_s
          logger.debug %(Using KindleGen from gem: #{result})
          [result]
        rescue LoadError => e
          logger.debug %(#{e}; Using KindleGen from PATH)
          [%(kindlegen#{::Gem.win_platform? ? '.exe' : ''})]
        end
      end

      def distill_epub_to_mobi epub_file, target, compress, kindlegen_path
        mobi_file = ::File.basename target.sub(EpubExtensionRx, '.mobi')
        compress_flag = KindlegenCompression[compress ? (compress.empty? ? '1' : compress.to_s) : '0']

        argv = get_kindlegen_command(kindlegen_path) + ['-dont_append_source', compress_flag, '-o', mobi_file, epub_file].compact
        begin
          # This duplicates Kindlegen.run, but we want to override executable
          out, err, res = Open3.capture3(*argv) do |r|
            r.force_encoding 'UTF-8' if ::Gem.win_platform? && r.respond_to?(:force_encoding)
          end
        rescue Errno::ENOENT => e
          raise 'Unable to run KindleGen. Either install the kindlegen gem or place `kindlegen` executable on PATH or set KINDLEGEN environment variable with path to it', cause: e
        end

        out.each_line do |line|
          log_line line
        end
        err.each_line do |line|
          log_line line
        end

        output_file = ::File.join ::File.dirname(epub_file), mobi_file
        if res.success?
          logger.debug %(Wrote MOBI to #{output_file})
        else
          logger.error %(KindleGen failed to write MOBI to #{output_file})
        end
      end

      def get_epubcheck_command epubcheck_path
        unless epubcheck_path.nil?
          logger.debug %(Using ebook-epubcheck-path attribute: #{epubcheck_path})
          return [epubcheck_path]
        end

        unless (result = ENV['EPUBCHECK']).nil?
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

      def validate_epub epub_file, epubcheck_path
        argv = get_epubcheck_command(epubcheck_path) + ['-w', epub_file]
        begin
          out, err, res = Open3.capture3(*argv)
        rescue Errno::ENOENT => e
          raise 'Unable to run EPUBCheck. Either install epubcheck-ruby gem or place `epubcheck` executable on PATH or set EPUBCHECK environment variable with path to it', cause: e
        end

        out.each_line do |line|
          logger.info line
        end
        err.each_line do |line|
          log_line line
        end

        logger.error %(EPUB validation failed: #{epub_file}) unless res.success?
      end

      def log_line line
        line = line.strip

        if line =~ /^fatal/i
          logger.fatal line
        elsif line =~ /^error/i
          logger.error line
        elsif line =~ /^warning/i
          logger.warn line
        else
          logger.info line
        end
      end

      private

      def class_string node
        role = node.role

        return '' unless role_valid_class? role

        %( class="#{role}")
      end

      # Handles asciidoctor 1.5.6 quirk when role can be parent
      def role_valid_class? role
        role.is_a? String
      end
    end

    class DocumentIdGenerator
      ReservedIds = %w(cover nav ncx)
      CharRefRx = /&(?:([a-zA-Z][a-zA-Z]+\d{0,2})|#(\d\d\d{0,4})|#x([\da-fA-F][\da-fA-F][\da-fA-F]{0,3}));/
      if defined? __dir__
        InvalidIdCharsRx = /[^\p{Word}]+/
        LeadingDigitRx = /^\p{Nd}/
      else
        InvalidIdCharsRx = /[^[:word:]]+/
        LeadingDigitRx = /^[[:digit:]]/
      end
      class << self
        def generate_id doc, pre = nil, sep = nil
          synthetic = false
          unless (id = doc.id)
            # NOTE we assume pre is a valid ID prefix and that pre and sep only contain valid ID chars
            pre ||= '_'
            sep = sep ? sep.chr : '_'
            if doc.header?
              id = doc.doctitle sanitize: true
              id = id.gsub CharRefRx do
                $1 ? ($1 == 'amp' ? 'and' : sep) : ((d = $2 ? $2.to_i : $3.hex) == 8217 ? '' : ([d].pack 'U*'))
              end if id.include? '&'
              id = id.downcase.gsub InvalidIdCharsRx, sep
              if id.empty?
                id, synthetic = nil, true
              else
                unless sep.empty?
                  if (id = id.tr_s sep, sep).end_with? sep
                    if id == sep
                      id, synthetic = nil, true
                    else
                      id = (id.start_with? sep) ? id[1..-2] : id.chop
                    end
                  elsif id.start_with? sep
                    id = id[1..-1]
                  end
                end
                unless synthetic
                  if pre.empty?
                    id = %(_#{id}) if LeadingDigitRx =~ id
                  elsif !(id.start_with? pre)
                    id = %(#{pre}#{id})
                  end
                end
              end
            elsif (first_section = doc.first_section)
              id = first_section.id
            else
              synthetic = true
            end
            id = %(#{pre}document#{sep}#{doc.object_id}) if synthetic
          end
          logger.error %(chapter uses a reserved ID: #{id}) if !synthetic && (ReservedIds.include? id)
          id
        end
      end
    end

    Extensions.register do
      if (document = @document).backend == 'epub3'
        document.set_attribute 'listing-caption', 'Listing'
        # pygments.rb hangs on JRuby for Windows, see https://github.com/asciidoctor/asciidoctor-epub3/issues/253
        if !(::RUBY_ENGINE == 'jruby' && Gem.win_platform?) && (Gem.try_activate 'pygments.rb')
          if document.set_attribute 'source-highlighter', 'pygments'
            document.set_attribute 'pygments-css', 'style'
            document.set_attribute 'pygments-style', 'bw'
          end
        end
        case (ebook_format = document.attributes['ebook-format'])
        when 'epub3', 'kf8'
          # all good
        when 'mobi'
          ebook_format = document.attributes['ebook-format'] = 'kf8'
        else
          # QUESTION should we display a warning?
          ebook_format = document.attributes['ebook-format'] = 'epub3'
        end
        document.attributes[%(ebook-format-#{ebook_format})] = ''
        treeprocessor do
          process do |doc|
            doc.id = DocumentIdGenerator.generate_id doc, (doc.attr 'idprefix'), (doc.attr 'idseparator')
            nil
          end
        end
      end
    end
  end
end
