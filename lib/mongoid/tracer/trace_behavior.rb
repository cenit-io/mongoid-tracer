module Mongoid
  module Tracer
    module TraceBehavior
      extend ActiveSupport::Concern

      include Mongoid::Document
      include Mongoid::Timestamps::Created

      included do
        field :action, type: StringifiedSymbol
        field :message, type: String
        field :target_model_name
        field :target_id
        field :attributes_overrides, type: Hash
        field :attributes_trace, type: Hash
        field :author_id

        before_save :validates_trace_action!, :set_author_id
      end

      def validates_trace_action!
        throw(:abort) unless validates_trace_action
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

      def target_before_action(current = nil)
        return nil if action == :create
        record =
          if self.next
            self.next.target_before_action(current)
          else
            current || target
          end || target_model.new
        revert_changes_on(record)
        record
      end

      def revert_changes_on(record, changes = changes_set)
        changes.each do |attr, values|
          if (relation = record.class.reflect_on_association(attr))
            if relation.many?
              new_associates = []
              association = record.send(relation.name)
              values.each do |associate_changes|
                next unless (before_id = associate_changes['_id'][0])
                associate =
                  begin
                    association.find(before_id)
                  rescue
                    relation.klass.new(id: before_id)
                  end
                revert_changes_on(associate, associate_changes)
                new_associates << associate
              end
              record.set_association_values(relation.name, new_associates)
            else
              if (before_id = values['_id'][0])
                associate = send(relation.name) || relation.klass.new(id: before_id)
                revert_changes_on(associate, values)
              else
                associate = nil
              end
              record.send("#{relation.name}=", associate)
            end
          else
            unless (value_before = values[0]).nil? && action == :create
              record.send("#{attr}=", value_before)
            end
          end
        end
      end

      def target_after_action(current = nil)
        if self.next
          self.next.target_before_action(current)
        else
          current || target
        end
      end

      def changes_set(previous_trace = nil)
        @changes_set ||= build_changes_set_from(target_model, attributes_trace, [], {}, previous_trace || previous)
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
          @previous = self.class.with(persistence_context) do |klass|
            klass.where(target_id: target_id, :created_at.lt => created_at).desc(:created_at).limit(1).first
          end
          @previous_cached = true
        end
        @previous
      end

      def next
        unless @next_cached
          @next = self.class.with(persistence_context) do |klass|
            klass.where(target_id: target_id, :created_at.gt => created_at).asc(:created_at).limit(1).first
          end
          @next_cached = true
        end
        @next
      end
    end
  end
end
