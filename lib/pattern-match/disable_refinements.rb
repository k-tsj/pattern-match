class Module
  refine_orig = "__refine_orig_#{Time.now.to_i}".to_sym

  methods = instance_methods(false) + private_instance_methods(false)
  if methods.include?(:refine)
    if methods.include?(refine_orig)
      raise LoadError, "can't re-define Module#refine"
    end
    alias_method refine_orig, :refine
    remove_method :refine
  end

  def refine(klass, &blk)
    klass.class_eval(&blk)
  end

  begin
    require 'pattern-match'
  ensure
    remove_method :refine

    if Kernel.respond_to?(refine_orig, true)
      alias_method :refine, refine_orig
      remove_method refine_orig
    end
  end
end
