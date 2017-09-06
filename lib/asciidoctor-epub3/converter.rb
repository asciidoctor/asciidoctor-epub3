# encoding: utf-8
require_relative 'spine_item_processor'
require_relative 'font_icon_map'

module Asciidoctor
module Epub3

# Public: The main converter for the epub3 backend that handles packaging the
# EPUB3 or KF8 publication file.
class Converter
  include ::Asciidoctor::Converter
  include ::Asciidoctor::Writer

  register_for 'epub3'

  def initialize backend, opts
    super
    basebackend 'html'
    outfilesuffix '.epub' # dummy outfilesuffix since it may be .mobi
    htmlsyntax 'xml'
    @validate = false
    @extract = false
  end

  def convert node, name = nil
    if (name ||= node.node_name) == 'document'
      @validate = node.attr? 'ebook-validate'
      @extract = node.attr? 'ebook-extract'
      @compress = node.attr 'ebook-compress'
      Packager.new node, (node.references[:spine_items] || [node]), node.attributes['ebook-format'].to_sym
    # converting an element from the spine document, such as an inline node in the doctitle
    elsif name.start_with? 'inline_'
      (@content_converter ||= ::Asciidoctor::Converter::Factory.default.create('epub3-xhtml5')).convert node, name
    else
      raise ::ArgumentError, %(Encountered unexpected node in epub3 package converter: #{name})
    end
  end

  # FIXME we have to package in write because we don't have access to target before this point
  def write packager, target
    packager.package validate: @validate, extract: @extract, compress: @compress, target: target
    nil
  end
end

# Public: The converter for the epub3 backend that converts the individual
# content documents in an EPUB3 publication.
class ContentConverter
  include ::Asciidoctor::Converter

  register_for 'epub3-xhtml5'

  EOL = %(\n)
  NoBreakSpace = '&#xa0;'
  ThinNoBreakSpace = '&#x202f;'
  RightAngleQuote = '&#x203a;'
  CalloutStartNum = %(\u2460)

  XmlElementRx = /<\/?.+?>/
  CharEntityRx = /&#(\d{2,6});/

  FromHtmlSpecialCharsMap = {
    '&lt;' => '<',
    '&gt;' => '>',
    '&amp;' => '&'
  }

  FromHtmlSpecialCharsRx = /(?:#{FromHtmlSpecialCharsMap.keys * '|'})/

  ToHtmlSpecialCharsMap = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;'
  }

  ToHtmlSpecialCharsRx = /[#{ToHtmlSpecialCharsMap.keys.join}]/

  OpenParagraphTagRx = /^<p>/
  CloseParagraphTagRx = /<\/p>$/

  def initialize backend, opts
    super
    basebackend 'html'
    outfilesuffix '.xhtml'
    htmlsyntax 'xml'
    @xrefs_seen = ::Set.new
    @icon_names = []
  end

  def convert node, name = nil
    if respond_to?(name ||= node.node_name)
      send name, node
    else
      warn %(asciidoctor: WARNING: conversion missing in epub3 backend for #{name})
    end
  end

  def document node
    docid = node.id

    if (doctitle = node.doctitle partition: true, sanitize: true, use_fallback: true).subtitle?
      title = doctitle.main
      subtitle = doctitle.subtitle
    else
      # HACK until we get proper handling of title-only in CSS
      title = ''
      subtitle = doctitle.combined
    end

    doctitle_sanitized = doctitle.combined
    subtitle_formatted = subtitle.split.map {|w| %(<b>#{w}</b>) } * ' '

    if (node.attr 'publication-type', 'book') == 'book'
      byline = nil
    else
      author = node.attr 'author'
      username = node.attr 'username', 'default'
      imagesdir = (node.references[:spine].attr 'imagesdir', '.').chomp '/'
      imagesdir = (imagesdir == '.' ? nil : %(#{imagesdir}/))
      byline = %(<p class="byline"><img src="#{imagesdir}avatars/#{username}.jpg"/> <b class="author">#{author}</b></p>#{EOL})
    end

    mark_last_paragraph node
    content = node.content

    # NOTE must run after content is resolved
    # TODO perhaps create dynamic CSS file?
    if @icon_names.empty?
      icon_css_head = icon_css_scoped = nil
    else
      icon_defs = @icon_names.map {|name|
        %(.i-#{name}::before { content: "#{FontIconMap[name.tr('-', '_').to_sym]}"; })
      } * EOL
      icon_css_head = %(<style>
#{icon_defs}
</style>
)
      # NOTE Namo Pubtree requires icon CSS to be repeated inside <body> (or in a linked stylesheet); wrap in div to hide from Aldiko
      icon_css_scoped = (node.attr? 'ebook-format', 'kf8') ? nil : %(<div style="display: none" aria-hidden="true"><style scoped="scoped">
#{icon_defs}
</style></div>
)
    end

    # NOTE kindlegen seems to mangle the <header> element, so we wrap its content in a div
    lines = [%(<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang = (node.attr 'lang', 'en')}" lang="#{lang}">
<head>
<meta charset="UTF-8"/>
<title>#{doctitle_sanitized}</title>
<link rel="stylesheet" type="text/css" href="styles/epub3.css"/>
<link rel="stylesheet" type="text/css" href="styles/epub3-css3-only.css" media="(min-device-width: 0px)"/>
#{icon_css_head}<script type="text/javascript">
document.addEventListener('DOMContentLoaded', function(event, reader) {
  if (!(reader = navigator.epubReadingSystem)) {
    if (navigator.userAgent.indexOf(' calibre/') >= 0) reader = { name: 'calibre-desktop' };
    else if (window.parent == window || !(reader = window.parent.navigator.epubReadingSystem)) return;
  }
  document.body.setAttribute('class', reader.name.toLowerCase().replace(/ /g, '-'));
});
</script>
</head>
<body>
<section class="chapter" title="#{doctitle_sanitized.gsub '"', '&quot;'}" epub:type="chapter" id="#{docid}">
#{icon_css_scoped}<header>
<div class="chapter-header">
#{byline}<h1 class="chapter-title">#{title}#{subtitle ? %[ <small class="subtitle">#{subtitle_formatted}</small>] : nil}</h1>
</div>
</header>
#{content})]

    if node.footnotes?
      # NOTE kindlegen seems to mangle the <footer> element, so we wrap its content in a div
      lines << '<footer>
<div class="chapter-footer">
<div class="footnotes">'
      node.footnotes.each do |footnote|
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

    lines * EOL
  end

  # NOTE embedded is used for AsciiDoc table cell content
  def embedded node
    node.content
  end

  def section node
    hlevel = node.level + 1
    epub_type_attr = node.special ? %( epub:type="#{node.sectname}") : nil
    div_classes = [%(sect#{node.level}), node.role].compact
    title = node.title
    title_sanitized = xml_sanitize title
    if node.document.header? || node.level != 1 || node != node.document.first_section
      %(<section class="#{div_classes * ' '}" title="#{title_sanitized}"#{epub_type_attr}>
<h#{hlevel} id="#{node.id}">#{title}</h#{hlevel}>#{(content = node.content).empty? ? nil : %[
#{content}]}
</section>)
    else
      # document has no level-0 heading and this heading serves as the document title
      node.content
    end
  end

  # TODO support use of quote block as abstract
  def preamble node
    if (first_block = node.blocks[0]) && first_block.style == 'abstract'
      abstract first_block
    # REVIEW should we treat the preamble as an abstract in general?
    elsif first_block && node.blocks.size == 1
      abstract first_block
    else
      node.content
    end
  end

  def open node
    id_attr = node.id ? %( id="#{node.id}") : nil
    class_attr = node.role ? %( class="#{node.role}") : nil
    if id_attr || class_attr
      %(<div#{id_attr}#{class_attr}>
#{convert_content node}
</div>)
    else
      convert_content node
    end
  end

  def abstract node
    %(<div class="abstract" epub:type="preamble">
#{convert_content node}
</div>)
  end

  def paragraph node
    role = node.role
    # stack-head is the alternative to the default, inline-head (where inline means "run-in")
    head_stop = node.attr 'head-stop', (role && (node.has_role? 'stack-head') ? nil : '.')
    # FIXME promote regexp to constant
    head = node.title? ? %(<strong class="head">#{title = node.title}#{head_stop && title !~ /[[:punct:]]$/ ? head_stop : nil}</strong> ) : nil
    if role
      node.set_option 'hardbreaks' if node.has_role? 'signature'
      %(<p class="#{role}">#{head}#{node.content}</p>)
    else
      %(<p>#{head}#{node.content}</p>)
    end
  end

  def pass node
    content = node.content
    if content == '<?hard-pagebreak?>'
      '<hr epub:type="pagebreak" class="pagebreak"/>'
    else
      content
    end
  end

  def admonition node
    if node.title?
      title = node.title
      title_sanitized = xml_sanitize title
      title_attr = %( title="#{node.caption}: #{title_sanitized}")
      title_el = %(<h2>#{title}</h2>
)
    else
      title_attr = %( title="#{node.caption}")
      title_el = nil
    end

    type = node.attr 'name'
    epub_type = case type
    when 'tip'
      'help'
    when 'note'
      'note'
    when 'important', 'warning', 'caution'
      'warning'
    end
    %(<aside class="admonition #{type}"#{title_attr} epub:type="#{epub_type}">
#{title_el}<div class="content">
#{convert_content node}
</div>
</aside>)
  end

  def example node
    title_div = node.title? ? %(<div class="example-title">#{node.title}</div>
) : nil
    %(<div class="example">
#{title_div}<div class="example-content">
#{convert_content node}
</div>
</div>)
  end

  def floating_title node
    tag_name = %(h#{node.level + 1})
    id_attribute = node.id ? %( id="#{node.id}") : nil
    %(<#{tag_name}#{id_attribute} class="#{['discrete', node.role].compact * ' '}">#{node.title}</#{tag_name}>)
  end

  def listing node
    figure_classes = ['listing']
    figure_classes << 'coalesce' if node.option? 'unbreakable'
    pre_classes = node.style == 'source' ? ['source', %(language-#{node.attr 'language'})] : ['screen']
    title_div = node.title? ? %(<figcaption>#{node.captioned_title}</figcaption>
) : nil
    # patches conums to fix extra or missing leading space
    # TODO remove patch once upgrading to Asciidoctor 1.5.6
    %(<figure class="#{figure_classes * ' '}">
#{title_div}<pre class="#{pre_classes * ' '}"><code>#{(node.content || '').gsub(/(?<! )<i class="conum"| +<i class="conum"/, ' <i class="conum"')}</code></pre>
</figure>)
  end

  # QUESTION should we wrap the <pre> in either <div> or <figure>?
  def literal node
    %(<pre class="screen">#{node.content}</pre>)
  end

  def page_break node
    '<hr epub:type="pagebreak" class="pagebreak"/>'
  end

  def thematic_break node
    '<hr class="thematicbreak"/>'
  end

  def quote node
    id_attr = %( id="#{node.id}") if node.id
    class_attr = (role = node.role) ? %( class="blockquote #{role}") : ' class="blockquote"'

    footer_content = []
    if (attribution = node.attr 'attribution')
      footer_content << attribution
    end

    if (citetitle = node.attr 'citetitle')
      citetitle_sanitized = xml_sanitize citetitle
      footer_content << %(<cite title="#{citetitle_sanitized}">#{citetitle}</cite>)
    end

    if node.title?
      footer_content << %(<span class="context">#{node.title}</span>)
    end

    footer_tag = footer_content.empty? ? nil : %(
<footer>~ #{footer_content * ' '}</footer>)
    content = (convert_content node).strip.
      sub(OpenParagraphTagRx, '<p><span class="open-quote">“</span>').
      sub(CloseParagraphTagRx, '<span class="close-quote">”</span></p>')
    %(<div#{id_attr}#{class_attr}>
<blockquote>
#{content}#{footer_tag}
</blockquote>
</div>)
  end

  def verse node
    id_attr = %( id="#{node.id}") if node.id
    class_attr = (role = node.role) ? %( class="verse #{role}") : ' class="verse"'

    footer_content = []
    if (attribution = node.attr 'attribution')
      footer_content << attribution
    end

    if (citetitle = node.attr 'citetitle')
      citetitle_sanitized = xml_sanitize citetitle
      footer_content << %(<cite title="#{citetitle_sanitized}">#{citetitle}</cite>)
    end

    footer_tag = footer_content.size > 0 ? %(
<span class="attribution">~ #{footer_content * ', '}</span>) : nil
    %(<div#{id_attr}#{class_attr}>
<pre>#{node.content}#{footer_tag}</pre>
</div>)
  end

  def sidebar node
    classes = ['sidebar']
    if node.title?
      classes << 'titled'
      title = node.title
      title_sanitized = xml_sanitize title
      title_attr = %( title="#{title_sanitized}")
      title_el = %(<h2>#{title}</h2>
)
    else
      title_attr = nil
      title_el = nil
    end

    %(<aside class="#{classes * ' '}"#{title_attr} epub:type="sidebar">
#{title_el}<div class="content">
#{convert_content node}
</div>
</aside>)
  end

  def table node
    lines = [%(<div class="table">)]
    lines << %(<div class="content">)
    table_id_attr = node.id ? %( id="#{node.id}") : nil
    frame_class = {
      'all' => 'table-framed',
      'topbot' => 'table-framed-topbot',
      'sides' => 'table-framed-sides',
      'none' => ''
    }
    grid_class = {
      'all' => 'table-grid',
      'rows' => 'table-grid-rows',
      'cols' => 'table-grid-cols',
      'none' => ''
    }
    table_classes = %W(table #{frame_class[node.attr 'frame'] || frame_class['topbot']} #{grid_class[node.attr 'grid'] || grid_class['rows']})
    if (role = node.role)
      table_classes << role
    end
    table_class_attr = %( class="#{table_classes * ' '}")
    table_styles = []
    unless (node.option? 'autowidth') && !(node.attr? 'width', nil, false)
      table_styles << %(width: #{node.attr 'tablepcwidth'}%)
    end
    table_style_attr = table_styles.size > 0 ? %( style="#{table_styles * '; '}") : nil

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
      [:head, :foot, :body].select {|tsec| !node.rows[tsec].empty? }.each do |tsec|
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

            cell_tag_name = (tsec == :head || cell.style == :header ? 'th' : 'td')
            cell_classes = []
            if (halign = cell.attr 'halign') && halign != 'left'
              cell_classes << 'halign-left'
            end
            if (halign = cell.attr 'valign') && halign != 'top'
              cell_classes << 'valign-top'
            end
            cell_class_attr = cell_classes.size > 0 ? %( class="#{cell_classes * ' '}") : nil
            cell_colspan_attr = cell.colspan ? %( colspan="#{cell.colspan}") : nil
            cell_rowspan_attr = cell.rowspan ? %( rowspan="#{cell.rowspan}") : nil
            cell_style_attr = (node.document.attr? 'cellbgcolor') ? %( style="background-color: #{node.document.attr 'cellbgcolor'}") : nil
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
    lines * EOL
  end

  def colist node
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

  # TODO add complex class if list has nested blocks
  def dlist node
    lines = []
    case (style = node.style)
    when 'itemized', 'ordered'
      list_tag_name = (style == 'itemized' ? 'ul' : 'ol')
      role = node.role
      subject_stop = node.attr 'subject-stop', (role && (node.has_role? 'stack') ? nil : ':')
      # QUESTION should we just use itemized-list and ordered-list as the class here? or just list?
      div_classes = [%(#{style}-list), role].compact
      list_class_attr = (node.option? 'brief') ? ' class="brief"' : nil
      lines << %(<div class="#{div_classes * ' '}">
<#{list_tag_name}#{list_class_attr}#{list_tag_name == 'ol' && (node.option? 'reversed') ? ' reversed="reversed"' : nil}>)
      node.items.each do |subjects, dd|
        # consists of one term (a subject) and supporting content
        subject = [*subjects].first.text
        subject_plain = xml_sanitize subject, :plain
        subject_element = %(<strong class="subject">#{subject}#{subject_stop && subject_plain !~ /[[:punct:]]$/ ? subject_stop : nil}</strong>)
        lines << '<li>'
        if dd
          # NOTE: must wrap remaining text in a span to help webkit justify the text properly
          lines << %(<span class="principal">#{subject_element}#{dd.text? ? %[ <span class="supporting">#{dd.text}</span>] : nil}</span>)
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
        if dd
          lines << '<dd>'
          if dd.blocks?
            lines << %(<span class="principal">#{dd.text}</span>) if dd.text?
            lines << dd.content
          else
            lines << %(<span class="principal">#{dd.text}</span>)
          end
          lines << '</dd>'
        end
      end
      lines << '</dl>
</div>'
    end
    lines * EOL
  end

  # TODO support start attribute
  def olist node
    complex = false
    div_classes = ['ordered-list', node.style, node.role].compact
    ol_classes = [node.style, ((node.option? 'brief') ? 'brief' : nil)].compact
    ol_class_attr = ol_classes.empty? ? nil : %( class="#{ol_classes * ' '}")
    id_attribute = node.id ? %( id="#{node.id}") : nil
    lines = [%(<div#{id_attribute} class="#{div_classes * ' '}">)]
    lines << %(<h3 class="list-heading">#{node.title}</h3>) if node.title?
    lines << %(<ol#{ol_class_attr}#{(node.option? 'reversed') ? ' reversed="reversed"' : nil}>)
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
    lines * EOL
  end

  def ulist node
    complex = false
    div_classes = ['itemized-list', node.style, node.role].compact
    ul_classes = [node.style, ((node.option? 'brief') ? 'brief' : nil)].compact
    ul_class_attr = ul_classes.empty? ? nil : %( class="#{ul_classes * ' '}")
    id_attribute = node.id ? %( id="#{node.id}") : nil
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
    lines * EOL
  end

  def image node
    target = node.attr 'target'
    type = (::File.extname target)[1..-1]
    img_attrs = [%(alt="#{node.attr 'alt'}")]
    case type
    when 'svg'
      img_attrs << %(style="width: #{node.attr 'scaledwidth', '100%'}")
      # TODO make this a convenience method on document
      epub_properties = (node.document.attr 'epub-properties') || []
      unless epub_properties.include? 'svg'
        epub_properties << 'svg'
        node.document.attributes['epub-properties'] = epub_properties
      end
    else
      if node.attr? 'scaledwidth'
        img_attrs << %(style="width: #{node.attr 'scaledwidth'}")
      end
    end
=begin
    # NOTE to set actual width and height, use CSS width and height
    if type == 'svg'
      if node.attr? 'scaledwidth'
        img_attrs << %(width="#{node.attr 'scaledwidth'}")
      # Kindle
      #elsif node.attr? 'scaledheight'
      #  img_attrs << %(width="#{node.attr 'scaledheight'}" height="#{node.attr 'scaledheight'}")
      # ePub3
      elsif node.attr? 'scaledheight'
        img_attrs << %(height="#{node.attr 'scaledheight'}" style="max-height: #{node.attr 'scaledheight'} !important")
      else
        # Aldiko doesn't not scale width to 100% by default
        img_attrs << %(width="100%")
      end
    end
=end
    %(<figure class="image">
<div class="content">
<img src="#{node.image_uri node.attr('target')}" #{img_attrs * ' '}/>
</div>#{node.title? ? %[
<figcaption>#{node.captioned_title}</figcaption>] : nil}
</figure>)
  end

  def inline_anchor node
    target = node.target
    case node.type
    when :xref # TODO would be helpful to know what type the target is (e.g., bibref)
      doc, refid, text, path = node.document, ((node.attr 'refid') || target), node.text, (node.attr 'path')
      # NOTE if path is non-nil, we have an inter-document xref
      # QUESTION should we drop the id attribute for an inter-document xref?
      if path
        # ex. chapter-id#section-id
        if node.attr 'fragment'
          refdoc_id, refdoc_refid = refid.split '#', 2
          if refdoc_id == refdoc_refid
            target = target[0...(target.index '#')]
            id_attr = %( id="xref--#{refdoc_id}")
          else
            id_attr = %( id="xref--#{refdoc_id}--#{refdoc_refid}")
          end
        # ex. chapter-id#
        else
          refdoc_id = refdoc_refid = refid
          # inflate key to spine item root (e.g., transform chapter-id to chapter-id#chapter-id)
          refid = %(#{refid}##{refid})
          id_attr = %( id="xref--#{refdoc_id}")
        end
        id_attr = nil unless @xrefs_seen.add? refid
        refdoc = doc.references[:spine_items].find {|it| refdoc_id == (it.id || (it.attr 'docname')) }
        if refdoc
          if (xreftext = refdoc.references[:ids][refdoc_refid])
            text ||= xreftext
          else
            warn %(asciidoctor: WARNING: #{::File.basename(doc.attr 'docfile')}: invalid reference to unknown anchor in #{refdoc_id} chapter: #{refdoc_refid})
          end
        else
          warn %(asciidoctor: WARNING: #{::File.basename(doc.attr 'docfile')}: invalid reference to anchor in unknown chapter: #{refdoc_id})
        end
      else
        id_attr = (@xrefs_seen.add? refid) ? %( id="xref-#{refid}") : nil
        if (refs = doc.references[:refs])
          if ::Asciidoctor::AbstractNode === (ref = refs[refid])
            xreftext = text || ref.xreftext((@xrefstyle ||= (doc.attr 'xrefstyle')))
          end
        else
          xreftext = doc.references[:ids][refid]
        end

        if xreftext
          text ||= xreftext
        else
          # FIXME we get false negatives for reference to bibref when using Asciidoctor < 1.5.6
          warn %(asciidoctor: WARNING: #{::File.basename(doc.attr 'docfile')}: invalid reference to unknown local anchor (or valid bibref): #{refid})
        end
      end
      %(<a#{id_attr} href="#{target}" class="xref">#{text || "[#{refid}]"}</a>)
    when :ref
      %(<a id="#{target}"></a>)
    when :link
      %(<a href="#{target}" class="link">#{node.text}</a>)
    when :bibref
      if @xrefs_seen.include? target
        %(<a id="#{target}" href="#xref-#{target}">[#{target}]</a>)
      else
        %(<a id="#{target}"></a>[#{target}])
      end
    end
  end

  def inline_break node
    %(#{node.text}<br/>)
  end

  def inline_button node
    %(<b class="button">[<span class="label">#{node.text}</span>]</b>)
  end

  def inline_callout node
    num = CalloutStartNum
    int_num = node.text.to_i
    (int_num - 1).times { num = num.next }
    %(<i class="conum" data-value="#{int_num}">#{num}</i>)
  end

  def inline_footnote node
    if (index = node.attr 'index')
      %(<sup class="noteref">[<a id="noteref-#{index}" href="#note-#{index}" epub:type="noteref">#{index}</a>]</sup>)
    elsif node.type == :xref
      %(<mark class="noteref" title="Unresolved note reference">#{node.text}</mark>)
    end
  end

  def inline_image node
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
      class_attr = %( class="#{node.role}") if node.role?
      %(<img src="#{target}" alt="#{node.attr 'alt'}"#{class_attr}/>)
    end
  end

  def inline_indexterm node
    node.type == :visible ? node.text : ''
  end

  def inline_kbd node
    if (keys = node.attr 'keys').size == 1
      %(<kbd>#{keys[0]}</kbd>)
    else
      key_combo = keys.map {|key| %(<kbd>#{key}</kbd>) }.join '+'
      %(<span class="keyseq">#{key_combo}</span>)
    end
  end

  def inline_menu node
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

  def inline_quoted node
    case node.type
    when :strong
      %(<strong>#{node.text}</strong>)
    when :emphasis
      %(<em>#{node.text}</em>)
    when :monospaced
      %(<code class="literal">#{node.text}</code>)
    when :double
      #%(&#x201c;#{node.text}&#x201d;)
      %(“#{node.text}”)
    when :single
      #%(&#x2018;#{node.text}&#x2019;)
      %(‘#{node.text}’)
    when :superscript
      %(<sup>#{node.text}</sup>)
    when :subscript
      %(<sub>#{node.text}</sub>)
    else
      node.text
    end
  end

  def convert_content node
    node.content_model == :simple ? %(<p>#{node.content}</p>) : node.content
  end

  # FIXME merge into with xml_sanitize helper
  def xml_sanitize value, target = :attribute
    sanitized = (value.include? '<') ? value.gsub(XmlElementRx, '').strip.tr_s(' ', ' ') : value
    if target == :plain && (sanitized.include? ';')
      sanitized = sanitized.gsub(CharEntityRx) { [$1.to_i].pack 'U*' } if sanitized.include? '&#'
      sanitized = sanitized.gsub(FromHtmlSpecialCharsRx, FromHtmlSpecialCharsMap)
    elsif target == :attribute
      sanitized = sanitized.gsub '"', '&quot;' if sanitized.include? '"'
    end
    sanitized
  end

  # TODO make check for last content paragraph a feature of Asciidoctor
  def mark_last_paragraph root
    return unless (last_block = root.blocks[-1])
    while last_block.context == :section && last_block.blocks?
      last_block = last_block.blocks[-1]
    end
    if last_block.context == :paragraph
      last_block.attributes['role'] = last_block.role? ? %(#{last_block.role} last) : 'last'
    end
    nil
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
      warn %(asciidoctor: ERROR: chapter uses a reserved ID: #{id}) if !synthetic && (ReservedIds.include? id)
      id
    end
  end
end

require_relative 'packager'

Extensions.register do
  if (document = @document).backend == 'epub3'
    document.attributes['spine'] = ''
    document.set_attribute 'listing-caption', 'Listing'
    if !(defined? ::AsciidoctorJ) && (::Gem::try_activate 'pygments.rb')
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
    # Only fire SpineItemProcessor for top-level include directives
    include_processor SpineItemProcessor.new(document)
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
