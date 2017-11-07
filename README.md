# Mongoid Tracer

Mongoid Tracer stores traces of your Mongoid document changes and deletions, including changes and deletions of embedded documents.

Changes of non embedded associated document can also be traced, even the changes of properties not corresponding with a Mongoid field or relation at all.  

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'mongoid-tracer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install mongoid-tracer

## Usage

Include the module `Mongoid::Tracer` in the models you want to trace

```ruby
class Post
  include Mongoid::Document
  include Mongoid::Tracer

  field           :title
  field           :body
  field           :rating
  embeds_many     :comments
  
  #By default the fields created_at, updated_at and _type are excluded from traces.
  #You can ignore more fields by
  #trace_ignore :rating, comments
end

class Comment
  include Mongoid::Document

  field             :title
  field             :body
  embedded_in       :post, inverse_of: :comments
  
  #Even when a model doesn't include the `Mongoid::Tracer` you can configure trace options
  #since it can be traced via associations through others associated models
  #trace_ignore :title
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/macarci/mongoid-tracer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Mongoid Tracer project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/macarci/mongoid-tracer/blob/master/CODE_OF_CONDUCT.md).
