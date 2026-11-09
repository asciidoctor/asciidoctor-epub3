# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Footnote reference IDs' do
  def chapter_with_note(book)
    book.items.values.find { |item| item.href.end_with?('.xhtml') && item.content.include?('<aside ') }
  end

  def check_note_targets(xml)
    ids = xml.xpath('//@id').map(&:value)
    expect(ids.uniq).to eq ids
    xml.xpath('//*[local-name()="aside"]').each do |note|
      backlink = note.at_xpath './/*[local-name()="a"]'
      expect(backlink).not_to be_nil
      targets = xml.xpath '//*[local-name()="a"]'
      targets = targets.select { |a| %(##{a['id']}) == backlink['href'] }
      expect(targets.size).to eq 1
      expect(targets[0].attribute_with_ns('type', 'http://www.idpf.org/2007/ops').value).to eq 'noteref'
      expect(targets[0]['href']).to eq %(##{note['id']})
    end
  end

  it 'keeps an author ID after an anonymous definition without colliding' do
    book = to_epub "= Book\n\nOne.footnote:[First.] Two.footnote:noteref-1[Second.]"
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    expect(xml.at_xpath('//*[@id="noteref-1"]')['href']).to eq '#note-2'
    check_note_targets xml
  end

  it 'keeps an author ID before an anonymous definition without colliding' do
    book = to_epub "= Book\n\nOne.footnote:noteref-2[First.] Two.footnote:[Second.]"
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    expect(xml.at_xpath('//*[@id="noteref-2"]')['href']).to eq '#note-1'
    check_note_targets xml
  end

  it 'reserves author anchors even when they occur later in the chapter' do
    book = to_epub <<~EOS
      = Book

      One.footnote:[First.]

      [[noteref-1]]
      Reserved block.

      Second anchor:noteref-1_[]reserved inline anchor.
    EOS
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    expect(xml.xpath('//*[@id="noteref-1"]').size).to eq 1
    expect(xml.xpath('//*[@id="noteref-1_"]').size).to eq 1
    expect(xml.at_xpath('//*[@id="note-1"]//*[local-name()="a"]')['href']).to eq '#noteref-1__'
    check_note_targets xml
  end

  it 'preserves an author ID in passthrough markup without colliding' do
    book = to_epub <<~EOS
      = Book

      One.footnote:[First.]

      ++++
      <span id='noteref-1'>Reserved author anchor.</span>
      ++++
    EOS
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    expect(xml.at_xpath('//*[@id="noteref-1"]').name).to eq 'span'
    expect(xml.at_xpath('//*[@id="note-1"]//*[local-name()="a"]')['href']).to eq '#noteref-1_'
    check_note_targets xml
  end

  it 'preserves an authored link to the named definition when disambiguating' do
    book = to_epub <<~EOS
      = Book

      One.footnote:[First.] Two.footnote:noteref-1[Second.]

      pass:[<a href="#noteref-1">1</a>]

      Last paragraph.
    EOS
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    expect(xml.xpath('//*[local-name()="p"]/*[local-name()="a" and text()="1" and @href="#noteref-1"]').size).to eq 1
    check_note_targets xml
  end

  it 'preserves an earlier authored link with the same ID and note destination' do
    book = to_epub <<~EOS
      = Book

      pass:[<a id="noteref-1" href="#note-1">Jump to note</a>] before One.footnote:[First.]
    EOS
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    authored = xml.at_xpath '//*[local-name()="a" and text()="Jump to note"]'
    expect(authored['id']).to eq 'noteref-1'
    expect(authored['href']).to eq '#note-1'
    expect(authored.attribute_with_ns('type', 'http://www.idpf.org/2007/ops')).to be_nil
    defining = xml.at_xpath '//*[local-name()="sup" and @class="noteref"]/*[local-name()="a"]'
    expect(defining['id']).to eq 'noteref-1_'
    expect(defining.attribute_with_ns('type', 'http://www.idpf.org/2007/ops').value).to eq 'noteref'
    expect(xml.at_xpath('//*[@id="note-1"]//*[local-name()="a"]')['href']).to eq %(##{defining['id']})
    check_note_targets xml
  end

  it 'distinguishes an authored noteref lookalike from the defining reference' do
    book = to_epub <<~EOS
      = Book

      pass:[<sup class="noteref">[<a id="noteref-1" href="#note-1" epub:type="noteref">1</a>]</sup>] before One.footnote:[First.]
    EOS
    xml = Nokogiri::XML book.item_by_href('_book.xhtml').content
    references = xml.xpath '//*[local-name()="sup" and @class="noteref"]/*[local-name()="a"]'
    expect(references.size).to eq 2
    expect(references.map { |reference| reference['id'] }).to eq %w[noteref-1 noteref-1_]
    expect(references.map { |reference| reference['href'] }).to eq %w[#note-1 #note-1]
    expect(xml.at_xpath('//*[@id="note-1"]//*[local-name()="a"]')['href']).to eq '#noteref-1_'
    check_note_targets xml
  end

  it 'keeps anonymous reference output reproducible without temporary IDs' do
    input = "= Book\n:reproducible:\n\nOne.footnote:[First.] Two.footnote:noteref-1[Second.]"
    first = to_epub(input).item_by_href('_book.xhtml').content
    second = to_epub(input).item_by_href('_book.xhtml').content
    expect(first).to eq second
    expect(first).not_to include 'epub3-noteref-'
    check_note_targets Nokogiri::XML(first)
  end

  it 'keeps a document title note only in its visible defining heading' do
    book = to_epub <<~EOS
      = Book footnote:[A title note.]
      :reproducible:

      pass:[<a id="noteref-1" href="#note-1">Authored jump</a>]
    EOS
    chapter = chapter_with_note book
    xml = Nokogiri::XML chapter.content
    expect(xml.at_xpath('//*[local-name()="title"]').text).to eq 'Book'
    expect(xml.at_xpath('//*[local-name()="title"]').element_children).to be_empty
    defining = xml.at_xpath '//*[local-name()="h1"]//*[local-name()="a" and @epub:type="noteref"]', 'epub' => 'http://www.idpf.org/2007/ops'
    expect(defining['id']).to eq 'noteref-1_'
    expect(xml.at_xpath('//*[@id="noteref-1"]').text).to eq 'Authored jump'
    expect(xml.at_xpath('//*[@id="noteref-1"]')['href']).to eq '#note-1'
    expect(xml.at_xpath('//*[local-name()="section" and @class="chapter"]')['title']).to eq 'Book'
    check_note_targets xml
    expect(book.title.content).to eq 'Book'
    expect(chapter.content).not_to include 'epub3-noteref-'
  end

  it 'keeps chapter title notes out of metadata and navigation labels' do
    book = to_epub <<~EOS
      = Book
      :doctype: book
      :toc:
      :reproducible:

      == Chapter footnote:[A chapter note.]

      pass:[<a id="noteref-1" href="#note-1">Authored jump</a>]
    EOS
    chapter = chapter_with_note book
    xml = Nokogiri::XML chapter.content
    expect(xml.at_xpath('//*[local-name()="title"]').text).to eq 'Chapter'
    expect(xml.at_xpath('//*[local-name()="title"]').element_children).to be_empty
    expect(xml.at_xpath('//*[local-name()="h1"]//*[@epub:type="noteref"]', 'epub' => 'http://www.idpf.org/2007/ops')['id']).to eq 'noteref-1_'
    check_note_targets xml
    %w[nav.xhtml toc.xhtml].each do |href|
      navigation = Nokogiri::XML book.item_by_href(href).content
      expect(navigation.xpath('//*[@epub:type="noteref"]', 'epub' => 'http://www.idpf.org/2007/ops')).to be_empty
      expect(navigation.at_xpath(%(//*[local-name()="a" and @href="#{chapter.href}"])).text).to eq 'Chapter'
      expect(book.item_by_href(href).content).not_to include 'epub3-noteref-'
    end
    expect(chapter.content).not_to include 'epub3-noteref-'
  end

  it 'preserves a named chapter title reference and backlink' do
    book = to_epub "= Book\n:doctype: book\n\n== Chapter footnote:title-note[A named note.]\n\nText."
    xml = Nokogiri::XML (chapter_with_note book).content
    expect(xml.xpath('//*[@id="title-note"]').size).to eq 1
    expect(xml.at_xpath('//*[@id="title-note"]')['href']).to eq '#note-1'
    expect(xml.at_xpath('//*[local-name()="title"]').text).to eq 'Chapter'
    check_note_targets xml
  end

  it 'omits in-chapter heading footnotes from the navigation label' do
    book = to_epub "= Article\n:doctype: article\n:toc:\n:toclevels: 2\n\n== Section footnote:section-note[A section note.]\n\nText."
    xml = Nokogiri::XML book.item_by_href('_article.xhtml').content
    expect(xml.xpath('//*[@id="section-note"]').size).to eq 1
    check_note_targets xml
    %w[nav.xhtml toc.xhtml].each do |href|
      navigation = Nokogiri::XML book.item_by_href(href).content
      expect(navigation.xpath('//*[@epub:type="noteref"]', 'epub' => 'http://www.idpf.org/2007/ops')).to be_empty
      expect(navigation.xpath('//*[@id="section-note"]')).to be_empty
    end
  end

  it 'keeps title formatting visible and escapes plain chapter labels once' do
    book = to_epub "= Book\n:doctype: book\n:toc:\n\n== Chapter *bold* & value footnote:[A title note.]\n\nText."
    chapter = chapter_with_note book
    xml = Nokogiri::XML chapter.content
    expect(xml.at_xpath('//*[local-name()="title"]').text).to eq 'Chapter bold & value'
    expect(xml.at_xpath('//*[local-name()="title"]').element_children).to be_empty
    expect(xml.at_xpath('//*[local-name()="section" and @class="chapter"]')['title']).to eq 'Chapter bold & value'
    expect(xml.at_xpath('//*[local-name()="h1"]//*[local-name()="strong"]').text).to eq 'bold'
    navigation = Nokogiri::XML book.item_by_href('nav.xhtml').content
    expect(navigation.at_xpath(%(//*[local-name()="a" and @href="#{chapter.href}"])).text).to eq 'Chapter bold & value'
    check_note_targets xml
  end

  [0, 7].each do |seed|
    it %(keeps title and body notes unique across chapters with counter seed #{seed}) do
      book = to_epub <<~EOS
        = Book
        :doctype: book
        :footnote-number: #{seed}
        :reproducible:

        == First footnote:[A first title note.]

        pass:[<a id="noteref-#{seed + 1}" href="#note-#{seed + 1}">Authored jump</a>]

        Body.footnote:[A body note.]

        === Detail footnote:shared-title[A detail note.]

        Text.

        == Second footnote:[A second title note.]

        Later.footnote:shared-title[] Another.footnote:[A later body note.]
      EOS
      chapters = book.items.values.select { |item| item.href.end_with?('.xhtml') && item.content.include?('<aside ') }
      expect(chapters.size).to eq 2
      xmls = chapters.map { |chapter| Nokogiri::XML chapter.content }
      notes = xmls.flat_map { |xml| xml.xpath('//*[local-name()="aside"]').map { |note| note['id'] } }
      expect(notes.sort).to eq (1..5).map { |index| %(note-#{seed + index}) }.sort
      xmls.each { |xml| check_note_targets xml }
      authored = xmls[0].at_xpath '//*[local-name()="a" and text()="Authored jump"]'
      expect(authored['id']).to eq %(noteref-#{seed + 1})
      expect(authored['href']).to eq %(#note-#{seed + 1})
      reference = xmls[1].at_xpath %(//*[@epub:type="noteref" and text()="#{seed + 2}"]), 'epub' => 'http://www.idpf.org/2007/ops'
      expect(reference['href']).to eq %(#{chapters[0].href}#note-#{seed + 2})
      chapters.each { |chapter| expect(chapter.content).not_to include 'epub3-noteref-' }
    end
  end
end
