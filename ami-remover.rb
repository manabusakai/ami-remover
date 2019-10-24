require 'aws-sdk-autoscaling'
require 'aws-sdk-ec2'
require 'date'
require 'optparse'
require 'pp'

DEBUG = ! ENV['DEBUG'].nil? ? true : false

def parse_options
  options = { remove_flag: false }
  OptionParser.new do |opt|
    opt.on('-d NUM', '--days NUM') do |days|
      options[:days] = days.to_i
    end
    opt.on('--include-tag TAG') do |tag|
      options[:include_tag] = tag.to_s
    end
    opt.on('--exclude-tag TAG') do |tag|
      options[:exclude_tag] = tag.to_s
    end
    opt.on('--region REGION') do |region|
      options[:region] = region.to_s
    end
    opt.on('-r', '--remove') do
      options[:remove_flag] = true
    end
    opt.on('-v', '--verbose') do
      options[:verbose] = true
    end
    opt.parse!(ARGV)
  end
  options
end

def get_snapshot_ids(block_device_mappings)
  snapshot_ids = []
  block_device_mappings.each do |mapping|
    snapshot_ids.push mapping.ebs.snapshot_id unless mapping.ebs.nil?
  end
  snapshot_ids
end

def filter_images(images, filter)
  # Exclude AMI newer than threshold date.
  unless filter[:days].nil?
    ENV['TZ'] = 'UTC'
    threshold_date = DateTime.now - filter[:days]

    images.each do |image_id, attribute|
      creation_date = DateTime.parse(attribute['creation_date'])
      images.delete image_id if creation_date > threshold_date
    end
  end

  # Include or Exclude AMI by tag name.
  if ! filter[:include_tag].nil? || ! filter[:exclude_tag].nil?
    images.each do |image_id, attribute|
      image_tags = []
      attribute['tags'].each do |tag|
        image_tags.push tag.key
      end

      unless filter[:include_tag].nil?
        next if image_tags.include?(filter[:include_tag])
        images.delete(image_id)
      end

      unless filter[:exclude_tag].nil?
        next unless image_tags.include?(filter[:exclude_tag])
        images.delete(image_id)
      end
    end
  end

  images
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
  image_ids.uniq
end

def get_images(filter)
  ec2  = Aws::EC2::Client.new(region: AWS_REGION)
  resp = ec2.describe_images({owners: ['self']})

  images = {}
  exclude_image_ids = get_images_of_launch_configurations

  resp.images.each do |image|
    # Exclude AMI included in launch configurations.
    next if exclude_image_ids.include?(image.image_id)

    images[image.image_id] = {
      'name'          => image.name,
      'tags'          => image.tags,
      'creation_date' => image.creation_date,
      'snapshot_ids'  => get_snapshot_ids(image.block_device_mappings)
    }
  end

  debug_output('Before filtering', images) if DEBUG
  images = filter_images(images, filter)
  debug_output('After filtering', images) if DEBUG

  images = images.sort_by do |image_id, attribute|
    attribute['creation_date']
  end.to_h

  images
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
  images
end

def debug_output(message, object)
  puts "\e[31m#{message}\e[0m"
  pp object
end

options = parse_options

if options[:region].nil?
  print "\e[31m"
  print 'Error: `--region` is required.'
  print "\e[0m\n"
  exit 1
end

if ! options[:include_tag].nil? && ! options[:exclude_tag].nil?
  print "\e[31m"
  print 'Error: `--include-tag` and `--exclude-tag` can not be used together.'
  print "\e[0m\n"
  exit 1
end

AWS_REGION = options[:region]

filter = {
  days:        options[:days],
  include_tag: options[:include_tag],
  exclude_tag: options[:exclude_tag],
  verbose:     options[:verbose]
}

images = describe_images(filter)

if options[:remove_flag]
  remove_images(images)
end
