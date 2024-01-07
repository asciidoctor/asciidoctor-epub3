# frozen_string_literal: true

require 'stringio' unless defined? StringIO

class String
  unless method_defined? :to_ios
    def to_ios
      StringIO.new self
    end
  end
end
