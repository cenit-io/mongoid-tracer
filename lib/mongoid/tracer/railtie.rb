module Mongoid
  module Tracer
    class Railtie < Rails::Railtie
      config.after_initialize do
        require 'mongoid/tracer/trace_behavior'
        require 'mongoid/tracer/trace'
        Trace.include(TraceBehavior)
      end
    end
  end
end
