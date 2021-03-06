require_relative '../units'
require_relative 'addition'
require_relative 'division'
require_relative 'subtraction'

class Units
    class Numeric < Numeric
	attr_reader :units, :value

	def initialize(value, units=nil)
	    raise ArgumentError, "Numeric can't be initialized with a #{value.class} : #{value}" unless value.is_a?(::Numeric)
	    @value = value
	    @units = (units.is_a?(Units) ? units : Units.new(units)) if units
	end

	# Handle conversion methods (to_*) and pass everything else to the wrapped value
	def method_missing(id, *args)
	    # Check this before valid_conversion? because valid_conversion? has low standards
	    if (id.to_s =~ /(.+)\?$/) and Units.valid_unit?($1)
		@units.is_a?($1)
	    elsif (@units and @units.valid_conversion?(id)) or Units.valid_unit?(id)
		units = Units.new(id)
		if @units
		    (@units == units) ? self : self.class.new(@units.convert(@value, id), units)
		else
		    self.class.new(value, units)
		end
	    elsif (id.to_s =~ /^per_(.+)$/) and Units.valid_unit?($1)
		units = @units ? @units.per({$1 => (args[0] || 1)}) : Units.new({$1 => -(args[0] || 1)})
		self.class.new(@value, units)
	    elsif (id.to_s =~ /^to_(.+)$/) and Units.valid_unit?($1)
		units = Units.new($1)
		return self if @units == units
		self.class.new(@units.convert(@value, $1), units)
	    else
		@value.send(id, *args)
	    end
	end

	def respond_to_missing?(name, include_private = false)
	    # Check this before valid_conversion? because valid_conversion? has low standards
	    if (name.to_s =~ /(.+)\?$/) and Units.valid_unit?($1)
		true
	    elsif @units and @units.valid_conversion?(name)
		true
	    elsif (name.to_s =~ /^to_(.+)$/) and Units.valid_unit?($1)
		true
	    else
		super
	    end
	end

	def inspect
	    if @units
		@value.inspect + ' ' + @units.inspect
	    else
		@value.inspect
	    end
	end
	def to_s
	    @value.to_s
	end

	# Convert other into something that can work with a {Numeric}
	def coerce(other)
	    case other
		when Fixnum then [self.class.new(other), self]
		when Float  then [self.class.new(other), self]
		else
		    other.class.send(:prepend, UnitsMixin) unless other.kind_of?(UnitsMixin)
		    [other, self]
	    end
	end

	# Both the values and the units must match for two numbers to be considered equal
	#  ie. 3.meters != 3.inches != 3
	# However, 0.units == 0 is a special case to avoid breaking any conditionals
	# that attempt to avoid dividing by zero
	def eql?(other)
	    if other.zero?
		@value.zero?
	    elsif other.respond_to?(:units)
		if other.respond_to? :value
		    @units.eql?(other.units) and @value.eql?(other.value)
		else
		    other == self
		end
	    else
		@units.nil? and @value.eql?(other)
	    end
	end

	def ==(other)
	    if other.zero?
		@value.zero?
	    elsif other.respond_to?(:units)
		if other.respond_to?(:value)
		    (@units == other.units) and (@value == other.value)
		else
		    other == self
		end
	    else
		@units.nil? and (@value == other)
	    end
	end

	def <=>(other)
	    if other.kind_of? Numeric
		if @units
		    if @units.eql?(other.units)
			@value <=> other.value
		    else
			# Try converting to a common unit
			self <=> other.to(@units)
		    end
		else
		    (@value <=> other.value)
		end
	    elsif other.respond_to? :map
		other.map {|a| self.send(:<=>, a)}
	    elsif Units::Operator
		-(other <=> @value)
	    else
		@value <=> other
	    end
	end

	# @note This method is defined here, instead of relying on method_missing,
	#  because the default implementation of Numeric#zero? passes the call
	#  to #==, which is rather heavy for what little needs to be done here.
	#  This is purely a matter of optimization; but it shaved quite a few cycles.
	def zero?
	    @value.zero?
	end

	# @group Arithmetic

	def -@
	    self.class.new(-value, units)
	end

	def +(other)
	    return other if self.zero?
	    return self if other.zero?

	    case other
		when Units::Addition	then Units.Addition(self) + other
		when Units::Operator	then Units.Addition(self) + other
		else op(:+, other)
	    end
	end

	def -(other)
	    return self if other.zero?

	    case other
		when Units::Addition	then Units.Subtraction(self) - other
		when Units::Operator	then Units.Subtraction(self) - other
		else op(:-, other)
	    end
	end

	def *(other)
	    return self if self.zero?
	    return other if (other.respond_to?(:zero?) ? other.zero? : (other == 0))

	    case other
		when Units::Operator	then other * self
		else op(:*, other)
	    end
	end

	def /(other)
	    case other
		when Units::Operator	then Units::Division.new(self, other)
		else op(:/, other)
	    end
	end

	def **(power)
	    self.class.new(@value ** power, @units ? (@units ** power) : nil)
	end
	# @endgroup

	# @group Conversion

	# Convert to the desired units
	# @param units [Units]	the desired units to convert to
	# @return [Numeric]
	def convert_to(units)
	    raise UnitsError, "Can't convert '#{@units}' to: #{units}" unless @units.valid_conversion?(units)
	    return self if @units == units
	    self.class.new(@units.convert(@value, units), units)
	end
	alias to convert_to

	# @endgroup

	private

	# Generic operator handler
	def op(sym, other)
	    if other.kind_of? Numeric
		begin
		    result_units = if @units
			@units.send(sym, other.units)
		    elsif (:/ == sym) && (0 == @value)
			nil
		    elsif other.units && ((:+ == sym) || (:- == sym))
			raise UnitsError
		    else
			other.units
		    end
		rescue UnitsError
		    case sym
			when :+ then Units::Addition.new(self, other)
			when :-
			    # If self is zero, then don't bother creating a Subtraction proxy
			    if value.zero?
				-other
			    else
				Units::Subtraction.new(self, other)
			    end
		    end
		else
		    self.class.new(@value.send(sym, other.value), result_units)
		end
	    elsif other.respond_to? :map
		other.map {|a| self.send(sym, a)}
	    else
		self.class.new(@value.send(sym, other), @units ? (@units.send(sym, other.units)) : other.units)
	    end
	rescue UnitsError
	    raise
	rescue ArgumentError    # Handle units that cancel out
	    @value.send(sym, other.value)
	rescue NoMethodError
	    self.class.new(@value.send(sym, other), @units)
	end
    end
end
