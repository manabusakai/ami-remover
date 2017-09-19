require 'aws-sdk-ec2'
require 'optparse'

AWS_REGION='ap-northeast-1'

def parse_options
  options = { remove_flag: false }
  OptionParser.new do |opt|
    opt.on('-r', '--remove', 'remove flag') do
      options[:remove_flag] = true
    end
    opt.parse!(ARGV)
  end
  return options
end

def get_snapshot_ids(block_device_mappings)
  snapshot_ids = []
  block_device_mappings.each do |mapping|
    snapshot_ids.push mapping.ebs.snapshot_id
  end
  return snapshot_ids
end

def get_images
  ec2  = Aws::EC2::Client.new(region: AWS_REGION)
  resp = ec2.describe_images({owners: ['self']})

  images = {}

  resp.images.each do |image|
    image_id      = image.image_id
    name          = image.name
    creation_date = image.creation_date
    snapshot_ids  = get_snapshot_ids(image.block_device_mappings)

    images[image_id] = {
      'name'          => name,
      'creation_date' => creation_date,
      'snapshot_id'   => snapshot_ids,
    }
  end

  return images
end

def describe_images
  puts "IMAGE_ID\tNAME\tCREATION_DATE"

  get_images.each do |image_id, attribute|
    print "#{image_id}\t"
    print "\"#{attribute['name']}\"\t"
    print "\"#{attribute['creation_date']}\"\n"
  end
end

options = parse_options

if options[:remove_flag]
  # Remove AMI
else
  describe_images
end
