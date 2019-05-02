const BACKSPACE          = UInt8('\b')
const TAB                = UInt8('\t')
const NEWLINE            = UInt8('\n')
const FORM               = UInt8('\f')
const RETURN             = UInt8('\r')
const SPACE              = UInt8(' ')
const QUOTE              = UInt8('"')
const PLUS               = UInt8('+')
const COMMA              = UInt8(',')
const MINUS              = UInt8('-')
const PERIOD             = UInt8('.')
const FORWARDSLASH       = UInt8('/')
const BACKSLASH          = UInt8('\\')
const ZERO               = UInt8('0')
const NEG_ONE            = UInt8('0') - 0x01
const TEN                = UInt8('9') + 0x01
const BIG_A              = UInt8('A')
const BIG_E              = UInt8('E')
const BIG_F              = UInt8('F')
const BIG_I              = UInt8('I')
const BIG_N              = UInt8('N')
const BIG_T              = UInt8('T')
const BIG_Y              = UInt8('Y')
const LITTLE_A           = UInt8('a')
const LITTLE_B           = UInt8('b')
const LITTLE_E           = UInt8('e')
const LITTLE_F           = UInt8('f')
const LITTLE_I           = UInt8('i')
const LITTLE_L           = UInt8('l')
const LITTLE_N           = UInt8('n')
const LITTLE_R           = UInt8('r')
const LITTLE_S           = UInt8('s')
const LITTLE_T           = UInt8('t')
const LITTLE_U           = UInt8('u')
const LITTLE_Y           = UInt8('y')
const OPEN_CURLY_BRACE   = UInt8('{')
const CLOSE_CURLY_BRACE  = UInt8('}')
const COLON              = UInt8(':')
const OPEN_SQUARE_BRACE  = UInt8('[')
const CLOSE_SQUARE_BRACE = UInt8(']')

function escapechar(b)
    b == QUOTE     && return QUOTE
    b == BACKSLASH && return BACKSLASH
    b == BACKSPACE && return LITTLE_B
    b == FORM      && return LITTLE_F
    b == NEWLINE   && return LITTLE_N
    b == RETURN    && return LITTLE_R
    b == TAB       && return LITTLE_T
    return 0x00
end

function reverseescapechar(b)
    b == QUOTE     && return QUOTE
    b == BACKSLASH && return BACKSLASH
    b == LITTLE_B  && return BACKSPACE
    b == LITTLE_F  && return FORM
    b == LITTLE_N  && return NEWLINE
    b == LITTLE_R  && return RETURN
    b == LITTLE_T  && return TAB
    return 0x00
end

charvalue(b) = (NEG_ONE < b < TEN)         ? b - ZERO            :
               (LITTLE_A <= b <= LITTLE_F) ? b - (LITTLE_A - 0x0a) :
               (BIG_A <= b <= BIG_F)       ? b - (BIG_A - 0x0a)    :
               throw(ArgumentError("JSON invalid unicode hex value"))

iscntrl(c::Char) = c <= '\x1f' || '\x7f' <= c <= '\u9f'
function escaped(b)
    if b == FORWARDSLASH
        return [FORWARDSLASH]
    elseif b >= 0x80
        return [b]
    elseif b in map(UInt8, ('"', '\\', '\b', '\f', '\n', '\r', '\t'))
        return [BACKSLASH, escapechar(b)]
    elseif iscntrl(Char(b))
        return UInt8[BACKSLASH, LITTLE_U, string(b, base=16, pad=4)...]
    else
        return [b]
    end
end

const ESCAPECHARS = [escaped(b) for b = 0x00:0xff]
const NEEDESCAPE = [length(x) > 1 for x in ESCAPECHARS]

function needescape(str)
    bytes = codeunits(str)
    @simd for i = 1:length(bytes)
        @inbounds NEEDESCAPE[bytes[i] + 0x01] && return true
    end
    return false
end

function write(io::IO, obj::AbstractString; kwargs...)
    Base.write(io, '"')
    if needescape(obj)
        bytes = codeunits(obj)
        for i = 1:length(bytes)
            @inbounds b = ESCAPECHARS[bytes[i] + 0x01]
            Base.write(io, b)
        end
    else
        Base.write(io, obj)
    end
    Base.write(io, '"')
    return
end

# read
const BACKSLASH = UInt8('\\')

@noinline invalid_escape(str) = throw(ArgumentError("encountered invalid escape character in json string: \"$str\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(Char(b))'"))

function unescape(s)
    n = ncodeunits(s)
    buf = Base.StringVector(n)
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = codeunit(s, i)
            if b == BACKSLASH
                i += 1
                i > n && invalid_escape(s)
                b = codeunit(s, i)
                if b == LITTLE_U
                    c = 0x0000
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    st = codeunits(string(Char(c)))
                    for j = 1:length(st)-1
                        @inbounds buf[len] = st[j]
                        len += 1
                    end
                    b = st[end]
                else
                    b = reverseescapechar(b)
                    b == 0x00 && invalid_escape(s)
                end
            elseif b < SPACE
                unescaped_control(b)
            end
            @inbounds buf[len] = b
            len += 1
            i += 1
        end
    end
    resize!(buf, len - 1)
    return String(buf)
end

function read(io::IO, T::Type{String}; kwargs...)
    @expect '"'
    b = readbyte(io)
    hasescapechars = false
    while b != UInt8('"')
        Base.write(BUF, b)
        if b == UInt8('\\')
            eof(io) && throw(ArgumentError("early EOF"))
            hasescapechars = true
            b = readbyte(io)
            Base.write(BUF, b)
        end
        eof(io) && throw(ArgumentError("early EOF"))
        b = readbyte(io)
    end
    str = String(take!(BUF))
    return hasescapechars ? unescape(str) : str
end

function read(io::IOBuffer, T::Type{String}; kwargs...)
    @expect '"'
    ptr = pointer(io.data, io.ptr)
    b = readbyte(io)
    len = 0
    hasescapechars = false
    while b != QUOTE
        len += 1
        if b == BACKSLASH
            eof(io) && throw(ArgumentError("early EOF"))
            hasescapechars = true
            b = readbyte(io)
            len += 1
        end
        eof(io) && throw(ArgumentError("early EOF"))
        b = readbyte(io)
    end
    str = unsafe_string(ptr, len)
    return hasescapechars ? unescape(str) : str
end

function read(io::IOBuffer, T::Type{Symbol}; kwargs...)
    @expect '"'
    ptr = pointer(io.data, io.ptr)
    b = readbyte(io)
    len = 0
    hasescapechars = false
    while b != QUOTE
        len += 1
        if b == BACKSLASH
            eof(io) && throw(ArgumentError("early EOF"))
            hasescapechars = true
            b = readbyte(io)
            len += 1
        end
        eof(io) && throw(ArgumentError("early EOF"))
        b = readbyte(io)
    end
    sym = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), ptr, len)
    return hasescapechars ? Symbol(unescape(unsafe_string(ptr, len))) : sym
end
# slow path
read(io::IO, ::Type{Symbol}; kwargs...) = Symbol(read(io, String; kwargs...))
