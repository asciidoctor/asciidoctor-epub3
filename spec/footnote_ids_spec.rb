# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Footnote reference IDs' do
  def check_note_targets(xml)
    ids = xml.xpath('//@id').map(&:value)
    expect(ids.uniq).to eq ids
    xml.xpath('//*[local-name()="aside"]').each do |note|
      backlink = note.at_xpath './/*[local-name()="a"]'
      expect(backlink).not_to be_nil
      targets = xml.xpath '//*[local-name()="a"]'
      targets = targets.select { |a| %(##{a['id']}) == backlink['href'] }
      expect(targets.size).to eq 1
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
end
