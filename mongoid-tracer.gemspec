# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mongoid/tracer/version'

Gem::Specification.new do |spec|
  spec.name          = 'mongoid-tracer'
  spec.version       = Mongoid::Tracer::VERSION
  spec.authors       = ['Maikel Arcia']
  spec.email         = ['macarci@gmail.com']

  spec.summary       = %q{Store traces of Mongoid documents, allowing undo of changes and deletions.}
  spec.homepage      = 'https://github.com/macarci/mongoid-tracer'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.15'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_runtime_dependency 'mongoid', '>= 5.0.1'
end
