require 'mongoid/tracer/version'
require 'mongoid/tracer/options'
require 'mongoid/tracer/document_extension'
require 'mongoid/tracer/traceable_document'
require 'mongoid/tracer/railtie'

module Mongoid
  module Tracer
    extend ActiveSupport::Concern
    extend Options::ClassMethods

    DESTROYED_FLAG = '$destroyed'

    DEFAULT_IGNORE = %w(created_at updated_at _type)

    include TraceableDocument

    included do
      after_initialize :capture_init_traces
    end

    class << self
      def configure
        yield self if block_given?
      end

      def author_id(&block)
        if block
          @author_id = block
        else
          @author_id && @author_id.call
        end
      end

      def trace_option(option, *args)
        if args.length == 0
          instance_variable_get(:"@_trace_#{option}") ||
            (const_defined?(const_name = "DEFAULT_#{option.to_s.upcase}") ? const_get(const_name) : [])
        else
          instance_variable_set(:"@_trace_#{option}", args.flatten.collect(&:to_s))
        end
      end
    end
  end

  require 'mongoid/document'

  Document.include(Mongoid::Tracer::DocumentExtension)
end
