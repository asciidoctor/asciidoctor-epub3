# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Table' do
  it 'supports halign' do
    book = to_epub <<~EOS
= Article

|===
>| Text
|===
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<td class="halign-right valign-top"><p class="tableblock">Text</p></td>'
  end

  it 'supports valign' do
    book = to_epub <<~EOS
= Article

|===
.>| Text
|===
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '<td class="halign-left valign-bottom"><p class="tableblock">Text</p></td>'
  end

  it 'supports colwidth' do
    book = to_epub <<~EOS
= Article

[cols="3,1"]
|===
| A | B
|===
    EOS
    article = book.item_by_href '_article.xhtml'
    expect(article).not_to be_nil
    expect(article.content).to include '
<colgroup>
<col style="width: 75%;" />
<col style="width: 25%;" />
</colgroup>
'
  end
end
