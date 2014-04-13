module Asciidoctor
class AbstractBlock
  def find_by filter_context = nil, options = {}, &block
    result = []
    filter_context = nil if filter_context == '*'
    filter_style = options[:style]
    filter_role = options[:role]
  
    if (filter_context == nil || filter_context == @context) &&
        (filter_style == nil || filter_style == @style) &&
        (filter_role == nil || (has_role? filter_role))
      if block_given?
        result << self if yield(self)
      else
        result << self
      end
    end
  
    if @context == :document && (filter_context == nil || filter_context == :section) && header?
      result.concat @header.find_by(filter_context, options, &block) || []
    end
    
    @blocks.each do |b|
      # yuck!
      if b.is_a? ::Array
        unless filter_context == :section # optimization
          b.flatten.each do |li|
            result.concat li.find_by(filter_context, options, &block) || []
          end
        end
      else
        result.concat b.find_by(filter_context, options, &block) || []
      end
    end unless filter_context == :document # optimization
    result.empty? ? nil : result
  end
end
end
