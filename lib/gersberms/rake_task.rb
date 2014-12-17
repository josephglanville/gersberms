require 'gersberms'
require 'rake'
require 'rake/tasklib'

module Gersberms
  # Provides a custom rake task.
  #
  # First require this file:
  # require 'gersberms/rake_task'
  #
  # Then you can configure the task like so.
  # Gersberms::RakeTask.new(:ami) do |ami|
  #   ami.ssh_user = 'ubuntu'
  #   ami.base_ami = 'ami-950b62af'
  #   ami.instance_type = 't2.micro'
  #   ami.security_groups = ['example_security_group']
  #   ami.subnet = 'example_subnet'
  #   ami.berksfile = 'Berksfile'
  #   ami.vendor_path = 'vendor/cookbooks'
  #   ami.runlist = ['example_cookbook::example_recipe']
  #   ami.json = {
  #     example_cookbook: {
  #       example_attribute: 'example_value'
  #     }
  #   }
  #   ami.ami_name = 'example-ami'
  #   ami.tags = ['example_tag']
  #   ami.accounts = ['example_account_id']
  # end
  #
  # The name you pass into the constructor will be the name of the task itself.
  # ie. rake ami for the above example
  class RakeTask < Rake::TaskLib
    ATTRS = [:ssh_user, :base_ami, :instance_type, :security_groups, :accounts,
             :subnet, :berksfile, :vendor_path, :runlist, :json, :ami_name, :tags]
    attr_accessor *ATTRS

    def initialize(*task_args, &task_block)
       task_block.call(*[self, task_args].slice(0, task_block.arity)) if task_block

       desc 'Build AMI using Gersberms' unless Rake.application.last_comment
       task @name do
         baker = Gersberms.new(self.to_h)
         baker.bake
       end
    end

    def to_h
      ATTRS.each_with_object({}) do |k,m|
        m[k] = self.send(k)
      end.delete_if {|k, v| v.nil?}
    end
  end
end
