isempty(x::Union{AbstractDict, AbstractArray, AbstractString, Tuple, NamedTuple}) = length(x) == 0
isempty(::Number) = false
isempty(::Nothing) = true
isempty(x) = false

getconvert(::Type{String}) = string
number(::Type{T}, x::T) where {T} = x
number(T, x::String) = Parsers.parse(T, x)
number(T, x) = convert(T, x)
getconvert(::Type{T}) where {T <: Number} = x -> number(T, x)
getconvert(T) = x -> convert(T, x)

const BUF = IOBuffer()
write(obj; kwargs...) = (write(BUF, obj; kwargs...); return String(take!(BUF)))

function write(io::IO, obj::Dict{K, V}; kwargs...) where {K, V}
    Base.write(io, '{')
    isempty(obj) && @goto done
    len = length(obj)
    i = 1
    for (k, v) in obj
        write(io, string(k); kwargs...)
        Base.write(io, ':')
        write(io, v; kwargs...) # recursive
        i < len && Base.write(io, ',')
        i += 1
    end
    @label done
    Base.write(io, '}')
    return
end

function write(io::IO, obj::Union{AbstractArray,Tuple,AbstractSet}; kwargs...)
    # always written as single array
    Base.write(io, '[')
    len = length(obj)
    i = 1
    for x in obj
        write(io, x; kwargs...) # recursive
        i < len && Base.write(io, ',')
        i += 1
    end
    Base.write(io, ']')
    return
end

write(io::IO, obj::Function; kwargs...) = (Base.write(io, obj.str); return)
write(io::IO, obj::Number; kwargs...) = (Base.write(io, string(obj)); return)
write(io::IO, obj::AbstractFloat; kwargs...) = (Base.print(io, isfinite(obj) ? obj : "null"); return)
write(io::IO, obj::Date; dateformat=Dates.ISODateFormat, kwargs...) = (Base.write(io, "\"$(Dates.format(obj, dateformat))\""); return)
write(io::IO, obj::DateTime; write_datetimeformat=nothing, dateformat=Dates.ISODateTimeFormat, kwargs...) = (Base.write(io, "\"$(Dates.format(obj, something(write_datetimeformat, dateformat)))\""); return)
write(io::IO, obj::Nothing; kwargs...) = (Base.write(io, "null"); return)
write(io::IO, obj::Missing; kwargs...) = (Base.write(io, "null"); return)
write(io::IO, obj::Bool; kwargs...) = (Base.write(io, obj ? "true" : "false"); return)
write(io::IO, obj::Union{Char, Symbol, Enum, Type}; kwargs...) = write(io, string(obj); kwargs...)
write(io::IO, p::Pair; kwargs...) = write(io, Dict(Symbol(p.first)=>p.second); kwargs...)

# N = # of fields
function generate_write_body(N, inds, names, omitempties, converts)
    # @show N, inds, names
    body = Expr(:block, :(kwargs = JSON2.mergedefaultkwargs(obj; kwargs...)))
    push!(body.args, :(Base.write(io, '{')))
    push!(body.args, :(j = 1))

    vals = ((Symbol("val_$i") for i = 1:N)...,)
    foreach(1:N) do i
        push!(body.args, quote
            nm = $(names[i])
            if isdefined(obj, $(inds[i]))
                $(vals[i]) = getfield(obj, $(inds[i]))
                if !($(omitempties[i])) || !JSON2.isempty($(vals[i]))
                    j == 1 || Base.write(io, ',')
                    JSON2.write(io, string(nm); kwargs...)
                    Base.write(io, ':')
                    JSON2.write(io, $(converts[i])($(vals[i])); kwargs...)
                    j += 1
                end
            else
                if !$(omitempties[i])
                    j == 1 || Base.write(io, ',')
                    JSON2.write(io, string(nm); kwargs...)
                    Base.write(io, ':')
                    JSON2.write(io, nothing; kwargs...)
                    j += 1
                end
            end
        end)
    end
    push!(body.args, :(Base.write(io, '}'); return))
    # @show body
    return body
end

@generated function write(io::IO, obj::T; kwargs...) where T
    N = fieldcount(T)
    inds = Tuple(1:N)
    names = Tuple(string(fieldname(T, i)) for i in inds)
    omitempties = Tuple(false for i in inds)
    converts = Tuple(getconvert(fieldtype(T, i)) for i in inds)
    ex = generate_write_body(N, inds, names, omitempties, converts)
    return ex
end
