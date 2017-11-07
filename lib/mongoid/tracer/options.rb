module Mongoid
  module Tracer
    module Options
      extend ActiveSupport::Concern

      NAMES = %w(ignore include references actions)

      included do
        delegate *NAMES.collect { |opt| "trace_#{opt}" }, to: :class
      end

      module ClassMethods

        def trace_action?(action)
          trace_actions.empty? || trace_actions.include?(action.to_s)
        end

        def trace_only(*args)
          if args.length == 0
            @trace_only
          else
            @trace_only = args.flatten.collect(&:to_s)
          end
        end

        def method_missing(symbol, *args, &block)
          if (match = symbol.to_s.match(/\Atrace_(.+)\Z/)) &&
            Mongoid::Tracer::Options::NAMES.include?(match[1])
            trace_option(match[1], *args)
          else
            super
          end
        end

        def trace_option(option, *args)
          if args.length == 0
            instance_variable_get(:"@_trace_#{option}") ||
              (is_a?(Class) && superclass < Mongoid::Tracer::Options && superclass.trace_option(option, *args)) ||
              Mongoid::Tracer.trace_option(option, *args)
          else
            instance_variable_set(:"@_trace_#{option}", (args.flatten.collect(&:to_s) + trace_option(option)).uniq)
          end
        end
      end
    end
  end
end
