require 'securerandom'
require_relative 'errors'

module Rbdux
  class Store
    class << self
      @instance = nil

      def instance
        @instance ||= Store.new
      end

      def reset
        @instance = nil
      end

      def method_missing(method, *args, &block)
        return unless instance.respond_to?(method)

        @instance.send(method, *args, &block)
      end
    end

    def with_store(store)
      raise ArgumentError unless store

      @store_container = store
    end

    def before(&block)
      validate_functional_inputs(block)

      @before_middleware << block

      self
    end

    def after(&block)
      validate_functional_inputs(block)

      @after_middleware << block

      self
    end

    def get(state_key = nil)
      if state_key
        @store_container.get(state_key)
      else
        @store_container.get_all
      end
    end

    def reduce(action, state_key = nil, &block)
      validate_functional_inputs(block)

      key = action.name

      reducers[key] = [] unless reducers.key?(key)
      reducers[key] << Reducer.new(state_key, block)

      self
    end

    def dispatch(action)
      validate_store_container

      previous_state = @store_container.get_all

      dispatched_action = apply_before_middleware(action)

      reducers.fetch(action.class.name, []).each do |reducer|
        apply_reducer!(reducer, dispatched_action)
      end

      apply_after_middleware(previous_state, dispatched_action)

      observers.values.each(&:call)
    end

    def subscribe(&block)
      validate_functional_inputs(block)

      subscriber_id = SecureRandom.uuid

      observers[subscriber_id] = block

      subscriber_id
    end

    def unsubscribe(subscriber_id)
      observers.delete(subscriber_id)
    end

    private

    Reducer = Struct.new(:state_key, :func)

    attr_reader :observers, :reducers

    def initialize
      @observers = {}
      @reducers = {}
      @before_middleware = []
      @after_middleware = []
    end

    def apply_before_middleware(action)
      dispatched_action = action

      @before_middleware.each do |m|
        new_action = m.call(self, dispatched_action)
        dispatched_action = new_action unless new_action.nil?
      end

      dispatched_action
    end

    def apply_after_middleware(previous_state, action)
      @after_middleware.each do |m|
        m.call(previous_state, get, action)
      end
    end

    def apply_reducer!(reducer, action)
      new_state = reducer.func.call(get(reducer.state_key), action)

      return if new_state.nil?

      if reducer.state_key
        @store_container.set(reducer.state_key, new_state)
      else
        @store_container.replace(new_state)
      end
    end

    def validate_functional_inputs(block)
      raise ArgumentError, 'You must define a block.' unless block
    end

    def validate_store_container
      raise Rbdux::Errors::MissingStoreContainerError unless @store_container
    end
  end
end
