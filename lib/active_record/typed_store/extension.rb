# frozen_string_literal: true

require 'active_record/typed_store/dsl'
require 'active_record/typed_store/behavior'
require 'active_record/typed_store/type'
require 'active_record/typed_store/typed_hash'
require 'active_record/typed_store/identity_coder'

module ActiveRecord::TypedStore
  module Extension
    def typed_store(store_attribute, options={}, &block)
      unless self < Behavior
        include Behavior
        class_attribute :typed_stores, :store_accessors, instance_accessor: false
      end

      dsl = DSL.new(store_attribute, options, &block)
      self.typed_stores = (self.typed_stores || {}).merge(store_attribute => dsl)
      self.store_accessors = typed_stores.each_value.flat_map(&:accessors).map { |a| -a.to_s }.to_set

      typed_klass = TypedHash.create(dsl.fields.values)
      const_set("#{store_attribute}_hash".camelize, typed_klass)

      if ActiveRecord.version >= Gem::Version.new('6.1.0.alpha')
        attribute(store_attribute) do |subtype|
          subtype = subtype.subtype if subtype.is_a?(Type)
          Type.new(typed_klass, dsl.coder, subtype)
        end
      else
        decorate_attribute_type(store_attribute, :typed_store) do |subtype|
          Type.new(typed_klass, dsl.coder, subtype)
        end
      end
      store_accessor(store_attribute, dsl.accessors)

      dsl.accessors.each do |accessor_name|
        define_method("#{accessor_name}_changed?") do
          send("#{store_attribute}_changed?") &&
            send(store_attribute)[accessor_name] != send("#{store_attribute}_was")[accessor_name]
        end

        define_method("#{accessor_name}_was") do
          send("#{store_attribute}_was")[accessor_name]
        end

        define_method("restore_#{accessor_name}!") do
          send("#{accessor_name}=", send("#{accessor_name}_was"))
        end

        define_method("saved_change_to_#{accessor_name}?") do
          return false unless saved_change_to_attribute?(store_attribute)
          prev_store, new_store = saved_change_to_attribute(store_attribute)
          prev_store&.dig(accessor_name) != new_store&.dig(accessor_name)
        end

        define_method("#{accessor_name}_before_last_save") do
          return unless saved_change_to_attribute?(store_attribute)
          prev_store, _new_store = saved_change_to_attribute(store_attribute)
          prev_store&.dig(accessor_name)
        end
      end
    end
  end
end
