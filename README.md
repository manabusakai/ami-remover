# AMI Remover

"AMI Remover" is a simple tool to delete AMI and snapshots.

## Install

```
$ bundle install
```

## Configuration

Please set either. (See also: [Configuring the AWS CLI](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html))

### Environment Variables

```
$ export AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY_ID
$ export AWS_SECRET_ACCESS_KEY=YOUR_SECRET_ACCESS_KEY
```

### Credential Files

```
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
```

## Usage

By default, it only displays the AMI ID. (`-v` or `--verbose` is verbose mode.)

```
$ bundle exec ruby ami-remover.rb [-v|--verbose]
```

If you want to delete, please add a remove option.

```
$ bundle exec ruby ami-remover.rb [-r|--remove]
```

## Filter

* `-d`, `--days`: Exclude AMI created within x days.
* `--include-tag`: Includes the specified tag name.
* `--exclude-tag`: Excludes the specified tag name.

`--include-tag` and `--exclude-tag` can not be used together.

For example, delete the AMI that is older than 365 days and has a `Project` tag.

```
$ bundle exec ruby ami-remover.rb -r -d 365 --include-tag Project
```

## License

This software is released under the MIT License.
