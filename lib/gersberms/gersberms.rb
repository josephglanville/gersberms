require 'aws-sdk'
require 'berkshelf'
require 'json'
require 'net/ssh'
require 'net/scp'

module Gersberms
  class Gersberms
    attr_accessor :options, :key_pair

    CHEF_PATH = '/tmp/gersberms-chef'

    DEFAULT_OPTIONS = {
      # Instance options
      ssh_user: 'ubuntu',
      base_ami: 'ami-950b62af',
      instance_type: 't2.micro',
      security_groups: [],
      subnet: nil,
      # Chef options
      berksfile: 'Berksfile',
      vendor_path: 'vendor/cookbooks',
      runlist: [],
      json: {},
      # AMI options
      ami_name: 'gersberms-ami',
      tags: [],
      accounts: []
    }

    def initialize(options = {})
      @ec2 = AWS::EC2.new
      @options = DEFAULT_OPTIONS.merge(options)
    end

    # TODO(jpg): move this
    def rand
      ('a'..'z').to_a.shuffle[0,8].join
    end

    def create_keypair
      name = 'gersberms-' + rand
      puts "Creating keypair: #{name}"
      @key_pair = @ec2.key_pairs.create(name)
    end

    def create_instance
      puts "Creating instance"
      @instance = @ec2.instances.create(
        image_id: @options[:base_ami],
        instance_type: @options[:instance_type],
        count: 1,
        key_pair: @key_pair,
        security_groups: @options[:security_groups]
      )
      puts "Launched instance #{@instance.id}, waiting to become running"
      sleep 1 until @instance.status == :running
      wait_for_ssh
      puts "Instance now running"
    end

    def wait_for_ssh
      sleep 10 # TODO(jpg): do this properly
    end

    def ssh(&block)
      Net::SSH.start(
        @instance.public_ip_address,
        @options[:ssh_user],
        key_data: [@key_pair.private_key],
        &block
      )
    end

    def cmd(command)
      ssh do |s|
        s.exec!(command)
      end
    end

    def chef_path(*args)
      args.unshift(CHEF_PATH)
      File.join(*args)
    end

    def chef_config
      # TODO(jpg): unindent
      StringIO.new <<-EOF
        file_cache_path    "/var/chef/cache"
        file_backup_path   "/var/chef/backup"
        cookbook_path ['/tmp/gersberms-chef/cookbooks']
        if Chef::VERSION.to_f < 11.8
          role_path nil
        else
          role_path []
        end
        log_level :info
        verbose_logging    false
        encrypted_data_bag_secret nil
        http_proxy nil
        http_proxy_user nil
        http_proxy_pass nil
        https_proxy nil
        https_proxy_user nil
        https_proxy_pass nil
        no_proxy nil
      EOF
    end

    def chef_json
      StringIO.new(@options[:json].to_json)
    end

    def install_chef
      puts "Installing Chef"
      # TODO(jpg): means to force upgrade of Chef etc.
      cmd('which chef-solo || curl -L https://www.opscode.com/chef/install.sh | sudo bash')
    end

    def upload_cookbooks
      puts "Uploading cookbooks"
      berksfile = Berkshelf::Berksfile.from_file(@options[:berksfile])
      berksfile.vendor(@options[:vendor_path])
      ssh do |s|
        s.exec!("mkdir -p #{CHEF_PATH}")
        s.scp.upload!(chef_config, chef_path('solo.rb'))
        s.scp.upload!(@options[:vendor_path], chef_path('cookbooks'), recursive: true)
        s.scp.upload!(chef_json, chef_path('node.json'))
      end
    end

    def run_chef
      puts "Running Chef"
      command = 'sudo chef-solo'
      command += " --config #{chef_path('solo.rb')}"
      command += " --json-attributes #{chef_path('node.json')}"
      command += " --override-runlist '#{@options[:runlist].join(',')}'"
      cmd(command)
    end

    def create_ami
      puts "Creating AMI: #{@options[:ami_name]}"
      @image = @instance.create_image(@options[:ami_name])
      @options[:tags].each do |tag|
        puts "Adding tag to AMI: #{tag}"
        @image.add_tag(tag)
      end
      
      if @options[:share_accounts]
        puts "Sharing AMI with: #{@options[:share_accounts]}"
        @image.permissions.add(*@options[:share_accounts])
      end
      puts "Waiting until AMI: #{@options[:ami_name]} becomes available"
      sleep 1 until @instance.state == :available
    end

    def stop_instance
      puts "Stopping instance: #{@instance.id}"
      @instance.stop
      sleep 1 until @instance.status == :stopped
    end

    def destroy_instance
      return unless @instance
      puts "Destroying instance: #{@instance.id}"
      @instance.terminate
      sleep 1 until @instance.status == :terminated
    end

    def destroy_keypair
      puts "Destroying keypair: #{@key_pair.name}"
      @key_pair.delete if @key_pair
    end

    def bake
      create_keypair
      create_instance
      install_chef
      upload_cookbooks
      run_chef
      stop_instance
      create_ami
      destroy_instance
      destroy_keypair
    rescue
      destroy_instance
      destroy_keypair
    end
  end
end
