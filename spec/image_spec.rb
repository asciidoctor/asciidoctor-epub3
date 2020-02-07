# frozen_string_literal: true

require_relative 'spec_helper'
require 'asciidoctor-diagram'

describe 'Asciidoctor::Epub3::Converter - Image' do
  it 'supports imagesoutdir != imagesdir != "{base_dir}/images"' do
    book, out_file = to_epub 'diagram/book.adoc'
    out_dir = out_file.dirname

    expect(out_dir.join('a', 'a.png')).to exist
    expect(out_dir.join('b', 'b.png')).to exist
    expect(out_dir.join('c.png')).to exist
    expect(out_dir.join('d', 'plantuml.png')).to exist

    expect(book).to have_item_with_href('a/a.png')
    expect(book).to have_item_with_href('b/b.png')
    expect(book).to have_item_with_href('c.png')
    expect(book).to have_item_with_href('d/plantuml.png')
  end

  it 'supports inline images' do
    book, out_file = to_epub 'inline-image/book.adoc'
    out_dir = out_file.dirname

    expect(out_dir.join('imagez', 'inline-diag.png')).to exist

    expect(book).to have_item_with_href('imagez/inline-diag.png')
    expect(book).to have_item_with_href('imagez/square.png')
    expect(book).to have_item_with_href('imagez/wolpertinger.jpg')
  end

  it 'converts font-based icons to CSS' do
    book, = to_epub 'icon/book.adoc'
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '.i-commenting::before { content: "\f4ad"; }'
  end

  it 'supports image width/height' do
    book, = to_epub 'image-dimensions/book.adoc'
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<img src="square.png" alt="100x100" width="100" />'
    expect(chapter.content).to include '<img src="square.png" alt="50x50" width="50" />'
    expect(chapter.content).to include '<img src="square.png" alt="50x?" width="50" />'
  end
end
