module Mongoid
  module Tracer
    module DocumentExtension
      extend ActiveSupport::Concern

      include Mongoid::Tracer::Options

      def current_attributes
        attrs = attributes.except(*trace_ignore)
        reflect_on_all_associations(:embeds_one, :embeds_many, :has_one, :has_many).each do |relation|
          next unless trace_ignore.exclude?(relation.name.to_s) && (relation.embedded? || trace_references.include?(relation.name.to_s))
          if relation.many?
            unless (docs_attrs = send(relation.name).collect(&:current_attributes)).empty?
              attrs[relation.name.to_s] = docs_attrs
            end
          elsif (doc = send(relation.name))
            attrs[relation.name.to_s] = doc.current_attributes
          end
        end
        each_trace_included { |property, value| attrs[property] = value unless attrs.key?(property) }
        attrs
      end

      def each_trace_included(&block)
        trace_include.each do |property|
          next if trace_ignore.include?(property)
          case (value = send(property))
          when NilClass, String, Numeric, Boolean, Hash, Array
            block.call(property, value)
          else
            fail "Illegal property trace value type: #{value.class}"
          end
        end
      end

      def set_association_values(association_name, values)
        send(association_name)
        target_proxy = instance_variable_get(:"@_#{association_name}")
        target_proxy.target.clear
        target_proxy.target.concat(values)
      end
    end
  end
end
