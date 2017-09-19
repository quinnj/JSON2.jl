readbyte(from::IO) = Base.read(from, UInt8)
peekbyte(from::IO) = Base.peek(from)

@inline function readbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    from.ptr = from.ptr + 1
    return byte
end

@inline function peekbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    return byte
end

macro expect(ch...)
    N = length(ch)
    uint8s = map(UInt8, ch)
    return esc(quote
        Base.@nexprs $N i->begin
            eof(io) && throw(ArgumentError("eof encountered before $T was able to be fully parsed"))
            b = JSON2.readbyte(io)
            b == $(uint8s)[i] || throw(JSON2.invalid(T, b))
        end
    end)
end

macro expectoneof(ch...)
    uint8s = map(UInt8, ch)
    return esc(quote
        if !eof(io)
            b = JSON2.readbyte(io)
            b in $uint8s || throw(ArgumentError("invalid JSON, encountered '$(Char(b))' expected one of: '$(join($ch, "' '"))'"))
        end
    end)
end

@inline iswh(b) = b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')

@inline function wh!(io)
    b = peekbyte(io)
    while iswh(b)
        readbyte(io)
        b = peekbyte(io)
    end
    return
end

invalid(T, b) = ArgumentError("invalid JSON detected parsing type '$T': encountered '$(Char(b))'")

read(str::String, T=Any, args...) = read(IOBuffer(str), T, args...)

function generate_read_body(N, names, types, isnamedtuple, keywordargs)
    body = quote
        JSON2.@expect '{' # start of object
        JSON2.wh!(io)
        JSON2.peekbyte(io) == JSON2.CLOSE_CURLY_BRACE && (JSON2.readbyte(io); return T())
        names = $names
    end
    keys = ((((Symbol("key_$j") for j = 1:i)...) for i = 1:N)...)
    vals = ((((Symbol("val_$j") for j = 1:i)...) for i = 1:N)...)
    foreach(1:N) do i
        if isnamedtuple
            ret = :(T(($((vals[i])...),)))
        elseif keywordargs
            ret = :(T(; $((:((Symbol($k), $v)) for (k, v) in zip(keys[i], vals[i]))...)))
        else
            ret = :(T($((vals[i])...)))
        end
        push!(body.args, quote
            $(keys[i][i]) = JSON2.read(io, String)
            $(keys[i][i]) = get(names, $(keys[i][i]), $(keys[i][i]))
            JSON2.wh!(io)
            JSON2.@expect ':'
            JSON2.wh!(io)
            $(vals[i][i]) = JSON2.read(io, $(types[i]))
            JSON2.wh!(io)
            JSON2.@expectoneof ',' '}'
            if b == JSON2.CLOSE_CURLY_BRACE
                return $ret
            end
            JSON2.wh!(io)
        end)
    end
    push!(body.args, :(throw(ArgumentError("failed to parse $T from JSON"))))
    # @show body
    return body
end

@generated function read(io::IO, ::Type{T}) where {T}
    N = fieldcount(T)
    types = Tuple((t = fieldtype(T, i); ifelse(t <: Nullable, t, Union{t, Void})) for i = 1:N)
    return generate_read_body(N, Dict{String, String}(), types, T <: NamedTuple, false)
end

# read generic JSON: detect null, Bool, Int, Float, String, Array, Dict/Object into a NamedTuple
function read(io::IO, ::Type{Any}=Any)
    eof(io) && return NamedTuple()
    wh!(io)
    b = peekbyte(io)
    if b == UInt('{')
        # object
        return read(io, NamedTuple)
    elseif b == UInt('[')
        # array
        return read(io, Vector{Any})
    elseif (NEG_ONE < b < TEN) || (b == MINUS || b == PLUS)
        # int or float
        fl = read(io, Float64)
        int = trunc(Int, fl)
        return ifelse(int == fl, int, fl)
    elseif b == UInt8('"')
        # string)
        return read(io, String)
    elseif b == UInt8('n')
        # null
        return read(io, Void)
    elseif b == UInt8('t')
        # true
        return read(io, Bool)
    elseif b == UInt8('f')
        # false or function literal
        pos = position(io)
        readbyte(io)
        eof(io) && throw(ArgumentError("early EOF"))
        func = peekbyte(io) == UInt8('u')
        seek(io, pos)
        return func ? read(io, Function) : read(io, Bool)
    else
        throw(ArgumentError("error detecting type of JSON object to parse: invalid JSON detected"))
    end
end

nonVoidT(::Type{Union{Void, T}}) where {T} = T
function read(io::IO, U::Union)
    if U.a === Void || U.b === Void
        b = peekbyte(io)
        if b == LITTLE_N
            return read(io, Void)
        else
            return read(io, nonVoidT(U))
        end
    else
        try
            return read(io, U.a)
        catch
            return read(io, U.b)
        end
    end
end

function read(io::IO, T::Type{NamedTuple})
    @expect '{'
    wh!(io)
    keys = Symbol[]
    vals = Any[]
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    while true
        push!(keys, read(io, Symbol))
        wh!(io)
        @expect ':'
        wh!(io)
        push!(vals, read(io, Any)) # recursively reads value
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return Base.namedtuple(NamedTuple{tuple(keys...)}, vals...)
end

read(io::IO, ::Type{T}) where {T <: Associative} = read(io, T())
function read(io::IO, dict::Dict{K,V}) where {K, V}
    T = typeof(dict)
    @expect '{'
    wh!(io)
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    while true
        key = read(io, K)
        wh!(io)
        @expect ':'
        wh!(io)
        dict[key] = read(io, V) # recursively reads one element
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return dict
end

read(io::IO, ::Type{T}) where {T <: Tuple} = tuple(read(io, Array)...)
read(io::IO, ::Type{T}) where {T <: AbstractSet} = T(read(io, Array))
read(io::IO, ::Type{T}) where {T <: AbstractArray} = read(io, T([]))

function read(io::IO, A::AbstractArray{eT}) where {eT}
    T = typeof(A)
    @expect '['
    wh!(io)
    peekbyte(io) == CLOSE_SQUARE_BRACE && (readbyte(io); @goto done)
    while true
        push!(A, read(io, eT)) # recursively reads one element
        wh!(io)
        @expectoneof ',' ']'
        b == CLOSE_SQUARE_BRACE && @goto done
        wh!(io)
    end
    @label done
    return A
end

function read(io::IO, ::Type{Function})
    str = readuntil(io, '}')
    return Function(str)
end

# read Number, String, Nullable, Bool
function read(io::IO, ::Type{T}) where {T <: Integer}
    eof(io) && throw(ArgumentError("early EOF"))
    v = zero(T)
    b = peekbyte(io)
    parseddigits = false
    negative = false
    if b == MINUS # check for leading '-' or '+'
        negative = true
        readbyte(io)
        b = peekbyte(io)
    elseif b == PLUS
        readbyte(io)
        b = peekbyte(io)
    end
    while NEG_ONE < b < TEN
        parseddigits = true
        b = readbyte(io)
        v, ov_mul = Base.mul_with_overflow(v, T(10))
        v, ov_add = Base.add_with_overflow(v, T(b - ZERO))
        (ov_mul | ov_add) && throw(OverflowError("overflow parsing $T, parsed $v"))
        eof(io) && break
        b = peekbyte(io)
    end
    !parseddigits && throw(invalid(T, b))
    return ifelse(negative, -v, v)
end

include("floatparsing.jl")

function read(io::IO, T::Type{Char})
    @expect '"'
    c = Char(readbyte(io))
    @expect '"'
    return c
end
read(io::IO, ::Type{Date}, format=Dates.ISODateFormat) = Date(read(io, String), format)
read(io::IO, ::Type{DateTime}, format=Dates.ISODateFormat) = DateTime(read(io, String), format)

read(io::IO, ::Type{Nullable}) = (v = read(io, Any); return ifelse(v == nothing, Nullable(), Nullable(v)))
function read(io::IO, ::Type{Nullable{T}}) where {T}
    b = peekbyte(io)
    if b == UInt8('n')
        @expect 'n' 'u' 'l' 'l'
        return Nullable{T}()
    else
        return Nullable(read(io, T))
    end
end
function read(io::IO, T::Type{Void})
    @expect 'n' 'u' 'l' 'l'
    return nothing
end

function read(io::IO, T::Type{Bool})
    b = peekbyte(io)
    if b == UInt8('t')
        @expect 't' 'r' 'u' 'e'
        return true
    else
        @expect 'f' 'a' 'l' 's' 'e'
        return false
    end
end

