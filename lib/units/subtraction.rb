require_relative 'operator'
require_relative 'division'

class Units
    class Subtraction < Operator
	def -(other)
	    return self.dup if other.zero?
	    return 0 if self == other

	    case other
		when Units::Addition	then self.class.new(*reduce(:-, *operands, *other.operands))
		when Units::Subtraction then self.class.new(*operands, other)
		else self.class.new(*operands, other)
	    end
	end

	def /(other)
	    case other
		when Units::Subtraction then Units::Division.new(self, other)
		else super
	    end
	end

	# Handle conversion methods (to_*) and pass everything else to the wrapped value
	def method_missing(id, *args)
	    if Units.valid_unit?(id) or ((id.to_s =~ /^to_(.+)$/) and Units.valid_unit?($1))
		operands.map {|operand| operand.respond_to?(id) ? operand.send(id) : operand }.reduce(:-)
	    else
		super
	    end
	end

	def to_s
	    super ' - '
	end

	# @group Math
	def sqrt
	    Units::SquareRoot.new(self)
	end
	# @endgroup
    end

    def self.Subtraction(*args)
	Units::Subtraction.new(*args)
    end
end