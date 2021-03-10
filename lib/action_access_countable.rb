require "action_access_countable/version"
require 'active_support/concern'
require 'active_support/core_ext'

module ActionAccessCountable
  class Error < StandardError; end

  extend ActiveSupport::Concern

  ACCESS_COUNTABLE_PARAMS = {
    threshold: {
      max: 100,
      during: 1.month,
      ban: 1.year
    },
    store: {
      model: 'ActionAccessCounter',
      attributes: {
        action: :action,
        identifier: :identifier,
        count_since: :count_since,
        count_total: :count_total,
        since: :since
      },
    },
    identifier_key: 'HTTP_X_REAL_IP',
    autoincrement: true
  }.freeze

    private

  def init_action_access_counter(resource: "#{self.class}",
                                 params: ACCESS_COUNTABLE_PARAMS,
                                 &block)

    @access_counter_params = ACCESS_COUNTABLE_PARAMS
      .deep_merge(params.deep_symbolize_keys)
      .with_indifferent_access
    @access_counter = nil

    aac_params = @access_counter_params
    aac_attrs = @access_counter_params[:store][:attributes]
    aac_model = "#{aac_params[:store][:model]}".constantize

    collection = block_given? ? yield || {} : {}

    if identifier = collection.fetch(aac_params[:identifier_key], nil)
      @access_counter = aac_model.find_or_initialize_by(
        aac_attrs[:identifier] => "#{identifier}",
        aac_attrs[:action] => "#{resource || self.class}"
      )
      if @access_counter.new_record?
        @access_counter.send("#{aac_attrs[:since]}=", Time.current)
      end
    end

    @access_counter
  end

  def increment_access_counter
    return unless ac = @access_counter

    aac_attrs = @access_counter_params[:store][:attributes]

    ac.send("#{aac_attrs[:count_since]}=",
            ac.send("#{aac_attrs[:count_since]}") + 1)
    ac.send("#{aac_attrs[:count_total]}=",
            ac.send("#{aac_attrs[:count_total]}") + 1)

    ac
  end

  def action_access_accepted?
    return true unless @access_counter

    current = Time.current
    ac = @access_counter
    aac_attrs = @access_counter_params[:store][:attributes]

    increment_access_counter if @access_counter_params[:autoincrement]

    threshold = @access_counter_params[:threshold]
    count_since = ac.send(aac_attrs[:since])
    reset_from = count_since + threshold[:during]
    due_date = reset_from + threshold[:ban]

    reset_count_since = lambda do
      ac.send("#{aac_attrs[:since]}=", current)
      ac.send("#{aac_attrs[:count_since]}=", 1)
    end

    if ac.send(aac_attrs[:count_since]) <= threshold[:max] + 1
      if reset_from <= current
        reset_count_since.call
        accept = true
      elsif ac.send(aac_attrs[:count_since]) <= threshold[:max]
        accept = true
      else
        accept = false
      end
    else
      if due_date > current
        accept = false
      else
        reset_count_since.call
        accept = true
      end
    end
    ac.save

    accept
  end
end
