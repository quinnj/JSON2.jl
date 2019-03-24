export @pretty

macro pretty(json, opts=:(JSON2.Opts()))
    return esc(:(JSON2.pretty($json, $opts)))
end

pretty(str, opts::Opts=Opts()) = pretty(stdout, str, opts)
function pretty(out::IO, str::String, opts::Opts=Opts(), indent=0, offset=0)
    io = IOBuffer(str)
    eof(io) && return
    JSON2.wh!(io)
    b = JSON2.readbyte(io)
    # printing object?
    if b == UInt8('{')
        peekbyte(io) == CLOSE_CURLY_BRACE && (Base.write(out, "{}"); return)
        indent += 1
        Base.write(out, b)
        Base.write(out, '\n')
        keys = []
        vals = []
        # loop thru all key-value pairs, keeping track of longest key to pad others
        while b != UInt8('}')
            JSON2.wh!(io)
            push!(keys, JSON2.read(io, String, opts))
            JSON2.wh!(io)
            JSON2.readbyte(io) # ':'
            JSON2.wh!(io)
            push!(vals, JSON2.read(io, Any, opts))
            b = JSON2.readbyte(io)
        end
        maxlen = maximum(map(length, keys)) + 5
        # @show maxlen
        for i = 1:length(keys)
            Base.write(out, "  "^indent)
            Base.write(out, lpad("\"$(keys[i])\"" * ": ", maxlen + offset, ' '))
            pretty(out, JSON2.write(vals[i], opts), opts, indent, maxlen + offset)
            if i == length(keys)
                indent -= 1
                Base.write(out, "\n" * ("  "^indent * " "^offset) * "}")
            else
                Base.write(out, ",\n")
            end
        end

    # printing array?
    elseif b == UInt8('[')
        peekbyte(io) == CLOSE_SQUARE_BRACE && (Base.write(out, "[]"); return)
        indent += 1
        Base.write(out, b)
        Base.write(out, '\n')
        JSON2.wh!(io)
        vals = []
        while b != UInt8(']')
            JSON2.wh!(io)
            push!(vals, JSON2.read(io, Any, opts))
            JSON2.wh!(io)
            b = JSON2.readbyte(io)
        end
        for (i, val) in enumerate(vals)
            Base.write(out, "  "^indent * " "^offset)
            pretty(out, JSON2.write(vals[i], opts), opts, indent, offset)
            if i == length(vals)
                indent -= 1
                Base.write(out, "\n" * ("  "^indent * " "^offset) * "]")
            else
                Base.write(out, ",\n")
            end
        end

    # printing constant?
    else
        Base.write(out, str)
    end
    return
end
