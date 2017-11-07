module Mongoid
  module Tracer
    module TraceBehavior
      extend ActiveSupport::Concern

      include Mongoid::Document
      include Mongoid::Timestamps::Created

      included do
        field :action, type: Symbol
        field :message, type: String
        field :target_model_name
        field :target_id
        field :attributes_overrides, type: Hash
        field :attributes_trace, type: Hash
        field :author_id

        before_save :validates_trace_action, :set_author_id
      end

      def validates_trace_action
        if action.to_s.end_with?('!')
          self.action = action.to_s.chop
        else
          if !target_model.trace_action?(action)
            errors.add(:action, "is not mandatory and #{target_model} is not tracing it")
          elsif attributes_trace.empty?
            errors.add(:attributes_trace, "is empty and supplied action #{action} is not mandatory!")
          end
        end
        errors.empty?
      end

      def set_author_id
        if (author_id = Tracer.author_id)
          self.author_id = author_id
        end
        errors.empty?
      end

      def target_model
        @target_model ||=
          if target_model_name
            target_model_name.constantize
          else
            fail NotImplementedError
          end
      end

      def target
        @target ||= target_model.where(id: target_id).first
      end

      def changes_set
        @changes_set ||= build_changes_set_from(target_model, attributes_trace, [], {}, previous)
      end

      def build_changes_set_from(model, attributes, path, set, trace)
        if trace && !attributes[Mongoid::Tracer::DESTROYED_FLAG]
          look_at = trace.attributes_trace
          path_exists = true
          path.each do |key|
            if look_at.is_a?(Hash)
              look_at = (path_exists &&= look_at.key?(key)) && look_at[key]
            elsif look_at.is_a?(Array)
              look_at = path_exists = look_at.detect { |item| item['_id'] == key }
            end
            break unless look_at
          end
          if look_at
            (attributes.keys - set.keys).each do |attr|
              if (relation = model.reflect_on_association(attr))
                path << attr
                if (set[attr] = attributes[attr])
                  set[attr] =
                    if relation.many?
                      currents = []
                      destroyed = []
                      current_ids = Set.new
                      attributes[attr].collect do |item|
                        current_ids << item['_id']
                        if item.size == 1 # Only _id is traced for order preservation
                          currents << { '_id' => [item['_id'], item['_id']] }
                        elsif item[Mongoid::Tracer::DESTROYED_FLAG]
                          destroyed << fill_changes(relation.klass, item, {})
                        else
                          path << item['_id']
                          currents << build_changes_set_from(relation.klass, item, path, {}, trace)
                          path.pop
                        end
                      end
                      currents + destroyed
                    else
                      build_changes_set_from(relation.klass, attributes[attr], path, {}, trace)
                    end
                end
                path.pop
              elsif look_at.key?(attr)
                set[attr] = [look_at[attr], attributes[attr]]
              end
            end
          else
            return fill_changes(model, attributes, set) if path_exists
          end
          return set if set.size == attributes.size
          build_changes_set_from(model, attributes, path, set, trace.previous)
        else
          fill_changes(model, attributes, set)
        end
      end

      def fill_changes(model, attributes, set)
        changes = {}
        destroyed = attributes[Mongoid::Tracer::DESTROYED_FLAG]
        attributes.each do |attr, value|
          next if attr == Mongoid::Tracer::DESTROYED_FLAG || model.trace_ignore.include?(attr)
          unless (pair = set[attr])
            pair =
              if (r = model.reflect_on_association(attr))
                if r.many?
                  value.collect { |item| fill_changes(r.klass, item, {}) }
                else
                  fill_changes(r.klass, value, {})
                end
              elsif destroyed
                [value, nil]
              else
                [nil, value]
              end
          end
          changes[attr] = pair
        end
        changes
      end

      def previous
        unless @previous_cached
          if (@previous = class_with_options.where(target_id: target_id, :created_at.lt => created_at).desc(:created_at).limit(1).first) && persistence_options
            @previous = @previous.with(persistence_options)
          end
          @previous_cached = true
        end
        @previous
      end

      def next
        unless @next_cached
          if (@next = class_with_options.where(target_id: target_id, :created_at.gt => created_at).asc(:created_at).limit(1).first) && persistence_options
            @next = @next.with(persistence_options)
          end
          @next_cached = true
        end
        @next
      end

      def class_with_options
        if persistence_options
          self.class.with(persistence_options)
        else
          self.class
        end
      end
    end
  end
end
