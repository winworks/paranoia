module Paranoia
  def self.included(klazz)
    klazz.extend Query
    klazz.extend Callbacks
  end

  module Query
    def paranoid? ; true ; end

    def with_deleted
      if ActiveRecord::VERSION::STRING >= "4.1"
        unscope where: paranoia_column
      else
        all.tap { |x| x.default_scoped = false }
      end
    end

    def only_deleted
      case paranoia_column_type
      when :datetime
        with_deleted.where.not(paranoia_column => nil)
      when :boolean
        with_deleted.where(paranoia_column => true)
      end
    end
    alias :deleted :only_deleted

    def restore(id, opts = {})
      if id.is_a?(Array)
        id.map { |one_id| restore(one_id, opts) }
      else
        only_deleted.find(id).restore!(opts)
      end
    end
  end

  module Callbacks
    def self.extended(klazz)
      klazz.define_callbacks :restore

      klazz.define_singleton_method("before_restore") do |*args, &block|
        set_callback(:restore, :before, *args, &block)
      end

      klazz.define_singleton_method("around_restore") do |*args, &block|
        set_callback(:restore, :around, *args, &block)
      end

      klazz.define_singleton_method("after_restore") do |*args, &block|
        set_callback(:restore, :after, *args, &block)
      end
    end
  end

  def destroy
    callbacks_result = run_callbacks(:destroy) { touch_paranoia_column(true) }
    callbacks_result ? self : false
  end

  # As of Rails 4.1.0 +destroy!+ will no longer remove the record from the db
  # unless you touch the paranoia column before.
  # We need to override it here otherwise children records might be removed
  # when they shouldn't
  if ActiveRecord::VERSION::STRING >= "4.1"
    def destroy!
      destroyed? ? super : destroy || raise(ActiveRecord::RecordNotDestroyed)
    end
  end

  def delete
    return if new_record?
    touch_paranoia_column(false)
  end

  def restore!(opts = {})
    ActiveRecord::Base.transaction do
      run_callbacks(:restore) do
        case paranoia_column_type
        when :datetime
          update_column paranoia_column, nil
        when :boolean
          update_column paranoia_column, false
        end
        restore_associated_records if opts[:recursive]
      end
    end
  end
  alias :restore :restore!

  def destroyed?
    !!send(paranoia_column)
  end
  alias :deleted? :destroyed?

  private

  # touch paranoia column.
  # insert time to paranoia column.
  # @param with_transaction [Boolean] exec with ActiveRecord Transactions.
  def touch_paranoia_column(with_transaction=false)
    case paranoia_column_type
    when :datetime
      if with_transaction
        with_transaction_returning_status { touch(paranoia_column) }
      else
        touch(paranoia_column)
      end
    when :boolean
      if with_transaction
        with_transaction_returning_status { update_column(paranoia_column, true) }
      else
        update_column(paranoia_column, true)
      end
    end
  end

  # restore associated records that have been soft deleted when
  # we called #destroy
  def restore_associated_records
    destroyed_associations = self.class.reflect_on_all_associations.select do |association|
      association.options[:dependent] == :destroy
    end

    destroyed_associations.each do |association|
      association = send(association.name)

      if association.paranoid?
        association.only_deleted.each { |record| record.restore(:recursive => true) }
      end
    end
  end
end

class ActiveRecord::Base
  def self.acts_as_paranoid(options={})
    alias :really_destroy! :destroy
    alias :destroy! :destroy
    alias :delete! :delete
    include Paranoia
    class_attribute :paranoia_column, :paranoia_column_type

    self.paranoia_column = options[:column] || :deleted_at
    self.paranoia_column_type = options[:column_type] || :datetime

    case paranoia_column_type
    when :datetime
      default_scope { where(paranoia_column => nil) }
    when :boolean
      default_scope { where(paranoia_column => false) }
    else
      raise ArgumentError, "invalid paranoia_column_type: #{paranoia_column_type.inspect}"
    end

    before_restore {
      self.class.notify_observers(:before_restore, self) if self.class.respond_to?(:notify_observers)
    }
    after_restore {
      self.class.notify_observers(:after_restore, self) if self.class.respond_to?(:notify_observers)
    }
  end

  # Please do not use this method in production.
  # Pretty please.
  def self.I_AM_THE_DESTROYER!
    # TODO: actually implement spelling error fixes
    puts %Q{
      Sharon: "There should be a method called I_AM_THE_DESTROYER!"
      Ryan:   "What should this method do?"
      Sharon: "It should fix all the spelling errors on the page!"
}
  end

  def self.paranoid? ; false ; end
  def paranoid? ; self.class.paranoid? ; end

  # Override the persisted method to allow for the paranoia gem.
  # If a paranoid record is selected, then we only want to check
  # if it's a new record, not if it is "destroyed".
  def persisted?
    paranoid? ? !new_record? : super
  end

  private

  def paranoia_column
    self.class.paranoia_column
  end

  def paranoia_column_type
    self.class.paranoia_column_type
  end
end
