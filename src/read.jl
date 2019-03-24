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

read(str::AbstractString, T=Any, opts::Opts=defaultopts(T), args...) = read(IOBuffer(str), T, opts, args...)

# read generic JSON: detect null, Bool, Int, Float, String, Array, Dict/Object into a NamedTuple
function read(io::IO, ::Type{Any}=Any, opts::Opts=Opts())
    eof(io) && return NamedTuple()
    wh!(io)
    b = peekbyte(io)
    if b == UInt('{')
        # object
        return read(io, NamedTuple, opts)
    elseif b == UInt('[')
        # array
        # TODO: we could try and be fancy here and parse a more specific vector
        return read(io, Vector{Any}, opts)
    elseif (NEG_ONE < b < TEN) || (b == MINUS || b == PLUS)
        # int or float
        fl = read(io, Float64, opts)
        int = unsafe_trunc(Int, fl)
        return ifelse(int == fl, int, fl)
    elseif b == UInt8('"')
        # string)
        return read(io, String, opts)
    elseif b == UInt8('n')
        # null
        return read(io, Nothing, opts)
    elseif b == UInt8('t')
        # true
        return read(io, Bool, opts)
    elseif b == UInt8('f')
        # false or function literal
        pos = position(io)
        readbyte(io)
        eof(io) && throw(ArgumentError("early EOF"))
        func = peekbyte(io) == UInt8('u')
        seek(io, pos)
        return func ? read(io, Function, opts) : read(io, Bool, opts)
    else
        throw(ArgumentError("error detecting type of JSON object to parse: invalid JSON detected"))
    end
end

nonNothingT(::Type{Union{Nothing, T}}) where {T} = T
function read(io::IO, U::Union, opts::Opts=Opts())
    if U.a === Nothing || U.b === Nothing
        b = peekbyte(io)
        if b == LITTLE_N
            return read(io, Nothing, opts)
        else
            return read(io, nonNothingT(U), opts)
        end
    else
        pos = position(io)
        try
            return read(io, U.a, opts)
        catch
            seek(io, pos)
            return read(io, U.b, opts)
        end
    end
end

function read(io::IO, T::Type{NamedTuple}, opts::Opts=Opts())
    @expect '{'
    wh!(io)
    keys = Symbol[]
    vals = Any[]
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    while true
        push!(keys, read(io, Symbol, opts))
        wh!(io)
        @expect ':'
        wh!(io)
        push!(vals, read(io, Any, opts)) # recursively reads value
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return NamedTuple{Tuple(keys)}(Tuple(vals))
end

function read(io::IO, ::Type{T}, opts::Opts=Opts()) where {T <: NamedTuple{names, types}} where {names, types}
    @expect '{'
    wh!(io)
    keys = Symbol[]
    vals = Any[]
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    typemap = Dict(k=>v for (k, v) in zip(names, types.parameters))
    while true
        key = read(io, Symbol, opts)
        push!(keys, key)
        wh!(io)
        @expect ':'
        wh!(io)
        push!(vals, read(io, typemap[key], opts)) # recursively reads value
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return NamedTuple{names}(NamedTuple{Tuple(keys)}(Tuple(vals)))
end

read(io::IO, ::Type{T}, opts::Opts=Opts()) where {T <: AbstractDict} = read(io, T(), opts)
function read(io::IO, dict::Dict{K,V}, opts::Opts=Opts()) where {K, V}
    T = typeof(dict)
    @expect '{'
    wh!(io)
    peekbyte(io) == CLOSE_CURLY_BRACE && (readbyte(io); @goto done)
    while true
        key = read(io, K, opts)
        wh!(io)
        @expect ':'
        wh!(io)
        dict[key] = read(io, V, opts) # recursively reads one element
        wh!(io)
        @expectoneof ',' '}'
        b == CLOSE_CURLY_BRACE && @goto done
        wh!(io)
    end
    @label done
    return dict
end

read(io::IO, ::Type{T}, opts::Opts=Opts()) where {T <: Tuple} = Tuple(read(io, Array, opts))
read(io::IO, ::Type{T}, opts::Opts=Opts()) where {T <: AbstractSet} = T(read(io, Array, opts))
read(io::IO, ::Type{T}, opts::Opts=Opts()) where {T <: AbstractArray} = read(io, T([]), opts)

function read(io::IO, A::AbstractArray{eT}, opts::Opts=Opts()) where {eT}
    T = typeof(A)
    @expect '['
    wh!(io)
    peekbyte(io) == CLOSE_SQUARE_BRACE && (readbyte(io); @goto done)
    while true
        push!(A, read(io, eT, opts)) # recursively reads one element
        wh!(io)
        @expectoneof ',' ']'
        b == CLOSE_SQUARE_BRACE && @goto done
        wh!(io)
    end
    @label done
    return A
end

function read(io::IO, ::Type{Function}, ::Opts=Opts())
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

# read Number, String, Nullable, Bool
read(io::IO, ::Type{T}, ::Opts=Opts()) where {T <: Integer} = Parsers.parse(io, T)
read(io::IO, ::Type{T}, ::Opts=Opts()) where {T <: AbstractFloat} = Parsers.parse(io, T)

function read(io::IO, T::Type{Char}, ::Opts=Opts())
    @expect '"'
    c = Char(readbyte(io))
    @expect '"'
    return c
end
read(io::IO, ::Type{Date}, opts::Opts=Opts()) = Date(read(io, String, opts), opts.date)
read(io::IO, ::Type{DateTime}, opts::Opts=Opts()) = DateTime(read(io, String, opts), opts.datetime)
read(io::IO, ::Type{T}, opts::Opts=Opts()) where {T <: Enum} = Core.eval(parentmodule(T), read(io, Symbol, opts))

function read(io::IO, T::Type{Nothing}, ::Opts=Opts())
    @expect 'n' 'u' 'l' 'l'
    return nothing
end

function read(io::IO, T::Type{Missing}, ::Opts=Opts())
    @expect 'n' 'u' 'l' 'l'
    return missing
end

function read(io::IO, T::Type{Bool}, ::Opts=Opts())
    b = peekbyte(io)
    if b == UInt8('t')
        @expect 't' 'r' 'u' 'e'
        return true
    else
        @expect 'f' 'a' 'l' 's' 'e'
        return false
    end
end

function generate_default_read_body(N, types, jsontypes, isnamedtuple, opts)
    inner = Expr(:block)
    keys = ((((Symbol("key_$j") for j = 1:i)...,) for i = 1:N)...,)
    vals = ((((Symbol("val_$j") for j = 1:i)...,) for i = 1:N)...,)
    foreach(1:N) do i
        if isnamedtuple
            ret = :(T(($((vals[i])...),)))
        else
            ret = :(T($((vals[i])...)))
        end
        push!(inner.args, quote
            $(keys[i][i]) = JSON2.read(io, String, opts)
            JSON2.wh!(io)
            JSON2.@expect ':'
            JSON2.wh!(io)
            $(vals[i][i]) = $(JSON2.getconvert(types[i]))(JSON2.read(io, $(jsontypes[i]), opts))
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

function read_args(io, b, name, names, T, types, jT, jsontypes, defaults, fulltypes, fulljsontypes, opts, args=(), argnm=EMPTY_SYMBOL, arg=nothing)
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
                    defaults, fulltypes, fulljsontypes, opts,
                    (args..., arg), EMPTY_SYMBOL, nothing)
            end
        else
            if isempty(names)
                return ((args..., defaults[name]), b)
            else
                return JSON2.read_args(io, b,
                    names[1], Base.tail(names),
                    types[1], Base.tail(types),
                    jsontypes[1], Base.tail(jsontypes),
                    defaults, fulltypes, fulljsontypes, opts,
                    (args..., defaults[name]), argnm, arg)
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
                                   defaults, fulltypes, fulljsontypes, opts,
                                   (args..., defaults[name]), argnm, arg)
        end
    end
    key = JSON2.read(io, Symbol, opts)
    JSON2.wh!(io)
    JSON2.@expect ':'
    JSON2.wh!(io)
    if key == name
        val = JSON2.getconvert(T)(JSON2.read(io, jT, opts))
    else
        val = defaults[name]
        if haskey(fulltypes, key)
            argnm = key
            arg = JSON2.getconvert(fulltypes[key])(JSON2.read(io, fulljsontypes[key], opts))
        else
            # ignore unknown field
            JSON2.read(io, Any, opts)
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
            defaults, fulltypes, fulljsontypes, opts,
            (args..., val), argnm, arg)
    end
end

function generate_missing_read_body(names, types, jsontypes, defaults, opts)
    fulltypes = NamedTuple{names}(types)
    fulljsontypes = NamedTuple{names}(jsontypes)
    body = quote
        JSON2.@expect '{'
        JSON2.wh!(io)
        JSON2.peekbyte(io) == JSON2.CLOSE_CURLY_BRACE && (JSON2.readbyte(io); return T())
        args, b = JSON2.read_args(io, b,
            $(QuoteNode(names[1])), $(Base.tail(names)),
            $(types[1]), $(Base.tail(types)),
            $(jsontypes[1]), $(Base.tail(jsontypes)),
            $defaults, $fulltypes, $fulljsontypes, $opts)
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

function generate_read_body_noargs(N, names, jsontypes, defaults, opts)
    body = quote
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
            key = JSON2.read(io, Symbol, opts)
            key = get(names, key, key)
            JSON2.wh!(io)
            JSON2.@expect ':'
            JSON2.wh!(io)
            val = JSON2.read(io, get(jsontypes, key, Any), opts)
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

@generated function read(io::IO, ::Type{T}, opts::Opts=defaultopts(T)) where {T}
    N = fieldcount(T)
    types = Tuple(fieldtype(T, i) for i = 1:N)
    return generate_default_read_body(N, types, types, T <: NamedTuple, opts)
end
