module ActiveRecord
  module Acts
    module Changed
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
        def acts_as_changed
          unless self.included_modules.include?(ActiveRecord::Acts::Changed::InstanceMethods)
            include InstanceMethods
	          alias_method_chain :initialize, :changed
	          alias_method_chain :clone, :changed
	          alias_method_chain :create_or_update, :changed
	          alias_method_chain :update_attribute, :changed
	          alias_method_chain :update_attributes!, :changed
	          alias_method_chain :update_attributes, :changed
            class << self
              alias_method_chain :instantiate, :changed
            end
          end
        end
      end
      
      module InstanceMethods
        
        def self.included(base) # :nodoc:
          base.extend ClassMethods
        end
      
        module ClassMethods
	        
	        def has_attribute?(key)
	          columns_hash.has_key?(key.to_s)
	        end
	        
	        def instantiate_with_changed(record)
	          object = instantiate_without_changed(record)
	          object.instance_variable_set("@original_attributes", record.dup)
	          object
	        end
        end
        
	      def initialize_with_changed(attributes = nil)
	        initialize_without_changed attributes
	        @original_attributes = {}
	        yield self if block_given?
	      end
	
	      def clone_with_changed
	        clone_without_changed
	        self.class.new do |record|
	          record.send :instance_variable_set, '@original_attributes', attributes
	        end
	      end
	
	      # Resets the changed attributes to the original state of the object,
	      # without reloading the object from the database.
	      def reset(options = nil)
	        clear_aggregation_cache
	        clear_association_cache
	        @attributes = @original_attributes
	        self
	      end
	      alias :revert :reset

        # Resets a single attribute.	
	      def reset_attribute(attribute)
	        @attributes[attribute] = @original_attributes[attribute]
	      end
	      alias :revert_attribute :reset_attribute

        # Checks a single attribute to see if it has changed.	
	      def attribute_changed?(attribute)
	        @original_attributes[attribute] != @attributes[attribute]
	      end
	      alias :attr_changed? :attribute_changed?
	
	      # Returns a hash of all the default attributes with their names as keys and clones of their objects as values.
	      def default_attributes(options = nil)
	        default_attributes = clone_attributes :read_attribute_default
	        return default_attributes if options.nil?
	        
          if except = options[:except]
            except = Array(except).collect { |attribute| attribute.to_s }
            except.each { |attribute_name| default_attributes.delete(attribute_name) }
            default_attributes
          elsif only = options[:only]
            only = Array(only).collect { |attribute| attribute.to_s }
            default_attributes.delete_if { |key, value| !only.include?(key) }
            default_attributes
          else
            raise ArgumentError, "Options does not specify :except or :only (#{options.keys.inspect})"
          end
	      end
	
	      # Returns a hash of all the original attributes with their names as keys and clones of their objects as values.
	      def original_attributes(options = nil)
	        attributes = clone_attributes :read_original_attribute
	        return attributes if options.nil?
	
          if except = options[:except]
            except = Array(except).collect { |attribute| attribute.to_s }
            except.each { |attribute_name| attributes.delete(attribute_name) }
            attributes
          elsif only = options[:only]
            only = Array(only).collect { |attribute| attribute.to_s }
            attributes.delete_if { |key, value| !only.include?(key) }
            attributes
          else
            raise ArgumentError, "Options does not specify :except or :only (#{options.keys.inspect})"
          end
	      end
	
	      # Returns a hash of all the changd attributes with their names as keys and clones of their objects as values.
	      def changed_attributes(options = nil)
	        attributes = clone_changed_attributes :read_attribute
	        return attributes if options.nil?
	        
          if except = options[:except]
            except = Array(except).collect { |attribute| attribute.to_s }
            except.each { |attribute_name| attributes.delete(attribute_name) }
            attributes
          elsif only = options[:only]
            only = Array(only).collect { |attribute| attribute.to_s }
            attributes.delete_if { |key, value| !only.include?(key) }
            attributes
          else
            raise ArgumentError, "Options does not specify :except or :only (#{options.keys.inspect})"
          end
	      end
	      alias_method :changes, :changed_attributes
		      
	      # Returns copy of the attributes hash where all the values have been safely quoted for use in
	      # an SQL statement.
	      def changed_attributes_with_quotes(include_primary_key = true)
	        changed_attributes.inject({}) do |quoted, (name, value)|
	          if column = column_for_attribute(name)
	            quoted[name] = quote_value(value, column) unless !include_primary_key && column.primary
	          end
	          quoted
	        end
	      end
	
	      def changed?
	        (new_record? || ! original_attributes.diff(attributes).empty?) ? true : false
	      end
	
	      def save_if_changed
	        changed? ? save : true
	      end
	
	      def save_if_changed!
	        changed? ? save! : true
	      end
	      
	      def save_changes(perform_validation = true)
	        return true unless new_record? or changed?
		      return false if perform_validation && !valid?
	        create_or_update_changed || raise(RecordNotSaved)
	      end
	      
	      def save_changes!
	        save_changes || raise(RecordNotSaved)
	      end
	
	      def update_attribute_with_changed(name, value)
	        send(name.to_s + '=', value)
	        save_changes(false)
	      end
	
	      def update_attribute_without_validation_skipping(name, value)
	        send(name.to_s + '=', value)
	        save_changes
	      end
	
	      def update_attributes_with_changed(attributes)
	        self.attributes = attributes
	        save_changes
	      end
	      
	      def update_attributes_with_changed!(attributes)
	        self.attributes = attributes
	        save_changes!
	      end
	
	      def changed_attribute_names
	        original_attributes.diff(attributes).keys.sort
	      end
	
	      def freeze
	        @attributes.freeze
	        @original_attributes.freeze
	        self
	      end
	      
	    private
	      def create_or_update_with_changed
	        result = create_or_update_without_changed
	        @original_attributes = attributes if result
	      end
	
	      def create_or_update_changed
	        raise ReadOnlyRecord if readonly?
	        result = new_record? ? create : update_changed
	        return false if result == false
	        @original_attributes = attributes
	        true
	      end
	
	      # Updates the associated record with values matching those of the instance attributes.
	      # Returns the number of affected rows.
	      def update_changed
		      if record_timestamps
		        t = self.class.default_timezone == :utc ? Time.now.utc : Time.now
		        write_attribute('updated_at', t) if respond_to?(:updated_at)
		        write_attribute('updated_on', t) if respond_to?(:updated_on)
		      end
	        connection.update(
	          "UPDATE #{self.class.table_name} " +
	          "SET #{quoted_comma_pair_list(connection, changed_attributes_with_quotes(false))} " +
	          "WHERE #{self.class.primary_key} = #{quote_value(id)}",
	          "#{self.class.name} Update"
	        )
	      end
	      
	      def read_attribute_default(attr_name)
	        attr_name = attr_name.to_s
	        if column = column_for_attribute(attr_name)
	          if unserializable_attribute?(attr_name, column)
	            unserialize_value_for_attribute(column.default, column.name)
	          else
	            column.type_cast(column.default)
	          end
	        else
	          column.default
	        end
	      end
	      
	      # Returns the value of the attribute identified by <tt>attr_name</tt> after it has been typecast (for example,
	      # "2004-12-12" in a data column is cast to a date object, like Date.new(2004, 12, 12)).
	      # Check for a changed_attribute first, then for original.
	      def read_original_attribute(attr_name)
	        attr_name = attr_name.to_s
	        if !(value = @original_attributes[attr_name]).nil?
	          if column = column_for_attribute(attr_name)
	            if unserializable_attribute?(attr_name, column)
	              unserialize_attribute(attr_name)
	            else
	              column.type_cast(value)
	            end
	          else
	            value
	          end
	        else
	          nil
	        end
	      end
	
	      def clone_changed_attributes(reader_method = :read_attribute, attributes = {})
	        self.changed_attribute_names.inject(attributes) do |attributes, name|
	          attributes[name] = clone_attribute_value(reader_method, name)
	          attributes
	        end
	      end
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActiveRecord::Acts::Changed)
