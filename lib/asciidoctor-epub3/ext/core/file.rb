# frozen_string_literal: true

class File
  # TODO: remove once minimum required Ruby version is at least 2.7
  unless respond_to? :absolute_path?
    def self.absolute_path?(path)
      Pathname.new(path).absolute?
    end
  end
end
