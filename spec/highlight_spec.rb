# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Highlight' do
  it 'highlights code listings with coderay' do
    book, = to_epub fixture_file('source_highlight.adoc'), attributes: { 'source-highlighter' => 'coderay' }
    article = book.item_by_href 'source_highlight.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<span class="keyword">class</span> <span class="class">Foo</span>'
    expect(article.content).to include '<link rel="stylesheet" href="./coderay-asciidoctor.css"/>'
    expect(book.item_by_href('coderay-asciidoctor.css')).not_to be_nil
  end

  it 'highlights code listings with pygments.rb' do
    book, = to_epub fixture_file('source_highlight.adoc'), attributes: { 'source-highlighter' => 'pygments' }
    article = book.item_by_href 'source_highlight.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<span class="tok-nc">Foo</span>'
    expect(article.content).to include '<link rel="stylesheet" href="./pygments-bw.css"/>'
    expect(book.item_by_href('pygments-bw.css')).not_to be_nil
  end

  it 'highlights code listings with Rouge' do
    book, = to_epub fixture_file('source_highlight.adoc'), attributes: { 'source-highlighter' => 'rouge' }
    article = book.item_by_href 'source_highlight.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<span class="k">class</span> <span class="nc">Foo</span>'
    expect(article.content).to include '<link rel="stylesheet" href="./rouge-bw.css"/>'
    expect(book.item_by_href('rouge-bw.css')).not_to be_nil
  end
end
