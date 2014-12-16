require 'gersberms'

module Gersberms
  class CLI < Thor
    desc "bake", "Create AMI using specified configuration file"
    option :config, type: :string, required: true
    def bake
      cfg = YAML.load_file(options[:config])
      cfg = cfg.each_with_object({}) { |(k,v),m| m[k.to_sym] = v }
      baker = Gersberms.new(cfg)
      baker.bake
    end
  end
end
