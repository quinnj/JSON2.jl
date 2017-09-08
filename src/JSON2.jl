__precompile__(true)
module JSON2

# for reading/writing javascript functions as value literals
struct Function
    str::String
end

include("write.jl")
include("read.jl")
include("strings.jl")
include("pretty.jl")

## JSON2.@format
function getformats(nm; kwargs...)
    for (k, v) in kwargs
        k == nm && return v
    end
    return NamedTuple()
end

macro format(T, kw, expr)
    args = filter(x->x.head != :line, expr.args)
    foreach(x->x.args[2] = QuoteNode(x.args[2]), args)
    # @show args
    q = esc(quote
        @generated function JSON2.write(io::IO, obj::$T)
            fieldformats = [JSON2.getformats(nm; $(args...)) for nm in fieldnames($T)]
            # @show fieldformats
            inds = Tuple(i for i = 1:length(fieldformats) if !get(fieldformats[i], :exclude, false))
            names = Tuple(string(get(fieldformats[i], :name, fieldname($T, i))) for i in inds)
            omitempties = Tuple(get(fieldformats[i], :omitempty, false) for i in inds)
            converts = Tuple(JSON2.getconvert(get(fieldformats[i], :T, fieldtype($T, i))) for i in inds)
            N = length(inds)
            ex = JSON2.generate_write_body(N, inds, names, omitempties, converts)
            # @show ex
            return ex
        end
        @generated function JSON2.read(io::IO, T::Type{$T})
            fieldformats = [JSON2.getformats(nm; $(args...)) for nm in fieldnames($T)]
            inds = Tuple(i for i = 1:length(fieldformats) if !get(fieldformats[i], :exclude, false))
            names = Dict{String, String}(string(get(fieldformats[i], :name, Symbol(""))) for i in inds if isdefined(fieldformats[i], :name))
            N = length(inds)
            types = Tuple(Any for i in inds)
            return JSON2.generate_read_body(N, names, types, false, $(kw.args[2]))
        end
    end)
    # @show q
    return q
end

macro format(T, expr)
    if expr.head == :(=) && expr.args[1] == :keywordargs
        return esc(:(JSON2.@format($T, $expr, begin end)))
    else
        return esc(:(JSON2.@format($T, keywordargs=false, $expr)))
    end
end

end # module