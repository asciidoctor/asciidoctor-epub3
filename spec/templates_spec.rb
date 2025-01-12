# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Templates' do
  it 'supports Slim templates' do
    book, = to_epub <<~EOS, template_dirs: [fixtures_dir.join('templates/slim').to_s], template_engine: 'slim'
= Article

Paragraph
EOS
    chapter = book.item_by_href '_article.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<slim>Paragraph</slim>'
  end

  it 'supports ERB templates' do
    book, = to_epub <<~EOS, template_dirs: [fixtures_dir.join('templates/erb').to_s]
= Article

Paragraph
EOS
    chapter = book.item_by_href '_article.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<erb>Paragraph</erb>'
  end
end
