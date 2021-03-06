require 'cfndsl/jsonable'
require 'cfndsl/names'
require 'cfndsl/aws/types'
require 'cfndsl/os/types'

module CfnDsl
  # Handles the overall template object
  # rubocop:disable Metrics/ClassLength
  class OrchestrationTemplate < JSONable
    dsl_attr_setter :AWSTemplateFormatVersion, :Description
    dsl_content_object :Condition, :Parameter, :Output, :Resource, :Mapping

    def self.external_parameters(params = nil)
      @external_parameters = params if params
      @external_parameters
    end

    def external_parameters
      self.class.external_parameters
    end

    def initialize
      @AWSTemplateFormatVersion = '2010-09-09'
    end

    GlobalRefs = {
      'AWS::NotificationARNs' => 1,
      'AWS::Region' => 1,
      'AWS::StackId' => 1,
      'AWS::StackName' => 1,
      'AWS::AccountId' => 1,
      'AWS::NoValue' => 1
    }.freeze

    # rubocop:disable Metrics/PerceivedComplexity
    def valid_ref?(ref, origin = nil)
      ref = ref.to_s
      origin = origin.to_s if origin

      return true if GlobalRefs.key?(ref)

      return true if @Parameters && @Parameters.key?(ref)

      if @Resources.key?(ref)
        return !origin || !@_resource_refs || !@_resource_refs[ref] || !@_resource_refs[ref].key?(origin)
      end

      false
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def check_refs
      invalids = check_resource_refs + check_output_refs

      invalids.empty? ? nil : invalids
    end

    def check_resource_refs
      invalids = []

      @_resource_refs = {}
      if @Resources
        @Resources.keys.each do |resource|
          @_resource_refs[resource.to_s] = @Resources[resource].build_references({})
        end
        @_resource_refs.keys.each do |origin|
          @_resource_refs[origin].keys.each do |ref|
            invalids.push "Invalid Reference: Resource #{origin} refers to #{ref}" unless valid_ref?(ref, origin)
          end
        end
      end

      invalids
    end

    def check_output_refs
      invalids = []

      output_refs = {}
      if @Outputs
        @Outputs.keys.each do |resource|
          output_refs[resource.to_s] = @Outputs[resource].build_references({})
        end
        output_refs.keys.each do |origin|
          output_refs[origin].keys.each do |ref|
            invalids.push "Invalid Reference: Output #{origin} refers to #{ref}" unless valid_ref?(ref)
          end
        end
      end

      invalids
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    def self.create_types
      names = {}
      nametypes = {}
      template_types['Resources'].each_pair do |name, type|
        # Subclass ResourceDefintion and generate property methods
        klass = Class.new(CfnDsl::ResourceDefinition)
        klassname = name.split('::').join('_')
        type_module.const_set(klassname, klass)
        type['Properties'].each_pair do |pname, ptype|
          if ptype.instance_of?(String)
            create_klass = type_module.const_get(ptype)

            klass.class_eval do
              CfnDsl.method_names(pname) do |method|
                define_method(method) do |*values, &block|
                  values.push create_klass.new if values.empty?

                  @Properties ||= {}
                  @Properties[pname] = CfnDsl::PropertyDefinition.new(*values)
                  @Properties[pname].value.instance_eval(&block) if block
                  @Properties[pname].value
                end
              end
            end
          else
            # Array version
            klass.class_eval do
              CfnDsl.method_names(pname) do |method|
                define_method(method) do |*values, &block|
                  values.push [] if values.empty?
                  @Properties ||= {}
                  @Properties[pname] ||= PropertyDefinition.new(*values)
                  @Properties[pname].value.instance_eval(&block) if block
                  @Properties[pname].value
                end
              end
            end

            sing_name = CfnDsl::Plurals.singularize(pname)
            create_klass = type_module.const_get(ptype[0])
            sing_names = sing_name == pname ? [ptype[0]] : [ptype[0], sing_name]

            klass.class_eval do
              sing_names.each do |sname|
                CfnDsl.method_names(sname) do |method|
                  define_method(method) do |value = nil, &block|
                    @Properties ||= {}
                    @Properties[pname] ||= PropertyDefinition.new([])
                    value = create_klass.new unless value
                    @Properties[pname].value.push value
                    value.instance_eval(&block) if block
                    value
                  end
                end
              end
            end
          end
        end
        parts = name.split('::')
        until parts.empty?
          abreve_name = parts.join('_')
          if names.key?(abreve_name)
            # this only happens if there is an ambiguity
            names[abreve_name] = nil
          else
            names[abreve_name] = type_module.const_get(klassname)
            nametypes[abreve_name] = name
          end
          parts.shift
        end
      end

      # Define property setter methods for each of the unambiguous type names
      names.each_pair do |typename, type|
        next unless type

        class_eval do
          CfnDsl.method_names(typename) do |method|
            define_method(method) do |name, *values, &block|
              name = name.to_s
              @Resources ||= {}
              resource = @Resources[name] ||= type.new(*values)
              resource.instance_eval(&block) if block
              resource.instance_variable_set('@Type', nametypes[typename])
              resource
            end
          end
        end
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
  end
  # rubocop:enable Metrics/ClassLength
end
