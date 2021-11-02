# frozen_string_literal: true

require 'rspec/core/formatters/base_formatter'
require 'method_source'
require 'erb'

# rubocop:disable Style/Documentation
module RSpec
  # rubocop:enable Style/Documentation

  # Add our settings...
  configure do |config|
    config.add_setting(:apidoc_title)
    config.add_setting(:apidoc_description)
    config.add_setting(:apidoc_host)
    config.add_setting(
      :apidoc_template_path,
      default: File.expand_path('apidoc/static/template.html.erb', __dir__)
    )
    config.add_setting(:apidoc_output_filename, default: 'apidoc.html')
  end

  # Our formatter class.
  #
  # We're using the formatter as the hooks do not allow to report when the
  # test runner is done.
  class Apidoc < RSpec::Core::Formatters::BaseFormatter
    include ERB::Util

    # We want only passed tests registered and know when the runner is finished
    RSpec::Core::Formatters.register self, :example_passed, :close

    # Returns the title for our docs
    #
    # @return [String]
    def title
      RSpec.configuration.apidoc_title
    end

    # Returns the description for our docs
    #
    # @return [String]
    def description
      RSpec.configuration.apidoc_description
    end

    # Returns the template path used to render our docs
    #
    # @return [String]
    def template_path
      RSpec.configuration.apidoc_template_path
    end

    # Returns the final document path for our docs
    #
    # @return [String]
    def output_filename
      RSpec.configuration.apidoc_output_filename
    end

    # Returns the API host used to generate the `curl` commands
    #
    # @return [String]
    def host
      RSpec.configuration.apidoc_host
    end

    # Returns the collected examples, sorted
    #
    # @return [Array] a list of [Hash] items
    def examples
      @examples ||= {}
      @examples = @examples.sort.to_h
    end

    # Parses and stores relevant to our docs data in the example metadata
    #
    # @return [Hash] the metadata that was added
    # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    def self.add(spec, example)
      request_body = parse_json_safely(spec.request.body.string)
      response_body = parse_json_safely(spec.response.body)

      if spec.request.controller_instance
        action_comment = spec.request.controller_class.instance_method(
          spec.request.controller_instance.action_name
        ).comment
        # Remove any `@param` or `@return` lines
        action_comment = action_comment.delete('#').gsub(/@.*$/, '').strip
        controller_class = spec.request.controller_class
        action_name = spec.request.controller_instance.action_name
      else
        action_comment = nil
        controller_class = spec.request.path
        action_name = spec.request.method
      end

      example.metadata[:apidoc_data] = {
        description: example.metadata[:full_description],

        controller_class: controller_class,
        action_name: action_name,
        action_comment: action_comment,

        content_type: spec.request.content_type,
        method: spec.request.method,
        path: spec.request.path,
        query: spec.request.query_parameters.to_param,
        request_body: request_body,

        status: spec.response.status,
        response_content_type: spec.response.content_type,
        response_body: response_body
      }
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength

    # Returns a parsed JSON object
    #
    # @param obj [Object] an object to parse as JSON
    # @return [Object]
    def self.parse_json_safely(obj)
      JSON.parse(obj)
    rescue StandardError
      obj.to_s
    end

    # Formatter callback, stores the example metadata for later to be used
    #
    # @return [Hash] the metadata that was stored
    def example_passed(notification)
      apidoc_data = notification.example.metadata[:apidoc_data]

      return if apidoc_data.nil?

      controller_name = apidoc_data[:controller_class].to_s
      controller_examples = examples[controller_name] ||= {}
      controller_examples[apidoc_data[:action_name]] ||= []
      controller_examples[apidoc_data[:action_name]].append(apidoc_data)
    end

    # Formatter callback, generates the HTML from the metadata we stored
    #
    # @return [Integer] size of the new file.
    def close(_notification)
      return if examples.empty?

      erb = ERB.new(File.read(template_path))
      File.write(output_filename, erb.result(self.binding))
    end
  end
end