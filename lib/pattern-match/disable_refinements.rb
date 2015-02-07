class Module
  methods = Module.instance_methods(false) + Module.private_instance_methods(false)
  if methods.include?(:refine)
    if methods.include?(:__refine_orig)
      raise LoadError, "can't re-define Module#refine"
    end
    alias_method :__refine_orig, :refine
    remove_method :refine
  end

  def refine(klass, &blk)
    klass.class_eval(&blk)
  end

  begin
    require 'pattern-match'
  ensure
    remove_method :refine

    if Kernel.respond_to?(:__refine_orig, true)
      alias_method :refine, :__refine_orig
      remove_method :__refine_orig
    end
  end
end
