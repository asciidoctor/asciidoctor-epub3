# frozen_string_literal: true

require_relative 'spec_helper'
require 'asciidoctor-diagram'

describe 'Asciidoctor::Epub3::Converter - Image' do
  it 'supports imagesoutdir != imagesdir != "{base_dir}/images"' do
    book, out_file = to_epub fixture_file('diagram/book.adoc')
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
    book, out_file = to_epub fixture_file('inline-image/book.adoc')
    out_dir = out_file.dirname

    expect(out_dir.join('imagez', 'inline-diag.png')).to exist

    expect(book).to have_item_with_href('imagez/inline-diag.png')
    expect(book).to have_item_with_href('imagez/square.png')
    expect(book).to have_item_with_href('imagez/wolpertinger.jpg')
  end

  it 'converts font-based icons to CSS' do
    book, = to_epub fixture_file('icon/book.adoc')
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '.i-commenting::before { content: "\f4ad"; }'
  end

  it 'adds front cover image' do
    book, = to_epub fixture_file('front-cover-image/book.adoc')
    cover_image = book.item_by_href 'jacket/cover.png'
    expect(cover_image).not_to be_nil
    cover_page = book.item_by_href 'cover.xhtml'
    expect(cover_page).not_to be_nil
    expect(cover_page.content).to include '<image width="1050" height="1600" xlink:href="jacket/cover.png"/>'
  end

  it "doesn't crash if cover image points to a directory" do
    book, = to_epub fixture_file('empty.adoc'), attributes: { 'front-cover-image' => '' }
    expect(book).not_to be_nil
  end

  it 'supports image width/height' do
    book, = to_epub fixture_file('image-dimensions/book.adoc')
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<img src="square.png" alt="100x100" width="100" />'
    expect(chapter.content).to include '<img src="square.png" alt="50x50" width="50" />'
    expect(chapter.content).to include '<img src="square.png" alt="50x?" width="50" />'
  end

  # If this test fails for you, make sure you're using gepub >= 1.0.11
  it 'adds SVG attribute to EPUB manifest if chapter contains SVG images' do
    book, = to_epub fixture_file('svg/book.adoc')
    chapter = book.item_by_href '_chapter.xhtml'
    expect(chapter).not_to be_nil
    properties = chapter['properties']
    expect(properties).to include('svg')
  end
end
