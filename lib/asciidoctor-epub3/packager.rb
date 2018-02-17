require_relative 'core_ext/string'
autoload :FileUtils, 'fileutils'
autoload :Open3, 'open3'
autoload :Shellwords, 'shellwords'

module Asciidoctor
module Epub3
module GepubBuilderMixin
  DATA_DIR = ::File.expand_path(::File.join ::File.dirname(__FILE__), '..', '..', 'data')
  SAMPLES_DIR = ::File.join DATA_DIR, 'samples'
  CharEntityRx = ContentConverter::CharEntityRx
  XmlElementRx = ContentConverter::XmlElementRx
  FromHtmlSpecialCharsMap = ContentConverter::FromHtmlSpecialCharsMap
  FromHtmlSpecialCharsRx = ContentConverter::FromHtmlSpecialCharsRx
  CsvDelimiterRx = /\s*,\s*/
  DefaultCoverImage = 'images/default-cover.png'
  ImageMacroRx = /^image::?(.*?)\[(.*?)\]$/
  ImgSrcScanRx = /<img src="(.+?)"/
  SvgImgSniffRx = /<img src=".+?\.svg"/

  attr_reader :book, :format, :spine

  # FIXME move to Asciidoctor::Helpers
  def sanitize_doctitle_xml doc, content_spec
    doctitle = doc.header? ? doc.doctitle : (doc.attr 'untitled-label')
    sanitize_xml doctitle, content_spec
  end

  # FIXME move to Asciidoctor::Helpers
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

  def add_theme_assets doc
    builder = self
    format = @format
    workdir = if doc.attr? 'epub3-stylesdir'
      stylesdir = doc.attr 'epub3-stylesdir'
      # FIXME make this work for Windows paths!!
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

    # TODO improve design/UX of custom theme functionality, including custom fonts
    resources do
      if format == :kf8
        # NOTE add layer of indirection so Kindle Direct Publishing (KDP) doesn't strip font-related CSS rules
        file 'styles/epub3.css' => '@import url("epub3-proxied.css");'.to_ios
        file 'styles/epub3-css3-only.css' => '@import url("epub3-css3-only-proxied.css");'.to_ios
        file 'styles/epub3-proxied.css' => (builder.postprocess_css_file ::File.join(workdir, 'epub3.css'), format)
        file 'styles/epub3-css3-only-proxied.css' => (builder.postprocess_css_file ::File.join(workdir, 'epub3-css3-only.css'), format)
      else
        file 'styles/epub3.css' => (builder.postprocess_css_file ::File.join(workdir, 'epub3.css'), format)
        file 'styles/epub3-css3-only.css' => (builder.postprocess_css_file ::File.join(workdir, 'epub3-css3-only.css'), format)
      end
    end

    resources do
      font_files, font_css = builder.select_fonts ::File.join(DATA_DIR, 'styles/epub3-fonts.css'), (doc.attr 'scripts', 'latin')
      file 'styles/epub3-fonts.css' => font_css
      unless font_files.empty?
        # NOTE metadata property in oepbs package manifest doesn't work; must use proprietary iBooks file instead
        #(@book.metadata.add_metadata 'meta', 'true')['property'] = 'ibooks:specified-fonts' unless format == :kf8
        builder.optional_file 'META-INF/com.apple.ibooks.display-options.xml' => '<?xml version="1.0" encoding="UTF-8"?>
<display_options>
<platform name="*">
<option name="specified-fonts">true</option>
</platform>
</display_options>'.to_ios unless format == :kf8

        # https://github.com/asciidoctor/asciidoctor-epub3/issues/120
        #
        # 'application/x-font-ttf' causes warnings in epubcheck 4.0.2,
        # "non-standard font type". Discussion:
        # https://www.mobileread.com/forums/showthread.php?t=231272
        #
        # 3.1 spec recommends 'application/font-sfnt', but epubcheck doesn't
        # implement that yet (warnings). https://idpf.github.io/epub-cmt/v3/
        #
        # 3.0 spec recommends 'application/vnd.ms-opentype', this works without
        # warnings.
        # http://www.idpf.org/epub/30/spec/epub30-publications.html#sec-core-media-types
        with_media_type 'application/vnd.ms-opentype' do
          font_files.each do |font_file|
            file font_file => ::File.join(DATA_DIR, font_file)
          end
        end
      end
    end
    nil
  end

  def add_cover_image doc
    imagesdir = (doc.attr 'imagesdir', '.').chomp '/'
    imagesdir = (imagesdir == '.' ? nil : %(#{imagesdir}/))

    if (image_path = doc.attr 'front-cover-image')
      image_attrs = {}
      if (image_path.include? ':') && image_path =~ ImageMacroRx
        if image_path.start_with? 'image::'
          warn %(asciidoctor: WARNING: deprecated block macro syntax detected in front-cover-image attribute)
        end
        image_path = %(#{imagesdir}#{$1})
        (::Asciidoctor::AttributeList.new $2).parse_into image_attrs, %w(alt width height) unless $2.empty?
      end
      workdir = (workdir = doc.attr 'docdir').nil_or_empty? ? '.' : workdir
      if ::File.readable?(::File.join workdir, image_path)
        unless !image_attrs.empty? && (width = image_attrs['width']) && (height = image_attrs['height'])
          width, height = 1050, 1600
        end
      else
        warn %(asciidoctor: ERROR: #{::File.basename(doc.attr 'docfile')}: front cover image not found or readable: #{::File.expand_path image_path, workdir})
        image_path = nil
      end
    end

    unless image_path
      image_path, workdir, width, height = DefaultCoverImage, DATA_DIR, 1050, 1600
    end

    resources do
      cover_image %(#{imagesdir}jacket/cover#{::File.extname image_path}) => (::File.join workdir, image_path)
      @last_defined_item.tap do |last_item|
        last_item['width'] = width
        last_item['height'] = height
      end
    end
    nil
  end

  # NOTE must be called within the ordered block
  def add_cover_page doc, spine_builder, manifest
    cover_item_attrs = manifest.items['item_cover'].instance_variable_get :@attributes
    href = cover_item_attrs['href']
    # NOTE we only store width and height temporarily to pass through the values
    width = cover_item_attrs.delete 'width'
    height = cover_item_attrs.delete 'height'

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
<image width="#{width}" height="#{height}" xlink:href="#{href}"/>
</svg></body>
</html>).to_ios
    # Gitden expects a cover.xhtml, so add it to the spine
    spine_builder.file 'cover.xhtml' => content
    assigned_id = (spine_builder.instance_variable_get :@last_defined_item).item.id
    spine_builder.id 'cover'
    # clearly a deficiency of gepub that it does not match the id correctly
    # FIXME can we move this hack elsewhere?
    @book.spine.itemref_by_id[assigned_id].idref = 'cover'
    nil
  end

  def add_images_from_front_matter
    (::File.read 'front-matter.html').scan ImgSrcScanRx do
      resources do
        file $1
      end
    end if ::File.file? 'front-matter.html'
    nil
  end

  def add_front_matter_page doc, spine_builder
    if ::File.file? 'front-matter.html'
      front_matter_content = ::File.read 'front-matter.html'
      spine_builder.file 'front-matter.xhtml' => (postprocess_xhtml front_matter_content, @format)
      unless (spine_builder.property? 'svg') || SvgImgSniffRx !~ front_matter_content
        spine_builder.add_property 'svg'
      end
    end
    nil
  end

  def add_content_images doc, images
    docimagesdir = (doc.attr 'imagesdir', '.').chomp '/'
    docimagesdir = (docimagesdir == '.' ? nil : %(#{docimagesdir}/))

    workdir = (workdir = doc.attr 'docdir').nil_or_empty? ? '.' : workdir
    resources workdir: workdir do
      images.each do |image|
        if (image_path = image[:path]).start_with? %(#{docimagesdir}jacket/cover.)
          warn %(asciidoctor: WARNING: image path is reserved for cover artwork: #{image_path}; skipping image found in content)
        elsif ::File.readable? image_path
          file image_path
        else
          warn %(asciidoctor: ERROR: #{::File.basename image[:docfile]}: image not found or not readable: #{::File.expand_path image_path, workdir})
        end
      end
    end
    nil
  end

  def add_profile_images doc, usernames
    imagesdir = (doc.attr 'imagesdir', '.').chomp '/'
    imagesdir = (imagesdir == '.' ? nil : %(#{imagesdir}/))

    resources do
      file %(#{imagesdir}avatars/default.jpg) => ::File.join(DATA_DIR, 'images/default-avatar.jpg')
      file %(#{imagesdir}headshots/default.jpg) => ::File.join(DATA_DIR, 'images/default-headshot.jpg')
    end

    workdir = (workdir = doc.attr 'docdir').nil_or_empty? ? '.' : workdir
    resources do
      usernames.each do |username|
        avatar = %(#{imagesdir}avatars/#{username}.jpg)
        if ::File.readable?(resolved_avatar = ::File.join(workdir, avatar))
          file avatar => resolved_avatar
        else
          warn %(asciidoctor: ERROR: avatar for #{username} not found or readable: #{avatar}; falling back to default avatar)
          file avatar => ::File.join(DATA_DIR, 'images/default-avatar.jpg')
        end

        headshot = %(#{imagesdir}headshots/#{username}.jpg)
        if ::File.readable?(resolved_headshot = ::File.join(workdir, headshot))
          file headshot => resolved_headshot
        elsif doc.attr? 'builder', 'editions'
          warn %(asciidoctor: ERROR: headshot for #{username} not found or readable: #{headshot}; falling back to default headshot)
          file headshot => ::File.join(DATA_DIR, 'images/default-headshot.jpg')
        end
      end
    end
    nil
  end

  def add_content doc
    builder, spine, format, images = self, @spine, @format, {}
    workdir = (doc.attr 'docdir').nil_or_empty? ? '.' : workdir
    resources workdir: workdir do
      extend GepubResourceBuilderMixin
      builder.add_images_from_front_matter
      builder.add_nav_doc doc, self, spine, format
      builder.add_ncx_doc doc, self, spine
      ordered do
        builder.add_cover_page doc, self, @book.manifest unless format == :kf8
        builder.add_front_matter_page doc, self
        spine.each_with_index do |item, i|
          docfile = item.attr 'docfile'
          imagesdir = (item.attr 'imagesdir', '.').chomp '/'
          imagesdir = (imagesdir == '.' ? '' : %(#{imagesdir}/))
          file %(#{item.id || (item.attr 'docname')}.xhtml) => (builder.postprocess_xhtml item.convert, format)
          add_property 'svg' if ((item.attr 'epub-properties') || []).include? 'svg'
          # QUESTION should we pass the document itself?
          item.references[:images].each do |target|
            images[image_path = %(#{imagesdir}#{target})] ||= { docfile: docfile, path: image_path }
          end
          # QUESTION reenable?
          #linear 'yes' if i == 0
        end
      end
    end
    add_content_images doc, images.values
    nil
  end

  def add_nav_doc doc, spine_builder, spine, format
    spine_builder.nav 'nav.xhtml' => (postprocess_xhtml nav_doc(doc, spine), format)
    spine_builder.id 'nav'
    nil
  end

  # TODO aggregate authors of spine document into authors attribute(s) on main document
  def nav_doc doc, spine
    lines = [%(<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang = (doc.attr 'lang', 'en')}" lang="#{lang}">
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
    lines << (nav_level spine, [(doc.attr 'toclevels', 1).to_i, 0].max)
    lines << %(</nav>
</body>
</html>)
    lines * EOL
  end

  def nav_level items, depth, state = {}
    lines = []
    lines << '<ol>'
    items.each do |item|
      #index = (state[:index] = (state.fetch :index, 0) + 1)
      if item.context == :document
        # NOTE we sanitize the chapter titles because we use formatting to control layout
        item_label = sanitize_doctitle_xml item, :cdata
        item_href = (state[:content_doc_href] = %(#{item.id || (item.attr 'docname')}.xhtml))
      else
        item_label = sanitize_xml item.title, :pcdata
        item_href = %(#{state[:content_doc_href]}##{item.id})
      end
      lines << %(<li><a href="#{item_href}">#{item_label}</a>)
      unless depth == 0 || (child_sections = item.sections).empty?
        lines << (nav_level child_sections, depth - 1, state)
        lines << '</li>'
      else
        lines[-1] = %(#{lines[-1]}</li>)
      end
      state.delete :content_doc_href if item.context == :document
    end
    lines << '</ol>'
    lines * EOL
  end

  # NOTE gepub doesn't support building a ncx TOC with depth > 1, so do it ourselves
  def add_ncx_doc doc, spine_builder, spine
    spine_builder.file 'toc.ncx' => (ncx_doc doc, spine).to_ios
    spine_builder.id 'ncx'
    nil
  end

  def ncx_doc doc, spine
    # TODO populate docAuthor element based on unique authors in work
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
    lines << (ncx_level spine, [(doc.attr 'toclevels', 1).to_i, 0].max, state = {})
    lines[0] = lines[0].sub '%{depth}', %(<meta name="dtb:depth" content="#{state[:max_depth]}"/>)
    lines << %(</navMap>
</ncx>)
    lines * EOL
  end

  def ncx_level items, depth, state = {}
    lines = []
    state[:max_depth] = (state.fetch :max_depth, 0) + 1
    items.each do |item|
      index = (state[:index] = (state.fetch :index, 0) + 1)
      if item.context == :document
        item_id = %(nav_#{index})
        item_label = sanitize_doctitle_xml item, :cdata
        item_href = (state[:content_doc_href] = %(#{item.id || (item.attr 'docname')}.xhtml))
      else
        item_id = %(nav_#{index})
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
      state.delete :content_doc_href if item.context == :document
    end
    lines * EOL
  end

  def collect_keywords doc, spine
    ([doc] + spine).map do |item|
      if item.attr? 'keywords'
        (item.attr 'keywords').split CsvDelimiterRx
      else
        []
      end
    end.flatten.uniq
  end

  # Swap fonts in CSS based on the value of the document attribute 'scripts',
  # then return the list of fonts as well as the font CSS.
  def select_fonts filename, scripts = 'latin'
    font_css = ::File.read(filename)
    font_css = font_css.gsub(/(?<=-)latin(?=\.ttf\))/, scripts) unless scripts == 'latin'

    # match CSS font urls in the forms of:
    # src: url(../fonts/notoserif-regular-latin.ttf);
    # src: url(../fonts/notoserif-regular-latin.ttf) format("truetype");
    font_list = font_css.scan(/url\(\.\.\/([^)]+\.ttf)\)/).flatten

    return [font_list, font_css.to_ios]
  end

  def postprocess_css_file filename, format
    return filename unless format == :kf8
    postprocess_css ::File.read(filename), format
  end

  def postprocess_css content, format
    return content.to_ios unless format == :kf8
    # TODO convert regular expressions to constants
    content
        .gsub(/^  -webkit-column-break-.*\n/, '')
        .gsub(/^  max-width: .*\n/, '')
        .to_ios
  end

  def postprocess_xhtml_file filename, format
    return filename unless format == :kf8
    postprocess_xhtml ::File.read(filename), format
  end

  # NOTE Kindle requires that
  #      <meta charset="utf-8"/>
  #      be converted to
  #      <meta http-equiv="Content-Type" content="application/xml+xhtml; charset=UTF-8"/>
  def postprocess_xhtml content, format
    return content.to_ios unless format == :kf8
    # TODO convert regular expressions to constants
    content
        .gsub(/<meta charset="(.+?)"\/>/, '<meta http-equiv="Content-Type" content="application/xml+xhtml; charset=\1"/>')
        .gsub(/<img([^>]+) style="width: (\d\d)%;"/, '<img\1 style="width: \2%; height: \2%;"')
        .gsub(/<script type="text\/javascript">.*?<\/script>\n?/m, '')
        .to_ios
  end
end

module GepubResourceBuilderMixin
  # Add missing method to builder to add a property to last defined item
  def add_property property
    @last_defined_item.add_property property
  end

  # Add helper method to builder to check if property is set on last defined item
  def property? property
    (@last_defined_item['properties'] || []).include? property
  end
end

class Packager
  KINDLEGEN = ENV['KINDLEGEN'] || 'kindlegen'
  EPUBCHECK = ENV['EPUBCHECK'] || %(epubcheck#{::Gem.win_platform? ? '.bat' : '.sh'})
  EpubExtensionRx = /\.epub$/i
  KindlegenCompression = ::Hash['0', '-c0', '1', '-c1', '2', '-c2', 'none', '-c0', 'standard', '-c1', 'huffdic', '-c2']

  def initialize spine_doc, spine, format = :epub3, options = {}
    @document = spine_doc
    @spine = spine || []
    @format = format
  end

  def package options = {}
    doc = @document
    spine = @spine
    fmt = @format
    target = options[:target]
    dest = File.dirname target

    # FIXME authors should be aggregated already on parent document
    authors = if doc.attr? 'authors'
      (doc.attr 'authors').split(GepubBuilderMixin::CsvDelimiterRx).concat(spine.map {|item| item.attr 'author' }.compact).uniq
    else
      []
    end

    builder = ::GEPUB::Builder.new do
      extend GepubBuilderMixin
      @document = doc
      @spine = spine
      @format = fmt
      @book.epub_backward_compat = (fmt != :kf8)

      language(doc.attr 'lang', 'en')
      id 'pub-language'

      if doc.attr? 'uuid'
        unique_identifier doc.attr('uuid'), 'pub-identifier', 'uuid'
      else
        unique_identifier doc.id, 'pub-identifier', 'uuid'
      end
      # replace with next line once the attributes argument is supported
      #unique_identifier doc.id, 'pub-id', 'uuid', 'scheme' => 'xsd:string'

      # NOTE we must use :plain_text here since gepub reencodes
      title(sanitize_doctitle_xml doc, :plain_text)
      id 'pub-title'

      # FIXME this logic needs some work
      if doc.attr? 'publisher'
        publisher(publisher_name = doc.attr('publisher'))
        # marc role: Book producer (see http://www.loc.gov/marc/relators/relaterm.html)
        creator doc.attr('producer', publisher_name), 'bkp'
      else
        # NOTE Use producer as both publisher and producer if publisher isn't specified
        if doc.attr? 'producer'
          producer_name = doc.attr 'producer'
          publisher producer_name
          # marc role: Book producer (see http://www.loc.gov/marc/relators/relaterm.html)
          creator producer_name, 'bkp'
        # NOTE Use author as creator if both publisher or producer are absent
        elsif doc.attr? 'author'
          # marc role: Author (see http://www.loc.gov/marc/relators/relaterm.html)
          creator doc.attr('author'), 'aut'
        end
      end

      if doc.attr? 'creator'
        # marc role: Creator (see http://www.loc.gov/marc/relators/relaterm.html)
        creator doc.attr('creator'), 'cre'
      else
        # marc role: Manufacturer (see http://www.loc.gov/marc/relators/relaterm.html)
        # QUESTION should this be bkp?
        creator 'Asciidoctor', 'mfr'
      end

      # TODO getting author list should be a method on Asciidoctor API
      contributors(*authors)

      if doc.attr? 'revdate'
        # TODO ensure this is a real date
        date(doc.attr 'revdate')
      else
        date ::Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')
      end

      if doc.attr? 'description'
        description(doc.attr 'description')
      end

      (collect_keywords doc, spine).each do |s|
        subject s
      end

      if doc.attr? 'source'
        source(doc.attr 'source')
      end

      if doc.attr? 'copyright'
        rights(doc.attr 'copyright')
      end

      #add_metadata 'ibooks:specified-fonts', true

      add_theme_assets doc
      add_cover_image doc
      if (doc.attr 'publication-type', 'book') != 'book'
        usernames = spine.map {|item| item.attr 'username' }.compact.uniq
        add_profile_images doc, usernames
      end
      add_content doc
    end

    ::FileUtils.mkdir_p dest unless ::File.directory? dest

    epub_file = fmt == :kf8 ? %(#{::Asciidoctor::Helpers.rootname target}-kf8.epub) : target
    builder.generate_epub epub_file
    puts %(Wrote #{fmt.upcase} to #{epub_file}) if $VERBOSE
    if options[:extract]
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
      puts %(Extracted #{fmt.upcase} to #{extract_dir}) if $VERBOSE
    end

    if fmt == :kf8
      # QUESTION shouldn't we validate this epub file too?
      distill_epub_to_mobi epub_file, target, options[:compress]
    elsif options[:validate]
      validate_epub epub_file
    end
  end

  def distill_epub_to_mobi epub_file, target, compress
    kindlegen_cmd = KINDLEGEN
    unless ::File.executable? kindlegen_cmd
      require 'kindlegen' unless defined? ::Kindlegen
      kindlegen_cmd = ::Kindlegen.command
    end
    mobi_file = ::File.basename(target.sub EpubExtensionRx, '.mobi')
    compress_flag = KindlegenCompression[compress ? (compress.empty? ? '1' : compress.to_s) : '0']
    cmd = [kindlegen_cmd, '-dont_append_source', compress_flag, '-o', mobi_file, epub_file].compact
    ::Open3.popen2e(::Shellwords.join cmd) {|input, output, wait_thr|
      output.each {|line| puts line } unless $VERBOSE.nil?
    }
    puts %(Wrote MOBI to #{::File.join ::File.dirname(epub_file), mobi_file}) if $VERBOSE
  end

  def validate_epub epub_file
    epubcheck_cmd = EPUBCHECK
    unless ::File.executable? epubcheck_cmd
      epubcheck_cmd = ::Gem.bin_path 'epubcheck', 'epubcheck'
    end
    # NOTE epubcheck gem doesn't support epubcheck command options; enable -quiet once supported
    ::Open3.popen2e(::Shellwords.join [epubcheck_cmd, epub_file]) {|input, output, wait_thr|
      output.each {|line| puts line } unless $VERBOSE.nil?
    }
  end
end
end
end
