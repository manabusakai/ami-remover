require 'aws-sdk-autoscaling'
require 'aws-sdk-ec2'
require 'date'
require 'optparse'
require 'pp'
require 'tty-prompt'

AWS_REGION = 'ap-northeast-1'
DEBUG = ! ENV['DEBUG'].nil? ? true : false

def parse_options
  options = { remove_flag: false }
  OptionParser.new do |opt|
    opt.on('-d NUM', '--days NUM', 'days option') do |days|
      options[:days] = days.to_i
    end
    opt.on('-r', '--remove', 'remove flag') do
      options[:remove_flag] = true
    end
    opt.on('-v', '--verbose', 'more verbose') do
      options[:verbose] = true
    end
    opt.parse!(ARGV)
  end
  return options
end

def get_snapshot_ids(block_device_mappings)
  snapshot_ids = []
  block_device_mappings.each do |mapping|
    snapshot_ids.push mapping.ebs.snapshot_id if ! mapping.ebs.nil?
  end
  return snapshot_ids
end

def filter_images(images, filter)
  if ! filter[:days].nil?
    ENV['TZ'] = 'UTC'
    threshold_date = DateTime.now - filter[:days]

    # Exclude AMI newer than threshold date.
    images.each do |image_id, attribute|
      creation_date = DateTime.parse(attribute['creation_date'])
      if creation_date > threshold_date
        images.delete(image_id)
      end
    end
  end
  return images
end

def get_images_of_launch_configurations
  autoscaling = Aws::AutoScaling::Client.new(region: AWS_REGION)

  next_token = ''
  image_ids  = []

  until next_token.nil?
    resp = autoscaling.describe_launch_configurations({next_token: next_token})
    resp.launch_configurations.each do |configuration|
      image_ids.push configuration.image_id
    end
    next_token = resp.next_token
  end
  return image_ids.uniq
end

def get_images(filter)
  ec2  = Aws::EC2::Client.new(region: AWS_REGION)
  resp = ec2.describe_images({owners: ['self']})

  images = {}
  exclude_image_ids = get_images_of_launch_configurations

  resp.images.each do |image|
    image_id      = image.image_id
    name          = image.name
    creation_date = image.creation_date
    snapshot_ids  = get_snapshot_ids(image.block_device_mappings)

    # Exclude AMI included in launch configurations
    next if exclude_image_ids.include?(image_id)

    images[image_id] = {
      'name'          => name,
      'creation_date' => creation_date,
      'snapshot_ids'  => snapshot_ids,
    }
  end

  debug_output('Before filtering', images) if DEBUG
  images = filter_images(images, filter)
  debug_output('After filtering', images) if DEBUG

  images = images.sort_by do |image_id, attribute|
    attribute['creation_date']
  end.to_h

  return images
end

def remove_images(images)
  ec2 = Aws::EC2::Client.new(region: AWS_REGION)
  images.each do |image_id, attribute|
    ec2.deregister_image({image_id: image_id})
    attribute['snapshot_ids'].each do |snapshot_id|
      ec2.delete_snapshot({snapshot_id: snapshot_id})
    end
    sleep(0.5)
  end
end

def describe_images(filter)
  images = get_images(filter)
  if filter[:verbose]
    images.each do |image_id, attribute|
      print "#{image_id}\s\s"
      print "#{attribute['creation_date']}\s\s"
      print "#{attribute['name']}\n"
    end
    puts "count: #{images.size}"
  else
    images.each do |image_id, attribute|
      puts "#{image_id}"
    end
  end
  return images
end

def debug_output(message, object)
  puts "\e[31m#{message}\e[0m"
  pp object
end

options = parse_options
filter = { days: options[:days], verbose: options[:verbose] }

images = describe_images(filter)

if options[:remove_flag]
  prompt = TTY::Prompt.new(enable_color: false)
  if prompt.yes?('Do you want to delete it?')
    remove_images(images)
  end
end
