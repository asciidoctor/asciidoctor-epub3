# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Footnote links' do
  def chapter_xml(book, name)
    Nokogiri::XML book.item_by_href(%(#{name}.xhtml)).content
  end

  def note_links(xml)
    xml.xpath '//*[local-name()="a" and @epub:type="noteref"]', 'epub' => 'http://www.idpf.org/2007/ops'
  end

  it 'links anonymous notes back to their original references' do
    book = to_epub "= Book\n:doctype: book\n\n== First\n\nOne.footnote:[First note.] Two.footnote:[Second note.]"
    xml = chapter_xml book, '_first'
    expect(note_links(xml).map { |a| a['id'] }).to eq %w[noteref-1 noteref-2]
    expect(xml.xpath('//*[local-name()="aside"]/*[local-name()="p"]/*[local-name()="a"]/@href').map(&:value))
      .to eq %w[#noteref-1 #noteref-2]
    expect(xml.xpath('//*[local-name()="aside"]/*[local-name()="p"]').map(&:text))
      .to eq ['1. First note.', '2. Second note.']
  end

  it 'keeps one backlink target when a named footnote is referenced repeatedly' do
    book = to_epub "= Book\n:doctype: book\n\n== First\n\nOne.footnote:shared[Same note.] Two.footnote:shared[] Three.footnote:shared[]"
    xml = chapter_xml book, '_first'
    expect(note_links(xml).map { |a| a['href'] }).to eq %w[#note-1 #note-1 #note-1]
    expect(note_links(xml).map { |a| a['id'] }).to eq ['shared', nil, nil]
    expect(xml.xpath('//*[local-name()="aside"]/*[local-name()="p"]/*[local-name()="a"]/@href').map(&:value))
      .to eq ['#shared']
    ids = xml.xpath('//@id').map(&:value)
    expect(ids.uniq).to eq ids
  end

  it 'resolves repeated notes to their defining chapter while keeping new notes local' do
    book = to_epub <<~EOS
      = Book
      :doctype: book
      :idprefix:

      == First

      One.footnote:shared[First note.]

      == Second

      Two.footnote:shared[] Three.footnote:[Second note.]
    EOS
    first = chapter_xml book, 'first'
    second = chapter_xml book, 'second'
    expect(note_links(first).map { |a| a['href'] }).to eq ['#note-1']
    expect(note_links(second).map { |a| a['href'] }).to eq ['first.xhtml#note-1', '#note-2']
    expect(second.xpath('//*[local-name()="aside"]/@id').map(&:value)).to eq ['note-2']
    expect(second.xpath('//*[local-name()="aside"]/*[local-name()="p"]/*[local-name()="a"]/@href').map(&:value))
      .to eq ['#noteref-2']
  end

  it 'retains unresolved-note diagnostics without generating a broken backlink' do
    book = to_epub "= Book\n\nMissing.footnote:absent[]"
    xml = chapter_xml book, '_book'
    expect(xml.xpath('//*[local-name()="mark" and @title="Unresolved note reference"]').text).to eq 'absent'
    expect(note_links(xml)).to be_empty
    expect(xml.xpath('//*[local-name()="aside"]')).to be_empty
  end

  it 'uses the actual chapter filename for preamble and reserved-name note references' do
    book = to_epub <<~EOS
      = Book
      :doctype: book
      :idprefix:

      Preamble.footnote:first[First note.]

      == Nav

      Navigation.footnote:second[Second note.]

      == Last

      Again.footnote:first[] And again.footnote:second[]
    EOS
    xml = chapter_xml book, 'last'
    expect(note_links(xml).map { |a| a['href'] }).to eq ['preamble.xhtml#note-1', 'nav_.xhtml#note-2']
    expect(chapter_xml(book, 'preamble').xpath('//*[local-name()="aside"]/*[local-name()="p"]/*[local-name()="a"]/@href').map(&:value))
      .to eq ['#first']
    expect(chapter_xml(book, 'nav_').xpath('//*[local-name()="aside"]/*[local-name()="p"]/*[local-name()="a"]/@href').map(&:value))
      .to eq ['#second']
  end
end
