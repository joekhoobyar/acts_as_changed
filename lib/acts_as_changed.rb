module ActiveRecord
  module Acts
    module Changed
      def self.included(base) # :nodoc:
        base.extend(ClassMethods)
      end
      
      module ClassMethods
      
        # Makes an ActiveRecord model keep track of it's original attributes so that changes can be detected.
        # 
        # Only one option is supported:
        # 
        # update_changes:: true / false
        # 
        # If this option evaluates to true, update_attribute(s) and friends will update any changed attributes.
        # Otherwise, by default, they will update each of the specified attribute(s).
        # 
        def acts_as_changed(options={})
          unless acts_as_changed?
            include InstanceMethods
            
            attribute_method_suffix '_default'
            attribute_method_suffix '_original'
            attribute_method_suffix '_original?'
            attribute_method_suffix '_changed?'
            
	          alias_method_chain :initialize, :changed
	          alias_method_chain :clone, :changed
	          alias_method_chain :create_or_update, :changed
	          with = options[:update_changes] ? :changed : :only
	          alias_method_chain :update_attribute, with
	          alias_method_chain :update_attribute_without_validation_skipping, with
	          alias_method_chain :update_attributes!, with
	          alias_method_chain :update_attributes, with
	          
            class << self
              alias_method_chain :instantiate, :changed
            end
	          self.class_eval do
	            def update_attribute_without_timestamps(name, value)
	              update_attribute name, value, false
	            end
	          end if with == :only
          end
        end
        
        # Does this AR model support acts_as_changed?
        def acts_as_changed?
          included_modules.include?(ActiveRecord::Acts::Changed::InstanceMethods)
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
        
        # Initialization.
	      def initialize_with_changed(attributes = nil)
	        initialize_without_changed attributes
	        @original_attributes = {}
	        yield self if block_given?
	      end
	
        # Initialization.
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
	        read_original_attribute(attribute) != read_attribute(attribute)
	      end
	      alias :attr_changed? :attribute_changed?
	
        # Queries an original attribute value (like AR's query_attribute).
	      def attribute_original?(attribute)
	        query_original_attribute(attribute)
	      end
	      alias :attr_original? :attribute_original?
	
	      # Returns a hash of all the default attributes with their names as keys and clones of their objects as values.
	      def default_attributes(options = nil)
	        default_attributes = clone_attributes :read_attribute_default
	        return default_attributes if options.nil?
	        
          if (except = options[:except])
            except = Array(except).collect { |attribute| attribute.to_s }
            except.each { |attribute_name| default_attributes.delete(attribute_name) }
            default_attributes
          elsif (only = options[:only])
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
	
          if (except = options[:except])
            except = Array(except).collect { |attribute| attribute.to_s }
            except.each { |attribute_name| attributes.delete(attribute_name) }
            attributes
          elsif (only = options[:only])
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
	        
          if (except = options[:except])
            except = Array(except).collect { |attribute| attribute.to_s }
            except.each { |attribute_name| attributes.delete(attribute_name) }
            attributes
          elsif (only = options[:only])
            only = Array(only).collect { |attribute| attribute.to_s }
            attributes.delete_if { |key, value| !only.include?(key) }
            attributes
          else
            raise ArgumentError, "Options does not specify :except or :only (#{options.keys.inspect})"
          end
	      end
	      alias_method :changes, :changed_attributes
		      
	      # Returns a copy of changed attributes where all the values have been safely quoted for use in
	      # an SQL statement.
	      def changed_attributes_with_quotes(include_primary_key = true)
	        changed_attributes.inject({}) do |quoted, (name, value)|
	          if column = column_for_attribute(name)
	            quoted[name] = quote_value(value, column) unless !include_primary_key && column.primary
	          end
	          quoted
	        end
	      end
		      
	      # Returns a copy of the named attributes where all the values have been safely quoted for use in
	      # an SQL statement.
	      def named_attributes_with_quotes(names)
	        names.inject({}) do |quoted, name|
	          if column = column_for_attribute(name)
		          quoted[name] = quote_value(attributes[name.to_s], column)
		        end
	          quoted
	        end
	      end

        # Returns true if any of the given attributes have changed.	
	      def changed?(names=nil)
	        return true if new_record?
	        return ! original_attributes.diff(attributes).empty? if names.nil?
	        return attr_changed?(names) unless names.is_a? Array
	        names.each do |name| return true if attr_changed?(name) end
	        false
	      end

        # Saves all of this record's attributes (a la save) only if any attribute has changed.	
	      def save_if_changed
	        changed? ? save : true
	      end

        # Saves all of this record's attributes (a la save!) only if any attribute has changed.	
	      def save_if_changed!
	        changed? ? save! : true
	      end
	      
        # Saves any changes to this record's attributes (a la save) only if any attribute has changed.	
	      def save_changes(perform_validation = true)
	        return true unless new_record? or changed?
		      return false if perform_validation && !valid?
	        create_or_update_changed
	      end
	      
        # Saves any changes to this record's attributes (a la save!) only if any attribute has changed.	
	      def save_changes!
	        save_changes || _raise_save_errors
	      end
	      
        # Saves only the named attributes (a la save).	
	      def save_only(names, perform_validation=true, with_timestamps=record_timestamps)
		      return false if perform_validation && !valid?
	        create_or_update_only(names, with_timestamps)
	      end
	      
        # Saves only the named attributes (a la save!).	
	      def save_only!(names)
	        save_only(names) || _raise_save_errors
	      end
	
        # Saves any changes to this record's attributes (a la update_attribute) only if any attribute has changed.	
	      def update_attribute_with_changed(name, value)
	        send(name.to_s + '=', value)
	        save_changes(false)
	      end
	
        # Saves only the given attribute (a la update_attribute).
	      def update_attribute_with_only(name, value, with_timestamps=record_timestamps)
	        send(name.to_s + '=', value)
	        save_only([name], false, with_timestamps)
	      end
	
        # Saves any changes to this record's attributes (a la update_attribute) only if any attribute has changed.
        # Does *NOT* skip validation.	
	      def update_attribute_without_validation_skipping_with_changed(name, value)
	        send(name.to_s + '=', value)
	        save_changes
	      end
	
        # Saves only the given attribute (a la update_attribute).
        # Does *NOT* skip validation.	
	      def update_attribute_without_validation_skipping_with_only(name, value, with_timestamps=record_timestamps)
	        send(name.to_s + '=', value)
	        save_only([name], true, with_timestamps)
	      end
	
        # Saves any changes to this record's attributes (a la update_attribute) only if any attribute has changed.	
	      def update_attributes_with_changed(attributes)
	        self.attributes = attributes
	        save_changes
		    rescue ActiveRecord::MultiparameterAssignmentErrors => e
		      e.errors.map(&:attribute).uniq.each { |k| errors.add k, 'is not valid' }
		      false
	      end
	      
        # Saves only the given attribute (a la update_attribute).
	      def update_attributes_with_only(attributes)
	        return unless attributes.is_a? Hash
	        self.attributes = attributes
	        save_only attributes.keys.map { |k| k = k.to_s; n = k.index('('); (n ? k[0,n] : k).to_sym }.uniq
		    rescue ActiveRecord::MultiparameterAssignmentErrors => e
		      e.errors.map(&:attribute).uniq.each { |k| errors.add k, 'is not valid' }
		      false
	      end
	      
        # Saves any changes to this record's attributes (a la update_attribute) only if any attribute has changed.
        # Does *NOT* skip validation.	
	      def update_attributes_with_changed!(attributes)
	        self.attributes = attributes
	        save_changes!
	      end
	
        # Saves only the given attribute (a la update_attribute).
        # Does *NOT* skip validation.	
	      def update_attributes_with_only!(attributes)
	        update_attributes_with_only(attributes) || _raise_save_errors
	      end
	
        # Returns all changes attribute names.	
	      def changed_attribute_names
	        original_attributes.diff(attributes).keys.reject { |k| k=='updated_at' }.sort
	      end
	
	      def freeze
	        @attributes.freeze
	        @original_attributes.freeze
	        self
	      end

      protected
        unless method_defined? :_raise_save_errors
          # Convenience to raise an error after attempting a save.
        	def _raise_save_errors(title='Failed to save record:', body=nil)
        	  body ||= errors.full_messages.join(', ') rescue '(no error messages)'
        	  raise(RecordNotSaved, "#{title} #{body}")
        	end
        end
	      
	    private
	      def create_or_update_with_changed
	        result = create_or_update_without_changed
	        @original_attributes = attributes if result
	        result
	      end
	
	      def create_or_update_changed
	        raise ReadOnlyRecord if readonly?
		      return false if callback(:before_save) == false
	        result = new_record? ? create : update_changed
	        return false if result == false
		      callback(:after_save)
	        @original_attributes = attributes
	        true
	      end
	
	      def create_or_update_only(names, with_timestamps=record_timestamps)
	        raise ReadOnlyRecord if readonly?
		      return false if callback(:before_save) == false
	        result = new_record? ? create : update_only(names, with_timestamps)
	        return false if result == false
		      callback(:after_save)
	        @original_attributes = attributes
	        true
	      end
	
	      # Updates the associated record with the changed instance attributes.
	      # Returns the number of affected rows.
	      def update_changed
		      if record_timestamps
		        t = self.class.default_timezone == :utc ? Time.now.utc : Time.now
		        write_attribute('updated_at', t) if respond_to?(:updated_at)
		        write_attribute('updated_on', t) if respond_to?(:updated_on)
		      end
		      return false if callback(:before_update) == false
		      chgs = changed_attributes_with_quotes(false)
	        result = chgs.empty? || connection.update(
	          "UPDATE #{self.class.table_name} " +
	          "SET #{quoted_comma_pair_list(connection, chgs)} " +
	          "WHERE #{self.class.primary_key} = #{quote_value(id)}",
	          "#{self.class.name} Update"
	        )
		      callback(:after_update)
		      result
	      end
	
	      # Updates the associated record with the named attributes only.
	      # Returns the number of affected rows.
	      def update_only(names, with_timestamps=record_timestamps)
		      if with_timestamps
		        t = self.class.default_timezone == :utc ? Time.now.utc : Time.now
		        if respond_to?(:updated_at)
			        write_attribute('updated_at', t)
			        names << :updated_at
			      end
			      if respond_to?(:updated_on)
			        write_attribute('updated_on', t)
			        names << :updated_on 
			      end
		      end
	        return false if callback(:before_update) == false
	        values = quoted_comma_pair_list(connection, named_attributes_with_quotes(names))
	        result = values.nil? || (values = values.strip).blank? || connection.update(
	          "UPDATE #{self.class.table_name} " +
	          "SET #{values} " +
	          "WHERE #{self.class.primary_key} = #{quote_value(id)}",
	          "#{self.class.name} Update"
	        )
		      callback(:after_update)
		      result
	      end
	      
	      def read_attribute_default(attr_name)
	        attr_name = attr_name.to_s
	        if (column = column_for_attribute(attr_name))
	          if unserializable_attribute?(attr_name, column)
	            unserialize_value_for_attribute(column.default, column.name)
	          else
	            column.type_cast(column.default)
	          end
	        else
	          column.default
	        end
	      end
	
	      def read_original_attribute(attr_name)
	        attr_name = attr_name.to_s
	        if !(value = @original_attributes[attr_name]).nil?
	          if (column = column_for_attribute(attr_name))
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
        
        def query_original_attribute(attr_name)
          attribute = @original_attributes[attr_name.to_s]
          if attribute.kind_of?(Fixnum) && attribute == 0
            false
          elsif attribute.kind_of?(String) && attribute == "0"
            false
          elsif attribute.kind_of?(String) && attribute.empty?
            false
          elsif attribute.nil?
            false
          elsif attribute == false
            false
          elsif attribute == "f"
            false
          elsif attribute == "false"
            false
          else
            true
          end
        end
	      
	      def clone_changed_attributes(reader_method = :read_attribute, attributes = {})
	        self.changed_attribute_names.each { |name| attributes[name] = clone_attribute_value(reader_method, name) }
	        attributes
	      end

      public
      	      
	      # Returns the default value of an attribute, type-casted.
	      alias :attribute_default :read_attribute_default
	      
	      # Returns the original value of the attribute, type-casted.
	      alias :attribute_original :read_original_attribute
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActiveRecord::Acts::Changed)
