require 'gersberms/gersberms'
module Gersberms
  def self.bake(*args)
    gersberms = Gersberms.new(*args)
    gersberms.bake
  end
end
