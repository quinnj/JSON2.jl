module JSON2

using Dates, Parsers

import Parsers: readbyte, peekbyte

function __init__()
    Threads.resize_nthreads!(STRINGESCAPEBUFFERS)
end

const STRINGESCAPEBUFFERS = [Parsers.StringBuffer()]

function getescapebuffer(str)
    io = STRINGESCAPEBUFFERS[Threads.threadid()]
    io.data = str
    io.ptr = 1
    io.size = sizeof(str)
    return io
end

# for reading/writing javascript functions as value literals
struct Function
    str::String
end

include("write.jl")
include("read.jl")
include("strings.jl")
include("pretty.jl")

defaultkwargs(x::T) where T = defaultkwargs(T)
defaultkwargs(x::Type) = Dict{Symbol, Any}()
defaultkwargs(x::Type{Date}) = Dict{Symbol, Any}(:dateformat => ISODateFormat)
defaultkwargs(x::Type{DateTime}) = Dict{Symbol, Any}(:datetimeformat => ISODateTimeFormat)
mergedefaultkwargs(x; kwargs...) = merge!(defaultkwargs(x), Dict(pairs(kwargs)))

## JSON2.@format
function getformats(nm; kwargs...)
    for (k, v) in pairs(kwargs)
        k == nm && return v
    end
    return NamedTuple()
end

macro format(T, expr)
    if occursin("keywordargs", string(expr)) || occursin("noargs", string(expr))
        esc(:(JSON2.@format($T, $expr, $(Expr(:block)))))
    else
        esc(:(JSON2.@format($T, "", $expr)))
    end
end

"""
    JSON2.@format T [noargs|keywordargs] begin
        _field_ => (; options...)
        _field2_ => (; options...)
    end

Specify a custom JSON formatting for a struct `T`. Options include:
    `name`:
    `jsontype`:
    `omitempty`:
    `exclude`:
    `default`:

By default, the JSON input is expected to contain each field of a type and be in the same order as the type was defined. For example, the struct:
```julia
struct T
    a::Int
    b::Int
    c::Union{Nothing, Int}
end
```
Would have JSON like:
```
{"a": 0, "b": 1, "c": null}
{"a": 0, "b": 1, "c": 2}
{"a": 0, "b": 1, "c": null, "d": 3} // extra fields are ignored
{"a": 0} // will work if T(a) constructor is defined
{"a": 0, "b": 1} // will work if T(a, b) constructor is defined
```
That is, each field _must_ be present in the JSON input and match in position to the original struct definition. Extra arguments after the struct's own fieldtypes are ignored.

Again, the default case is for JSON input that will have consistently ordered, always-present fields; for cases where the input JSON is _not_ well-ordered or if there is a possibility of a `null`, non-`Union{T, Nothing}` field, here's how to approach more advanced custom formatting:
    - If the input will always be consistenly-ordered, but fields may be missing (not `null`, but the field key isn't even available in the input), defaults can be provided like:
    ```
    JSON2.@format T begin
        c => (default=0,)
    end
    ```
    This says that, when reading from a JSON input, if field `c` isn't present, to set it's value to 0.

    - If the JSON input is not consistenly-ordered, there are two other options for allowing direct type parsing:

      ```
      T(; a=0, b=0, c=0, kwargs...) = T(a, b, c)
      JSON2.@format T keywordargs begin
        ...
      end
      ```
      Here we've defined a "keywordargs" constructor for `T` that essentially takes a default for each field as keyword arguments, then constructs `T`.
      During parsing, the JSON input will be parsed for any valid field key-values and the keyword constructor will be called
      with whatever arguments are parsed in whatever order. Note that we also included a catchall `kwargs...` in our constructor which can be used to "throw away" or ignore any extra fields in the JSON input.

      ```
      mutable struct T
          a::Int
          b::Int
          c::Union{Nothing, Int}
      end
      T() = T(0, 0, 0)
      JSON2.@format T noargs begin
        ...
      end
      ```
      In this case, we've made `T` a _mutable_ struct and defined a "noargs" constructor `T() = ...`; we then specified in `JSON2.@format T noargs` the `noargs` option.
      During parsing, an instance of `T` will first constructed using the "noargs" constructor, then fields will be set as they're parsed from the JSON input (hence why `mutable struct` is required).

"""
macro format(T, typetype, exprs...)
    kwend, expr = if exprs[end].head === :(=)
        length(exprs), Expr(:block)
    else
        length(exprs) - 1, exprs[end]
    end
    kwargs = map(exprs[1:kwend]) do ex
        k = QuoteNode(ex.args[1])
        v = ex.args[2]
        :($k => $v)
    end
    kw = if !isempty(kwargs)
        :(JSON2.defaultkwargs(::Type{$T}) = Dict{Symbol, Any}($(kwargs...)))
    end

    args = filter(x->typeof(x) != LineNumberNode, expr.args)
    foreach(x->x.args[2] = QuoteNode(x.args[2]), args)
    anydefaults = any(z->:default in z, map(x->map(y->y.args[1], x.args[3].args), args))
    wr = quote
        @generated function JSON2.write(io::IO, obj::$T; kwargs...)
            fieldformats = [JSON2.getformats(nm; $(args...)) for nm in fieldnames($T)]
            # @show fieldformats
            inds = Tuple(i for i = 1:length(fieldformats) if !get(fieldformats[i], :exclude, false))
            names = Tuple(string(get(fieldformats[i], :name, fieldname($T, i))) for i in inds)
            omitempties = Tuple(get(fieldformats[i], :omitempty, false) for i in inds)
            converts = Tuple(JSON2.getconvert(get(fieldformats[i], :jsontype, fieldtype($T, i))) for i in inds)
            N = length(inds)
            ex = JSON2.generate_write_body(N, inds, names, omitempties, converts)
            # @show ex
            return ex
        end
    end
    if occursin("noargs", string(typetype))
        q = quote
            @generated function JSON2.read(io::IO, T::Type{$T}; kwargs...)
                N = fieldcount($T)
                fieldformats = Dict($(args...))
                names = (; ((Symbol(get(get(fieldformats, nm, NamedTuple()), :name, nm)), nm) for nm in fieldnames($T) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false))...)
                jsontypes = (; ((get(get(fieldformats, nm, NamedTuple()), :name, nm), get(get(fieldformats, nm, NamedTuple()), :jsontype, fieldtype($T, i))) for (i, nm) in enumerate(fieldnames($T)) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false))...)
                defaults = (; ((get(get(fieldformats, nm, NamedTuple()), :name, nm), get(fieldformats, nm, NamedTuple())[:default]) for nm in fieldnames($T) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false) && haskey(get(fieldformats, nm, NamedTuple()), :default))...)
                return JSON2.generate_read_body_noargs(N, names, jsontypes, defaults)
            end
        end
    elseif occursin("keywordargs", string(typetype))
        q = quote
            @generated function JSON2.read(io::IO, T::Type{$T}; kwargs...)
                N = fieldcount($T)
                fieldformats = Dict($(args...))
                names = (; ((Symbol(get(get(fieldformats, nm, NamedTuple()), :name, nm)), nm) for nm in fieldnames($T) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false) && haskey(get(fieldformats, nm, NamedTuple()), :name))...)
                types = (; ((get(get(fieldformats, nm, NamedTuple()), :name, nm), get(get(fieldformats, nm, NamedTuple()), :jsontype, fieldtype($T, i))) for (i, nm) in enumerate(fieldnames($T)) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false))...)
                defaults = (; ((get(get(fieldformats, nm, NamedTuple()), :name, nm), get(fieldformats, nm, NamedTuple())[:default]) for nm in fieldnames($T) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false) && haskey(get(fieldformats, nm, NamedTuple()), :default))...)
                q = quote
                    JSON2.@expect '{'
                    JSON2.wh!(io)
                    keys = Symbol[]
                    vals = Any[]
                    JSON2.peekbyte(io) == JSON2.CLOSE_CURLY_BRACE && (JSON2.readbyte(io); @goto done)
                    typemap = $types
                    while true
                        key = JSON2.read(io, Symbol)
                        push!(keys, key)
                        JSON2.wh!(io)
                        JSON2.@expect ':'
                        JSON2.wh!(io)
                        push!(vals, JSON2.read(io, get(typemap, key, Any))) # recursively reads value
                        JSON2.wh!(io)
                        JSON2.@expectoneof ',' '}'
                        b == JSON2.CLOSE_CURLY_BRACE && @goto done
                        JSON2.wh!(io)
                    end
                    @label done
                    return T(; $defaults..., NamedTuple{Tuple(keys)}(Tuple(vals))...)
                end
                # @show q
                return q
            end
        end
    elseif anydefaults
        q = quote
            @generated function JSON2.read(io::IO, T::Type{$T}; kwargs...)
                N = fieldcount($T)
                fieldformats = Dict($(args...))
                names = Tuple(Symbol(get(get(fieldformats, nm, NamedTuple()), :name, nm)) for nm in fieldnames($T) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false))
                types = Tuple(fieldtype($T, i) for i = 1:fieldcount($T) if !get(get(fieldformats, fieldname($T, i), NamedTuple()), :exclude, false))
                jsontypes = Tuple(get(get(fieldformats, fieldname($T, i), NamedTuple()), :jsontype, fieldtype($T, i)) for i = 1:fieldcount($T) if !get(get(fieldformats, fieldname($T, i), NamedTuple()), :exclude, false))
                defaults = (; ((get(get(fieldformats, nm, NamedTuple()), :name, nm), get(fieldformats, nm, NamedTuple())[:default]) for nm in fieldnames($T) if !get(get(fieldformats, nm, NamedTuple()), :exclude, false) && haskey(get(fieldformats, nm, NamedTuple()), :default))...)
                return JSON2.generate_missing_read_body(names, types, jsontypes, defaults)
            end
        end
        # @show q
    else
        q = quote
            @generated function JSON2.read(io::IO, T::Type{$T}; kwargs...)
                fieldformats = Dict($(args...))
                types = Tuple(fieldtype($T, i) for i = 1:fieldcount($T) if !get(get(fieldformats, fieldname($T, i), NamedTuple()), :exclude, false))
                jsontypes = Tuple(get(get(fieldformats, fieldname($T, i), NamedTuple()), :jsontype, fieldtype($T, i)) for i = 1:fieldcount($T) if !get(get(fieldformats, fieldname($T, i), NamedTuple()), :exclude, false))
                N = length(types)
                return JSON2.generate_default_read_body(N, types, jsontypes, $T <: NamedTuple)
            end
        end
    end

    push!(q.args, wr, kw)
    # @show q
    return esc(q)
end

end # module
