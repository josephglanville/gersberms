require 'aws-sdk'
require 'berkshelf'
require 'json'
require 'net/ssh'
require 'net/scp'

module Gersberms
  class Gersberms
    attr_accessor :options, :key_pair, :image

    CHEF_PATH = '/tmp/gersberms-chef'

    DEFAULT_OPTIONS = {
      # Instance options
      ssh_user: 'ubuntu',
      base_ami: 'ami-950b62af',
      instance_type: 't2.micro',
      public_address: true,
      security_groups: nil,
      subnet: nil,
      # Chef options
      berksfile: 'Berksfile',
      vendor_path: 'vendor/cookbooks',
      runlist: [],
      json: {},
      # AMI options
      ami_name: 'gersberms-ami',
      tags: [],
      accounts: [],
      # Additional files or directories to upload
      # files: [{ source: '.',  destination: '/tmp/staging' }]
      files: [],
      # Gersberms options
      logger: Logger.new(STDOUT),
      max_ssh_attempts: 60
    }

    def initialize(options = {})
      @ec2 = AWS::EC2.new
      @options = Hashie::Mash.new(DEFAULT_OPTIONS.merge(options))
    end

    def logger
      @options[:logger]
    end

    # TODO(jpg): move this
    def rand
      ('a'..'z').to_a.shuffle[0, 8].join
    end

    def create_keypair
      name = 'gersberms-' + rand
      logger.info "Creating keypair: #{name}"
      @key_pair = @ec2.key_pairs.create(name)
    end

    def create_instance
      logger.info 'Creating instance'
      create_options = {
        image_id: @options[:base_ami],
        instance_type: @options[:instance_type],
        count: 1,
        key_pair: @key_pair,
        associate_public_ip_address: @options[:public_address]
      }
      create_options[:security_group_ids] = @options[:security_groups] if @options[:security_groups]
      create_options[:subnet] = @options[:subnet] if @options[:subnet]
      @instance = @ec2.instances.create(create_options)
      sleep 1 until @instance.exists?
      logger.info "Launched instance #{@instance.id}, waiting to become running"
      sleep 1 until @instance.status == :running
      wait_for_ssh
      logger.info 'Instance now running'
    end

    def wait_for_ssh
      cmd('true')
    end

    def ssh(&block)
      attempts = 0
      Net::SSH.start(
        @instance.public_ip_address,
        @options[:ssh_user],
        key_data: [@key_pair.private_key],
        &block
      )
    rescue Timeout::Error, Errno::EHOSTUNREACH, Errno::ECONNREFUSED => e
      sleep 1
      attempts += 1
      retry unless attempts > @options[:max_ssh_attempts]
      logger.error "Exceeded max SSH attempts: #{@options[:max_ssh_attempts]}"
      raise
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
        cookbook_path ['#{chef_path('cookbooks')}']
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
      StringIO.new(JSON.pretty_generate(@options[:json]))
    end

    def install_chef
      logger.info 'Installing Chef'
      # TODO(jpg): means to force upgrade of Chef etc.
      cmd('which chef-solo || curl -L https://www.opscode.com/chef/install.sh | sudo bash')
    end

    def upload_files
      return unless @options[:files].count > 1
      puts 'Uploading files'
      ssh do |s|
        @options[:files].each do |f|
          s.scp.upload!(f[:source], f[:destination], recursive: true)
        end
      end
    end

    def upload_cookbooks
      logger.info 'Vendoring cookbooks'
      berksfile = Berkshelf::Berksfile.from_file(@options[:berksfile])
      berksfile.vendor(@options[:vendor_path])
      ssh do |s|
        logger.debug "Creating #{CHEF_PATH}"
        s.exec!("mkdir -p #{CHEF_PATH}")
        logger.debug "Creating #{chef_path('solo.rb')}"
        s.scp.upload!(chef_config, chef_path('solo.rb'))
        logger.debug "Uploading cookbooks to #{chef_path('cookbooks')}"
        s.scp.upload!(@options[:vendor_path], chef_path('cookbooks'), recursive: true)
        logger.debug "Create #{chef_path('node.json')}"
        s.scp.upload!(chef_json, chef_path('node.json'))
        logger.debug s.exec!("cat #{chef_path('node.json')}")
      end
    end

    def run_chef
      logger.info 'Running Chef'
      command = 'sudo chef-solo'
      command += " --config #{chef_path('solo.rb')}"
      command += " --json-attributes #{chef_path('node.json')}"
      command += " --override-runlist '#{@options[:runlist].join(',')}'"
      logger.debug command
      output = cmd(command)
      logger.debug 'Chef output:'
      logger.debug output
    end

    def create_ami
      logger.info "Creating AMI: #{@options[:ami_name]}"
      @image = @instance.create_image(@options[:ami_name])
      @options[:tags].each do |tag|
        logger.info "Adding tag to AMI: #{tag}"
        @image.add_tag(tag)
      end

      if @options[:share_accounts]
        logger.info "Sharing AMI with: #{@options[:share_accounts]}"
        @image.permissions.add(*@options[:share_accounts])
      end

      logger.debug "Waiting until AMI: #{@options[:ami_name]} exists"
      sleep 1 until @image.exists?

      logger.debug "Waiting until AMI: #{@options[:ami_name]} becomes available"
      sleep 1 until @image.state == :available

      logger.info "AMI #{@image.id} created sucessfully"
    end

    def stop_instance
      logger.info "Stopping instance: #{@instance.id}"
      @instance.stop
      sleep 1 until @instance.status == :stopped
    end

    def destroy_instance
      return unless @instance
      logger.info "Destroying instance: #{@instance.id}"
      @instance.terminate
      sleep 1 until @instance.status == :terminated
    end

    def destroy_keypair
      logger.info "Destroying keypair: #{@key_pair.name}"
      @key_pair.delete if @key_pair
    end

    def preflight
      fail "AMI #{@options[:ami_name]} already exists" if @ec2.images[@options[:ami_name]].exists?
    end

    def bake
      preflight
      create_keypair
      create_instance
      install_chef
      upload_cookbooks
      upload_files
      run_chef
      stop_instance
      create_ami
      destroy_instance
      destroy_keypair
      @image.id
    rescue => e
      logger.error "Failed!: #{e.message} \n#{e.backtrace.join("\n")}"
      destroy_instance
      destroy_keypair
    end
  end
end
