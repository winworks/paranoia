module Paranoia
  def self.included(klazz)
    klazz.extend Query
    klazz.extend Callbacks
  end

  module Query
    def paranoid? ; true ; end

    def with_deleted
      all.tap { |x| x.default_scoped = false }
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

    def restore(id)
      if id.is_a?(Array)
        id.map { |one_id| restore(one_id) }
      else
        only_deleted.find(id).restore!
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
    run_callbacks(:destroy) { delete_or_soft_delete(true) }
  end

  def delete
    return if new_record?
    delete_or_soft_delete
  end

  def restore!
    case paranoia_column_type
    when :datetime
      run_callbacks(:restore) { update_column paranoia_column, nil }
    when :boolean
      run_callbacks(:restore) { update_column paranoia_column, false }
    end
  end

  def destroyed?
    !!send(paranoia_column)
  end
  alias :deleted? :destroyed?

  private
  # select and exec delete or soft-delete.
  # @param with_transaction [Boolean] exec with ActiveRecord Transactions, when soft-delete.
  def delete_or_soft_delete(with_transaction=false)
    destroyed? ? destroy! : touch_paranoia_column(with_transaction)
  end

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
end

class ActiveRecord::Base
  def self.acts_as_paranoid(options={})
    alias :destroy! :destroy
    alias :delete!  :delete
    include Paranoia
    class_attribute :paranoia_column, :paranoia_column_type

    self.paranoia_column = options[:column] || :deleted_at
    self.paranoia_column_type = options[:column_type] || :datetime

    case paranoia_column_type
    when :datetime
      default_scope { where(self.quoted_table_name + ".#{paranoia_column} IS NULL") }
    when :boolean
      default_scope { where(paranoia_column => false) }
    else
      raise ArgumentError, "invalid paranoia_column_type: #{paranoia_column_type.inspect}"
    end
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
