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

read(str::AbstractString, T=Any; kwargs...) = read(IOBuffer(str), T; kwargs...)

# read generic JSON: detect null, Bool, Int, Float, String, Array, Dict/Object into a NamedTuple
function read(io::IO, ::Type{Any}=Any; kwargs...)
    eof(io) && return NamedTuple()
    wh!(io)
    b = peekbyte(io)
    if b == UInt('{')
        # object
        return read(io, NamedTuple; kwargs...)
    elseif b == UInt('[')
        # array
        # TODO: we could try and be fancy here and parse a more specific vector
        return read(io, Vector{Any}; kwargs...)
    elseif (NEG_ONE < b < TEN) || (b == MINUS || b == PLUS)
        # int or float
        fl = read(io, Float64; kwargs...)
        int = unsafe_trunc(Int, fl)
        return ifelse(int == fl, int, fl)
    elseif b == UInt8('"')
        # string)
        return read(io, String; kwargs...)
    elseif b == UInt8('n')
        # null
        return read(io, Nothing; kwargs...)
    elseif b == UInt8('t')
        # true
        return read(io, Bool; kwargs...)
    elseif b == UInt8('f')
        # false or function literal
        pos = position(io)
        readbyte(io)
        eof(io) && throw(ArgumentError("early EOF"))
        func = peekbyte(io) == UInt8('u')
        seek(io, pos)
        return func ? read(io, Function; kwargs...) : read(io, Bool; kwargs...)
    else
        throw(ArgumentError("error detecting type of JSON object to parse: invalid JSON detected"))
    end
end

nonNothingT(::Type{Union{Nothing, T}}) where {T} = T
function read(io::IO, U::Union; kwargs...)
    if U.a === Nothing || U.b === Nothing
        b = peekbyte(io)
        if b == LITTLE_N
            return read(io, Nothing; kwargs...)
        else
            return read(io, nonNothingT(U); kwargs...)
        end
    else
        pos = position(io)
        try
            return read(io, U.a; kwargs...)
        catch
            seek(io, pos)
            return read(io, U.b; kwargs...)
        end
    end
end

function read(io::IO, T::Type{NamedTuple}; kwargs...)
    @expect '{'
    wh!(io)
    keys = Symbol[]
    vals = Any[]
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    while true
        push!(keys, read(io, Symbol; kwargs...))
        wh!(io)
        @expect ':'
        wh!(io)
        push!(vals, read(io, Any; kwargs...)) # recursively reads value
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return NamedTuple{Tuple(keys)}(Tuple(vals))
end

function read(io::IO, ::Type{T}; kwargs...) where {T <: NamedTuple{names, types}} where {names, types}
    @expect '{'
    wh!(io)
    keys = Symbol[]
    vals = Any[]
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    typemap = Dict(k=>v for (k, v) in zip(names, types.parameters))
    while true
        key = read(io, Symbol; kwargs...)
        push!(keys, key)
        wh!(io)
        @expect ':'
        wh!(io)
        push!(vals, read(io, typemap[key]; kwargs...)) # recursively reads value
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return NamedTuple{names}(NamedTuple{Tuple(keys)}(Tuple(vals)))
end

read(io::IO, ::Type{T}; kwargs...) where {T <: AbstractDict} = read(io, T(); kwargs...)
function read(io::IO, dict::Dict{K,V}; kwargs...) where {K, V}
    T = typeof(dict)
    @expect '{'
    wh!(io)
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    while true
        key = read(io, K; kwargs...)
        wh!(io)
        @expect ':'
        wh!(io)
        dict[key] = read(io, V; kwargs...) # recursively reads one element
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return dict
end

read(io::IO, ::Type{T}; kwargs...) where {T <: Tuple} = Tuple(read(io, Array; kwargs...))
read(io::IO, ::Type{T}; kwargs...) where {T <: AbstractSet} = T(read(io, Array; kwargs...))
read(io::IO, ::Type{T}; kwargs...) where {T <: AbstractArray} = read(io, T([]); kwargs...)

function read(io::IO, A::AbstractArray{eT}; kwargs...) where {eT}
    T = typeof(A)
    @expect '['
    wh!(io)
    peekbyte(io) == CLOSE_SQUARE_BRACE && (readbyte(io); @goto done)
    while true
        push!(A, read(io, eT; kwargs...)) # recursively reads one element
        wh!(io)
        @expectoneof ',' ']'
        b == CLOSE_SQUARE_BRACE && @goto done
        wh!(io)
    end
    @label done
    return A
end

function read(io::IO, ::Type{Function}; kwargs...)
    buf = IOBuffer()
    wh!(io)
    while !eof(io)
        b = readbyte(io)
        Base.write(buf, b)
        b == UInt8('{') && break
    end
    bracketcount = 1
    while !eof(io) && bracketcount > 0
        b = readbyte(io)
        Base.write(buf, b)
        bracketcount += b == UInt8('{') ? 1 : b == UInt8('}') ? -1 : 0
    end
    return Function(String(take!(buf)))
end

# read Number, String, Bool
read(io::IO, ::Type{T}; kwargs...) where {T <: Integer} = Parsers.parse(T, io)
read(io::IO, ::Type{T}; kwargs...) where {T <: AbstractFloat} = Parsers.parse(T, io)

function read(io::IO, T::Type{Char}; kwargs...)
    @expect '"'
    c = Char(readbyte(io))
    @expect '"'
    return c
end
read(io::IO, ::Type{Date}; dateformat=Dates.ISODateFormat, kwargs...) = Date(read(io, String; kwargs...), dateformat)
function read(io::IO, ::Type{DateTime}; read_datetimeformats=[], dateformat=Dates.ISODateTimeFormat, kwargs...)
    dfs = [read_datetimeformats; dateformat]
    s = read(io, String; kwargs...)
    for df in dfs
        try
            return DateTime(s, df)
        catch ex
        end
    end
    error("Unable to parse datetime: $s")
end
read(io::IO, ::Type{T}; kwargs...) where {T <: Enum} = Core.eval(parentmodule(T), read(io, Symbol; kwargs...))

function read(io::IO, T::Type{Nothing}; kwargs...)
    @expect 'n' 'u' 'l' 'l'
    return nothing
end

function read(io::IO, T::Type{Missing}; kwargs...)
    @expect 'n' 'u' 'l' 'l'
    return missing
end

function read(io::IO, T::Type{Bool}; kwargs...)
    b = peekbyte(io)
    if b == UInt8('t')
        @expect 't' 'r' 'u' 'e'
        return true
    else
        @expect 'f' 'a' 'l' 's' 'e'
        return false
    end
end

function generate_default_read_body(N, types, jsontypes, isnamedtuple)
    inner = Expr(:block, :(kwargs = JSON2.mergedefaultkwargs(T; kwargs...)))
    keys = ((((Symbol("key_$j") for j = 1:i)...,) for i = 1:N)...,)
    vals = ((((Symbol("val_$j") for j = 1:i)...,) for i = 1:N)...,)
    foreach(1:N) do i
        if isnamedtuple
            ret = :(T(($((vals[i])...),)))
        else
            ret = :(T($((vals[i])...)))
        end
        push!(inner.args, quote
            $(keys[i][i]) = JSON2.read(io, String; kwargs...)
            JSON2.wh!(io)
            JSON2.@expect ':'
            JSON2.wh!(io)
            $(vals[i][i]) = $(JSON2.getconvert(types[i]))(JSON2.read(io, $(jsontypes[i]); kwargs...))
            JSON2.wh!(io)
            JSON2.@expectoneof ',' '}'
            b == JSON2.CLOSE_CURLY_BRACE && return $ret
            JSON2.wh!(io)
        end)
    end
    if isnamedtuple
        ret = :(T(($((vals[N])...),)))
    else
        ret = :(T($((vals[N])...)))
    end
    body = quote
        JSON2.@expect '{'
        JSON2.wh!(io)
        JSON2.peekbyte(io) == JSON2.CLOSE_CURLY_BRACE && (JSON2.readbyte(io); return T())
        $inner
        # in case there are extra fields, just ignore
        curlies = 1
        while !eof(io)
            b = JSON2.readbyte(io)
            if b == JSON2.OPEN_CURLY_BRACE
                curlies += 1
            elseif b == JSON2.CLOSE_CURLY_BRACE
                curlies -= 1
            end
            curlies == 0 && return $ret
        end
        throw(ArgumentError("failed to parse $T from JSON"))
    end
    # @show body
    return body
end

const EMPTY_SYMBOL = Symbol("")

function read_args(io, b, name, names, T, types, jT, jsontypes, defaults, fulltypes, fulljsontypes, args=(), argnm=EMPTY_SYMBOL, arg=nothing; kwargs...)
    # @show name, names, T, types, jT, jsontypes, defaults, args, argnm, arg
    # @show name == argnm
    # @show names
    # @show isempty(names)
    if argnm != EMPTY_SYMBOL
        if name == argnm
            if isempty(names)
                return ((args..., arg), b)
            else
                return JSON2.read_args(io, b,
                    names[1], Base.tail(names),
                    types[1], Base.tail(types),
                    jsontypes[1], Base.tail(jsontypes),
                    defaults, fulltypes, fulljsontypes,
                    (args..., arg), EMPTY_SYMBOL, nothing;
                    kwargs...)
            end
        else
            if isempty(names)
                return ((args..., defaults[name]), b)
            else
                return JSON2.read_args(io, b,
                    names[1], Base.tail(names),
                    types[1], Base.tail(types),
                    jsontypes[1], Base.tail(jsontypes),
                    defaults, fulltypes, fulljsontypes,
                    (args..., defaults[name]), argnm, arg;
                    kwargs...)
            end
        end
    end
    JSON2.wh!(io)
    if b == JSON2.CLOSE_CURLY_BRACE
        if isempty(names)
            return ((args..., defaults[name]), b)
        else
            return JSON2.read_args(io, b, names[1], Base.tail(names),
                                   types[1], Base.tail(types),
                                   jsontypes[1], Base.tail(jsontypes),
                                   defaults, fulltypes, fulljsontypes,
                                   (args..., defaults[name]), argnm, arg;
                                   kwargs...)
        end
    end
    key = JSON2.read(io, Symbol; kwargs...)
    JSON2.wh!(io)
    JSON2.@expect ':'
    JSON2.wh!(io)
    if key == name
        val = JSON2.getconvert(T)(JSON2.read(io, jT; kwargs...))
    else
        val = defaults[name]
        if haskey(fulltypes, key)
            argnm = key
            arg = JSON2.getconvert(fulltypes[key])(JSON2.read(io, fulljsontypes[key]; kwargs...))
        else
            # ignore unknown field
            JSON2.read(io, Any; kwargs...)
        end
    end
    JSON2.wh!(io)
    JSON2.@expectoneof ',' '}'
    if isempty(names)
        return ((args..., val), b)
    else
        return JSON2.read_args(io, b,
            names[1], Base.tail(names),
            types[1], Base.tail(types),
            jsontypes[1], Base.tail(jsontypes),
            defaults, fulltypes, fulljsontypes,
            (args..., val), argnm, arg;
            kwargs...)
    end
end

function generate_missing_read_body(names, types, jsontypes, defaults)
    fulltypes = NamedTuple{names}(types)
    fulljsontypes = NamedTuple{names}(jsontypes)
    body = quote
        kwargs = JSON2.mergedefaultkwargs(T; kwargs...)
        JSON2.@expect '{'
        JSON2.wh!(io)
        JSON2.peekbyte(io) == JSON2.CLOSE_CURLY_BRACE && (JSON2.readbyte(io); return T())
        args, b = JSON2.read_args(io, b,
            $(QuoteNode(names[1])), $(Base.tail(names)),
            $(types[1]), $(Base.tail(types)),
            $(jsontypes[1]), $(Base.tail(jsontypes)),
            $defaults, $fulltypes, $fulljsontypes; kwargs...)
        b == JSON2.CLOSE_CURLY_BRACE && return T(args...)
        # in case there are extra fields, just ignore
        curlies = 1
        while !eof(io)
            b = JSON2.readbyte(io)
            if b == JSON2.OPEN_CURLY_BRACE
                curlies += 1
            elseif b == JSON2.CLOSE_CURLY_BRACE
                curlies -= 1
            end
            curlies == 0 && return T(args...)
        end
        throw(ArgumentError("failed to parse $T from JSON"))
    end
    # @show body
    return body
end

function generate_read_body_noargs(N, names, jsontypes, defaults)
    body = quote
        kwargs = JSON2.mergedefaultkwargs(T; kwargs...)
        x = T()
        eof(io) && return x
        JSON2.@expect '{' # start of object
        JSON2.wh!(io)
        JSON2.peekbyte(io) == JSON2.CLOSE_CURLY_BRACE && (JSON2.readbyte(io); return x)
        names = $names
        defaults = $defaults
        allnames = Set($(names))
        seen = Set{Symbol}()
        jsontypes = $jsontypes
        while !eof(io)
            key = JSON2.read(io, Symbol; kwargs...)
            key = get(names, key, key)
            JSON2.wh!(io)
            JSON2.@expect ':'
            JSON2.wh!(io)
            val = JSON2.read(io, get(jsontypes, key, Any); kwargs...)
            key in allnames && Core.setfield!(x, key, val)
            push!(seen, key)
            JSON2.wh!(io)
            JSON2.@expectoneof ',' '}'
            b == JSON2.CLOSE_CURLY_BRACE && break
            JSON2.wh!(io)
        end
        for i = 1:$N
            key = fieldname(T, i)
            if !(key in seen) && haskey(defaults, key)
                Core.setfield!(x, key, defaults[key])
            end
        end
        b == JSON2.CLOSE_CURLY_BRACE && return x
        throw(ArgumentError("failed to parse $T from JSON"))
    end
    # @show body
    return body
end

@generated function read(io::IO, ::Type{T}; kwargs...) where T
    N = fieldcount(T)
    types = Tuple(fieldtype(T, i) for i = 1:N)
    return generate_default_read_body(N, types, types, T <: NamedTuple)
end
