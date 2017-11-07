module Mongoid
  module Tracer
    module TraceableDocument

      def capture_init_traces
        @init_traces = {}
        each_trace_included { |property, value| @init_traces[property] = value }
        trace_references.each do |relation_name|
          if reflect_on_association(relation_name).many?
            unless (docs_attrs = send(relation_name).collect(&:current_attributes)).empty?
              @init_traces[relation_name] = docs_attrs
            end
          elsif (doc = send(relation_name))
            @init_traces[relation_name] = doc.current_attributes
          end
        end
      end

      def save(options = {})
        already_tracing = thread_key = msg = nil
        if (tracing = tracing?)
          msg = options && options.delete(:message)
          thread_key = "[mongoid-tracing]#{self.class}##{id}"
          unless (already_tracing = Thread.current[thread_key])
            Thread.current[thread_key] = true
            capture_attributes
          end
        end
        saved = super
        if saved && tracing && !already_tracing
          trace_references.each { |relation_name| remove_instance_variable(:"@_#{relation_name}") }
          if captured_attributes.key?('_id')
            trace_update(msg)
          else
            trace_create(msg)
          end
        end
        saved
      ensure
        Thread.current[thread_key] = nil unless thread_key.nil? || already_tracing
      end

      def destroy(options = nil)
        already_tracing = thread_key = msg = nil
        if (tracing = tracing?)
          msg = options && options.delete(:message)
          thread_key = "[mongoid-tracing]#{self.class}##{id}"
          unless (already_tracing = Thread.current[thread_key])
            Thread.current[thread_key] = true
            capture_attributes
          end
        end
        destroyed = super
        if destroyed && tracing && !already_tracing
          trace_destroy(msg)
        end
        destroyed
      ensure
        Thread.current[thread_key] = nil unless thread_key.nil? || already_tracing
      end

      def tracing_options
        self.class.tracing_options
      end

      def tracing?
        true
      end

      def captured_attributes
        @captured_attributes || capture_attributes
      end

      def capture_attributes
        @captured_attributes =
          if new_record?
            {}
          else
            send(:_reload)
              .except(*self.class.trace_ignore)
              .merge(@init_traces || {}) do |_, left, right|
              if left.is_a?(Hash) && right.is_a?(Hash)
                left.deep_reverse_merge(right)
              else
                left || right
              end
            end
          end
      end

      def attributes_trace(action = nil)
        if action.to_s == 'destroy'
          flag_destroyed(self.class, captured_attributes)
        else
          build_trace(self, captured_attributes)
        end
      end

      def trace_model
        Trace
      end

      def trace_action_attributes(action = nil)
        {
          target_model_name: self.class.to_s,
          target_id: id,
          attributes_trace: attributes_trace(action)
        }
      end

      def trace_action!(action, message = nil)
        trace_action("#{action}!", message)
      end

      def trace_action(action, message = nil)
        trace_attrs = trace_action_attributes(action)
        trace_attrs[:action] ||= action || :trace
        trace_attrs[:message] = message if message
        trace = trace_model.create(trace_attrs)
        @captured_attributes_trace = nil
        trace
      end

      def method_missing(symbol, *args, &block)
        if (match = symbol.to_s.match(/\Atrace_(.+)\Z/))
          trace_action(*[match[1], args].flatten)
        else
          super
        end
      end

      def build_trace(record, before)
        before ||= {}
        trace = {}
        current_attributes = record.current_attributes
        Set.new(current_attributes.keys + before.keys - record.trace_ignore).each do |attr|
          record_value = current_attributes[attr]
          if (relation = record.reflect_on_association(attr)) && (relation.embedded? || trace_references.include?(relation.name.to_s))
            if relation.many?
              sub_traces = []
              before_items = (before[attr] || []).collect { |item| [item['_id'], item] }.to_h
              unchanged = true
              record.send(attr).each do |sub_record|
                sub_record_trace = build_trace(sub_record, before_items.delete(sub_record.id))
                unchanged &&= sub_record_trace.empty?
                sub_record_trace['_id'] = sub_record.id
                sub_record_trace.delete(relation.foreign_key.to_s) unless relation.embedded?
                sub_traces << sub_record_trace
              end
              unless before_items.empty?
                unchanged = false
                before_items.values.each { |sub_item| sub_traces << flag_destroyed(relation.klass, sub_item) }
              end
              trace[attr] = sub_traces unless unchanged
            else
              if (sub_record = record.send(attr))
                sub_trace = build_trace(sub_record, before[attr])
                sub_trace.delete(relation.foreign_key.to_s) unless relation.embedded?
                trace[attr] = sub_trace unless sub_trace.empty?
              elsif (sub_item = before[attr])
                trace[attr] = flag_destroyed(relation.klass, sub_item)
              end
            end
          else
            trace[attr] = record_value unless record_value == before[attr]
          end
        end
        trace
      end

      def traces
        trace_model.where(target_id: id)
      end

      def flag_destroyed(model, trace)
        destroy_trace = { Mongoid::Tracer::DESTROYED_FLAG => true }
        trace.each do |attr, value|
          next if attr == Mongoid::Tracer::DESTROYED_FLAG || model.trace_ignore.include?(attr)
          destroy_trace[attr] =
            if (r = model.reflect_on_association(attr))
              if r.many?
                value.collect { |item| flag_destroyed(r.klass, item) }
              else
                flag_destroyed(r.klass, value)
              end
            else
              value
            end
        end
        destroy_trace
      end
    end
  end
end
