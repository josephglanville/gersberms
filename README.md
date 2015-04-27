# Gersberms

Build AMIs the right way with chef-solo and Berkshelf.

## Installation

    $ gem install gersberms

## Usage

Gersberms can be used via the CLI, as a library or as a Rake task.

All of the following are equivalent

### CLI

To use the CLI you must create a YAML formatted config file.

```yaml
ssh_user: ubuntu
base_ami: ami-950b62af
type: t2.micro
ami_name: example-ami
security_groups:
  - example_security_group
runlist:
  - example_cookbook::default
json:
  example_cookbook:
    example_attribute: example_value
```

Which you can then use with the `bake` command like so:

   $ gersberms bake --config=config.yml

### Library
```ruby
require 'gersberms'

config = {
  ssh_user: 'ubuntu',
  base_ami: 'ami-950b62af'
  instance_type: 't2.micro',
  ami_name: 'example-ami',
  security_groups: ['example_security_group'],
  runlist: ['example_cookbook::default'],
  json: {
    example_cookbook: {
      example_attribute: "example_value"
    }
  }
}

Gersberms.bake(config)
```

### Rake Task

```ruby
require 'gersberms/rake_task'

Gersberms::RakeTask.new(:ami) do |ami|
  ami.ssh_user = 'ubuntu'
  ami.base_ami = 'ami-950b62af'
  ami.instance_type = 't2.micro'
  ami.ami_name = 'example-ami'
  ami.security_groups = ['example_security_group']
  ami.runlist = ['example_cookbook::default']
  ami.json = {
    example_cookbook: {
      example_attribute: 'example_value'
    }
  }
end
```
