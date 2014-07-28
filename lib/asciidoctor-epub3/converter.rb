# encoding: UTF-8
require_relative 'spine_item_processor'
require_relative 'font_icon_map'

module Asciidoctor
module Epub3
class Converter
  include ::Asciidoctor::Converter
  include ::Asciidoctor::Writer
  register_for 'epub3'
  EOL = "\n"
  #WordJoiner = [8288].pack 'U*'
  WordJoiner = [65279].pack 'U*'
  NoBreakSpace = '&#xa0;'
  ThinNoBreakSpace = '&#x202f;'
  RightAngleQuote = '&#x203a;'

  XmlElementRx = /<\/?.+?>/
  CharEntityRx = /&#(\d{2,5});/
  NamedEntityRx = /&([A-Z]+);/
  UppercaseTagRx = /<(\/)?([A-Z]+)>/

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
    @xrefs_used = ::Set.new
    @icon_names = []
  end

  def convert node, name = nil
    if respond_to?(name ||= node.node_name)
      send name, node
    else
      warn %(conversion missing in epub3 backend for #{name})
    end
  end

  # TODO aggregate authors of spine document into authors attribute(s) on main document
  def navigation_document node, spine
    doctitle_sanitized = ((node.doctitle sanitize: true) || (node.attr 'untitled-label')).gsub WordJoiner, ''
    lines = [%(<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang = (node.attr 'lang', 'en')}" lang="#{lang}">
<head>
<meta charset="UTF-8"/>
<title>#{doctitle_sanitized}</title>
<link rel="stylesheet" type="text/css" href="styles/epub3.css"/>
<link rel="stylesheet" type="text/css" href="styles/epub3-css3-only.css" media="(min-device-width: 0px)"/>
</head>
<body>
<h1>#{doctitle_sanitized}</h1>
<nav epub:type="toc" id="toc">
<h2>#{node.attr 'toc-title'}</h2>
<ol>)]
    spine.each do |item|
      lines << %(<li><a href="#{item.id || (item.attr 'docname')}.xhtml">#{((item.doctitle sanitize: true) || (item.attr 'untitled-label')).gsub WordJoiner, ''}</a></li>)
    end
    lines << %(</ol>
</nav>
</body>
</html>)
    lines * EOL
  end

  def document node
    docid = node.id
    doctitle = node.doctitle || (node.attr 'untitled-label')
    doctitle_sanitized = ((node.doctitle sanitize: true) || (node.attr 'untitled-label')).gsub WordJoiner, ''

    if doctitle.include? ': '
      title, subtitle = doctitle.split ': ', 2
      subtitle_formatted = subtitle.gsub(WordJoiner, '').split(' ').map {|w| %(<b>#{w}</b>) } * ' '
    else
      # HACK until we get proper handling of title-only in CSS
      title = ''
      subtitle = doctitle
      subtitle_formatted = (subtitle.split ' ').map {|w| %(<b>#{w}</b>) } * ' '
    end
    title_upper = title.upcase
    # FIXME make this uppercase routine more intelligent, less fragile
    subtitle_formatted_upper = subtitle_formatted.upcase
        .gsub(UppercaseTagRx) { %(<#{$1}#{$2.downcase}>) }
        .gsub(NamedEntityRx) { %(&#{$1.downcase};) }

    author = node.attr 'author'
    username = node.attr 'username', 'default'
    # FIXME needs to resolve to the imagesdir of the spine document, not this document
    #imagesdir = (node.attr 'imagesdir', '.').chomp '/'
    #imagesdir = (imagesdir == '.' ? nil : %(#{imagesdir}/))
    imagesdir = 'images/'

    mark_last_paragraph node
    content = node.content

    # NOTE must run after content is resolved
    # NOTE pubtree requires icon CSS to be repeated inside <body> (or in a linked stylesheet); perhaps create dynamic CSS file?
    icon_css = unless @icon_names.empty?
      icon_defs = @icon_names.map {|name|
        %(.i-#{name}::before { content: "#{FontIconMap[name.tr('-', '_').to_sym]}"; })
      } * EOL
      %(<style>
#{icon_defs}
</style>
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
#{icon_css}<script type="text/javascript">
document.addEventListener('DOMContentLoaded', function(event) {
  var epubReader = navigator.epubReadingSystem;
  if (!epubReader) {
    if (window.parent == window || !(epubReader = window.parent.navigator.epubReadingSystem)) {
      return;
    }
  }
  document.body.setAttribute('class', epubReader.name.toLowerCase().replace(/ /g, '-'));
});
</script>
</head>
<body>
<section class="chapter" title="#{doctitle_sanitized.gsub '"', '&quot;'}" epub:type="chapter" id="#{docid}">
#{icon_css && (icon_css.sub '<style>', '<style scoped="scoped">')}<header>
<div class="chapter-header">
<p class="byline"><img src="#{imagesdir}avatars/#{username}.jpg"/> <b class="author">#{author}</b></p>
<h1 class="chapter-title">#{title_upper}#{subtitle ? %[ <small class="subtitle">#{subtitle_formatted_upper}</small>] : nil}</h1>
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

  # QUESTION use convert_content?
  def open node
    node.content
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
    head = node.title? ? %(<strong class="head">#{title = node.title}#{head_stop && title !~ /[[:punct:]]$/ ? head_stop : nil}</strong> ) : nil
    if role
      if node.has_role? 'signature'
        node.set_option 'hardbreaks'
      end
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

  def listing node
    figure_classes = ['listing']
    figure_classes << 'coalesce' if node.option? 'unbreakable'
    pre_classes = if node.style == 'source'
      ['source', %(language-#{node.attr 'language'})]
    else
      ['screen']
    end
    title_div = node.title? ? %(<figcaption>#{node.captioned_title}</figcaption>
) : nil
    # patches conums to fix extra or missing leading space
    # TODO apply this patch upstream to Asciidoctor
    %(<figure class="#{figure_classes * ' '}">
#{title_div}<pre class="#{pre_classes * ' '}"><code>#{node.content.gsub(/(?<! )<i class="conum"| +<i class="conum"/, ' <i class="conum"')}</code></pre>
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
    footer_content = []
    if attribution = (node.attr 'attribution')
      footer_content << attribution  
    end

    if citetitle = (node.attr 'citetitle')
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
    %(<div class="blockquote">
<blockquote>
#{content}#{footer_tag}
</blockquote>
</div>)
  end

  def verse node
    footer_content = []
    if attribution = (node.attr 'attribution')
      footer_content << attribution  
    end

    if citetitle = (node.attr 'citetitle')
      citetitle_sanitized = xml_sanitize citetitle
      footer_content << %(<cite title="#{citetitle_sanitized}">#{citetitle}</cite>)
    end

    footer_tag = footer_content.size > 0 ? %(
<span class="attribution">~ #{footer_content * ', '}</span>) : nil
    %(<div class="verse">
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
      title_upper = title.upcase.gsub(NamedEntityRx) { %(&#{$1.downcase};) }
      title_el = %(<h2>#{title_upper}</h2>
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
      'sides' => 'table-framed-sides'
    }
    grid_class = {
      'all' => 'table-grid',
      'rows' => 'table-grid-rows',
      'cols' => 'table-grid-cols'
    }
    table_classes = %W(table #{frame_class[(node.attr 'frame')] || frame_class['topbot']} #{grid_class[(node.attr 'grid')] || grid_class['rows']})
    if (role = node.role)
      table_classes << role
    end
    table_class_attr = %( class="#{table_classes * ' '}")
    table_styles = []
    unless node.option? 'autowidth'
      table_styles << %(width: #{node.attr 'tablepcwidth'}%;)
    end
    table_style_attr = table_styles.size > 0 ? %( style="#{table_styles * ' '}") : nil

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
      #    lines << %(<col style="width: #{col.attr 'colpcwidth'}%;"/>)
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
                cell_content = %(<div>#{cell.content}</div>)
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
            cell_style_attr = (node.document.attr? 'cellbgcolor') ? %( style="background-color: #{node.document.attr 'cellbgcolor'};") : nil
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
    num = "\u2460"
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
            lines << dd.text
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
    lines << %(<h3>#{node.title}</h3>) if node.title?
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
    # TODO could strip WordJoiner if brief since not using justify
    ul_classes = [node.style, ((node.option? 'brief') ? 'brief' : nil)].compact
    ul_class_attr = ul_classes.empty? ? nil : %( class="#{ul_classes * ' '}")
    id_attribute = node.id ? %( id="#{node.id}") : nil
    lines = [%(<div#{id_attribute} class="#{div_classes * ' '}">)]
    lines << %(<h3>#{node.title}</h3>) if node.title?
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
      img_attrs << %(style="width: #{node.attr 'scaledwidth', '100%'};")
      # TODO make this a convenience method on document
      epub_properties = (node.document.attr 'epub-properties') || []
      unless epub_properties.include? 'svg'
        epub_properties << 'svg'
        node.document.attributes['epub-properties'] = epub_properties
      end
    else
      if node.attr? 'scaledwidth'
        img_attrs << %(style="width: #{node.attr 'scaledwidth'};")
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
        img_attrs << %(height="#{node.attr 'scaledheight'}" style="max-height: #{node.attr 'scaledheight'} !important;")
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
    when :xref
      refid = (node.attr 'refid') || target
      id_attr = unless @xrefs_used.include? refid
        @xrefs_used << refid
        %( id="xref-#{refid}")
      end
      # FIXME seems like text should be prepared already
      # FIXME would be nice to know what type the target is (e.g., bibref)
      text = node.text || (node.document.references[:ids][refid] || %([#{refid}]))
      %(<a#{id_attr} href="#{target}" class="xref">#{text}</a>#{WordJoiner})
    when :ref
      %(<a id="#{target}"></a>)
    when :link
      %(<a href="#{target}" class="link">#{node.text}</a>#{WordJoiner})
    when :bibref
      %(<a id="#{target}" href="#xref-#{target}">[#{target}]</a>#{WordJoiner})
    end
  end

  def inline_break node
    %(#{node.text}<br/>)
  end

  def inline_button node
    %(<b class="button">[<span class="label">#{node.text}</span>]</b>#{WordJoiner})
  end

  def inline_callout node
    num = "\u2460"
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
    if (type = node.type) == 'icon'
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
      key_combo = keys.map {|key| %(<kbd>#{key}</kbd>+) }.join.chop
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
      %(<strong>#{node.text}</strong>#{WordJoiner})
    when :emphasis
      %(<em>#{node.text}</em>#{WordJoiner})
    when :monospaced
      %(<code class="literal">#{node.text}</code>#{WordJoiner})
    when :double
      #%(&#x201c;#{node.text}&#x201d;)
      %(“#{node.text}”)
    when :single
      #%(&#x2018;#{node.text}&#x2019;)
      %(‘#{node.text}’)
    when :superscript
      %(<sup>#{node.text}</sup>#{WordJoiner})
    when :subscript
      %(<sub>#{node.text}</sub>#{WordJoiner})
    else
      node.text
    end
  end

  def convert_content node
    if node.content_model == :simple
      %(<p>#{node.content}</p>)
    else
      node.content
    end
  end

  # TODO generating this id should be part of Asciidoctor API
  def resolve_document_id node
    unless (doc_id = node.id)
      doc_id = if node.header?
        node.doctitle(sanitize: true).gsub(WordJoiner, '').downcase.delete(':').tr_s(' ', '-').tr_s('-', '-')
      elsif (first_section = node.first_section)
        first_section.id
      else
        %(document-#{node.object_id})
      end
    end
    doc_id
  end

  def xml_sanitize value, target = :attribute
    sanitized = (value.include? '<') ? value.gsub(XmlElementRx, '').tr_s(' ', ' ').strip : value
    if target == :plain && (sanitized.include? ';')
      sanitized = sanitized.gsub(CharEntityRx) { [$1.to_i].pack('U*') }.gsub(FromHtmlSpecialCharsRx, FromHtmlSpecialCharsMap)
    elsif target == :attribute
      sanitized = sanitized.gsub(WordJoiner, '').gsub('"', '&quot;')
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

  def write output, target
    #if @nav
    #  target = ::File.join ::File.dirname(target), 'nav.xhtml'
    #end
    ::File.open target, 'w' do |fd|
      fd.write output
    end
  end

  def self.convert_file source_file, options = {}
    require_relative 'packager' unless defined? Packager
    # QUESTION should we force the doctype to book?
    options = options.merge(backend: :epub3, header_footer: true)
    ebook_format = if (format = options.delete :ebook_format)
      (format = format.to_sym) == :mobi ? :kf8 : format
    else
      :epub3
    end
    validate = options.delete :validate
    extract = options.delete :extract
    # TODO if to_dir not given, make and use tmp directory
    to_dir = ::File.expand_path(options.delete(:to_dir) || ::Dir.pwd)
    # TODO handle case that attributes is not a string
    options[:attributes] = %(spine ebook-format=#{ebook_format} ebook-format-#{ebook_format} #{options[:attributes]})
    # FIXME honor existing registry
    options[:extensions_registry] = ::Asciidoctor::Extensions.build_registry :epub3 do
      # NOTE register directly on spine document so it only fires for top-level includes
      # NOTE the SpineItemProcessor needs access to the document instance
      include_processor SpineItemProcessor.new @document
    end
    spine_doc = ::Asciidoctor.load_file source_file, options
    # restore attributes to those defined in the document header
    spine_doc.restore_attributes
    # REVIEW reaching into converter to assign document id feels like a hack; should happen in Asciidoctor parser
    spine_doc.id = spine_doc.converter.resolve_document_id spine_doc
    packager = Packager.new spine_doc, (spine_doc.references[:spine_items] || [spine_doc]), to_dir, ebook_format
    packager.package validate: validate, extract: extract
  end
end
end
end

# FIXME: this include processor to replace tabs with spaces does not honor partial includes!
=begin
Asciidoctor::Extensions.register {
  doc = @document
  include_processor do
    process do |reader, target, attributes|
      source = File.read File.join(doc.base_dir, target)
      # TODO substitute tabs more carefully
      reader.push_include source.gsub("\t", '    '), target, target, 1, attributes
      reader
    end

    def handles? target
      target.start_with? 'code/'
    end
  end
}
=end
