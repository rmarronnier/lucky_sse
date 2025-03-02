require "spec"
require "../src/lucky_sse"

# Mock implementation to help with testing
module Mocks
  # Add helper methods to emulate mocking for IO and other objects
  def self.allow(object)
    AllowHelper.new(object)
  end

  class AllowHelper(T)
    def initialize(@object : T)
    end

    def receive(method_name)
      MethodHelper.new(@object, method_name.to_s)
    end
  end

  class MethodHelper(T)
    def initialize(@object : T, @method_name : String)
    end

    def and_return(&block : -> U) forall U
      # This is a simplistic mock implementation
      # In a real environment, you'd use a proper mocking library
      {% for method in T.methods %}
        {% if method.name.stringify == "@method_name" %}
          def @object.{{method.name}}({% for arg, index in method.args %}{% if index > 0 %}, {% end %}{{arg}}{% end %})
            yield
          end
        {% end %}
      {% end %}
    end

    def and_raise(exception)
      # This is a simplistic mock implementation
      # In a real environment, you'd use a proper mocking library
      {% for method in T.methods %}
        {% if method.name.stringify == "@method_name" %}
          def @object.{{method.name}}({% for arg, index in method.args %}{% if index > 0 %}, {% end %}{{arg}}{% end %})
            raise exception
          end
        {% end %}
      {% end %}
    end
  end
end

include Mocks

# Make to_s available on IO::Memory for spec verification
class IO::Memory
  def to_s
    String.new(to_slice)
  end
end

# Add helper extensions to make testing easier
class HTTP::Server::Response
  # Allow access to the IO for testing
  def output
    @io
  end
end
