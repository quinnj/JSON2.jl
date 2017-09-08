const EXPONENTS = [
    1e0,   1e1,   1e2,   1e3,   1e4,   1e5,   1e6,   1e7,   1e8,    1e9,
    1e10,  1e11,  1e12,  1e13,  1e14,  1e15,  1e16,  1e17,  1e18,  1e19,
    1e20,  1e21,  1e22,  1e23,  1e24,  1e25,  1e26,  1e27,  1e28,  1e29,
    1e30,  1e31,  1e32,  1e33,  1e34,  1e35,  1e36,  1e37,  1e38,  1e39,
    1e40,  1e41,  1e42,  1e43,  1e44,  1e45,  1e46,  1e47,  1e48,  1e49,
    1e50,  1e51,  1e52,  1e53,  1e54,  1e55,  1e56,  1e57,  1e58,  1e59,
    1e60,  1e61,  1e62,  1e63,  1e64,  1e65,  1e66,  1e67,  1e68,  1e69,
    1e70,  1e71,  1e72,  1e73,  1e74,  1e75,  1e76,  1e77,  1e78,  1e79,
    1e80,  1e81,  1e82,  1e83,  1e84,  1e85,  1e86,  1e87,  1e88,  1e89,
    1e90,  1e91,  1e92,  1e93,  1e94,  1e95,  1e96,  1e97,  1e98,  1e99,
    1e100, 1e101, 1e102, 1e103, 1e104, 1e105, 1e106, 1e107, 1e108, 1e109,
    1e110, 1e111, 1e112, 1e113, 1e114, 1e115, 1e116, 1e117, 1e118, 1e119,
    1e120, 1e121, 1e122, 1e123, 1e124, 1e125, 1e126, 1e127, 1e128, 1e129,
    1e130, 1e131, 1e132, 1e133, 1e134, 1e135, 1e136, 1e137, 1e138, 1e139,
    1e140, 1e141, 1e142, 1e143, 1e144, 1e145, 1e146, 1e147, 1e148, 1e149,
    1e150, 1e151, 1e152, 1e153, 1e154, 1e155, 1e156, 1e157, 1e158, 1e159,
    1e160, 1e161, 1e162, 1e163, 1e164, 1e165, 1e166, 1e167, 1e168, 1e169,
    1e170, 1e171, 1e172, 1e173, 1e174, 1e175, 1e176, 1e177, 1e178, 1e179,
    1e180, 1e181, 1e182, 1e183, 1e184, 1e185, 1e186, 1e187, 1e188, 1e189,
    1e190, 1e191, 1e192, 1e193, 1e194, 1e195, 1e196, 1e197, 1e198, 1e199,
    1e200, 1e201, 1e202, 1e203, 1e204, 1e205, 1e206, 1e207, 1e208, 1e209,
    1e210, 1e211, 1e212, 1e213, 1e214, 1e215, 1e216, 1e217, 1e218, 1e219,
    1e220, 1e221, 1e222, 1e223, 1e224, 1e225, 1e226, 1e227, 1e228, 1e229,
    1e230, 1e231, 1e232, 1e233, 1e234, 1e235, 1e236, 1e237, 1e238, 1e239,
    1e240, 1e241, 1e242, 1e243, 1e244, 1e245, 1e246, 1e247, 1e248, 1e249,
    1e250, 1e251, 1e252, 1e253, 1e254, 1e255, 1e256, 1e257, 1e258, 1e259,
    1e260, 1e261, 1e262, 1e263, 1e264, 1e265, 1e266, 1e267, 1e268, 1e269,
    1e270, 1e271, 1e272, 1e273, 1e274, 1e275, 1e276, 1e277, 1e278, 1e279,
    1e280, 1e281, 1e282, 1e283, 1e284, 1e285, 1e286, 1e287, 1e288, 1e289,
    1e290, 1e291, 1e292, 1e293, 1e294, 1e295, 1e296, 1e297, 1e298, 1e299,
    1e300, 1e301, 1e302, 1e303, 1e304, 1e305, 1e306, 1e307, 1e308,
]

pow10(exp) = (@inbounds v = EXPONENTS[exp+1]; return v)

maxexponent(::Type{Int16}) = 4
maxexponent(::Type{Int32}) = 38
maxexponent(::Type{Int64}) = 308

minexponent(::Type{Int16}) = -5
minexponent(::Type{Int32}) = -38
minexponent(::Type{Int64}) = -308

inttype(::Type{Float16}) = Int16
inttype(::Type{Float32}) = Int32
inttype(::Type{Float64}) = Int64

outofrange(T::Type{<:AbstractFloat}, exp::Signed) = ArgumentError("error parsing a `$T` value; exponent out of range: $exp")

function scale(exp, v::T, frac=0) where T
    if exp >= 0
        max_exp = maxexponent(T)
        exp > max_exp && throw(outofrange(T, exp))
        if frac > 14
            fin2 = BigFloat(v) * BigFloat(JSON2.pow10(exp))
            fin = Float64(fin2)
        else
            fin = v * JSON2.pow10(exp)
        end
        return fin
    else
        min_exp = minexponent(T)
        # compensate roundoff?
        if exp < min_exp
            -exp + min_exp > -min_exp && throw(outofrange(T, exp))
            result = v / pow10(-min_exp)
            fin = result / pow10(-exp + min_exp)
            return fin
        else
            if -22 < exp < -15
                # strategy = 5
                # if strategy == 1
                #     digit = v % 10
                #     fin = div(v, 10) / JSON2.pow10(-exp - 1) + (digit / JSON2.pow10(-exp))    
                # elseif strategy == 2
                #     fin = (v * 10) / JSON2.pow10(-exp + 1)
                # elseif strategy == 3
                #     digit = v % 10
                #     fin = v / JSON2.pow10(-exp)
                #     newdigit = (fin * JSON2.pow10(-exp)) % 10
                #     if newdigit == digit
                #         return fin
                #     elseif newdigit < digit
                #         return nextfloat(fin)
                #     else
                #         return prevfloat(fin)
                #     end
                # elseif strategy == 4
                #     fin = v / JSON2.pow10(-exp)
                # elseif strategy == 5
                # @show v, -exp
                fin2 = BigFloat(v) / BigFloat(JSON2.pow10(-exp))
                # @show fin2
                fin = Float64(fin2)
                # @show fin
                # println("here 3")
                # end
            else
                # @show v, exp
                # println("here 4")
                fin = v / JSON2.pow10(-exp)
            end
            return fin
        end
    end
end

function read(io::IO, ::Type{T}) where {T <: AbstractFloat}
    eof(io) && throw(ArgumentError("early EOF"))
    b = peekbyte(io)
    negative = false
    if b == MINUS # check for leading '-' or '+'
        negative = true
        readbyte(io)
        b = peekbyte(io)
    elseif b == PLUS
        readbyte(io)
        b = peekbyte(io)
    end
    # float digit parsing
    iT = inttype(T)
    v = zero(iT)
    parseddigits = false
    while NEG_ONE < b < TEN
        b = readbyte(io)
        parseddigits = true
        # process digits
        v *= iT(10)
        v += iT(b - ZERO)
        eof(io) && (result = T(v); @goto done)
        b = peekbyte(io)
    end
    # if we didn't get any digits, check for NaN/Inf or leading dot
    if !parseddigits
        pos = position(io)
        if b == LITTLE_N || b == BIG_N
            b = readbyte(io)
            (!(b == LITTLE_A || b == BIG_A) || eof(io)) && @goto error
            b = readbyte(io)
            !(b == LITTLE_N || b == BIG_N) && @goto error
            result = T(NaN)
            @goto done
        elseif b == LITTLE_I || b == BIG_I
            b = readbyte(io)
            (!(b == LITTLE_N || b == BIG_N) || eof(io)) && @goto error
            b = readbyte(io)
            !(b == LITTLE_F || b == BIG_F) && @goto error
            result = T(Inf)
            eof(io) && @goto done
            b = peekbyte(io)
            if b == LITTLE_I || b == BIG_I
                # read the rest of INFINITY
                readbyte(io)
                eof(io) && @goto done
                b = peekbyte(io)
                b == LITTLE_N || b == BIG_N || @goto done
                readbyte(io)
                eof(io) && @goto done
                b = readbyte(io)
                b == LITTLE_I || b == BIG_I || @goto done
                readbyte(io)
                eof(io) && @goto done
                b = peekbyte(io)
                b == LITTLE_T || b == BIG_T || @goto done
                readbyte(io)
                eof(io) && @goto done
                b = peekbyte(io)
                b == LITTLE_Y || b == BIG_Y || @goto done
                readbyte(io)
                eof(io) && @goto done
                b = peekbyte(io)
            end
            @goto done
        elseif b == PERIOD
            # keep parsing fractional part below
        else
            @goto error
        end
    end
    # parse fractional part
    frac = 0
    result = T(v)
    if b == PERIOD
        eof(io) && (parseddigits ? @goto(done) : @goto(error))
        readbyte(io)
        b = peekbyte(io)
    elseif b == LITTLE_E || b == BIG_E
        @goto parseexp
    else
        @goto done
    end

    while NEG_ONE < b < TEN
        b = readbyte(io)
        frac += 1
        # process digits
        v *= iT(10)
        v += iT(b - ZERO)
        eof(io) && (result = scale(-frac, v); @goto done)
        b = peekbyte(io)
    end
    # parse potential exp
    if b == LITTLE_E || b == BIG_E
        @label parseexp
        eof(io) && (result = scale(-frac, v); @goto done)
        readbyte(io)
        b = peekbyte(io)
        exp = zero(iT)
        negativeexp = false
        if b == MINUS
            negativeexp = true
            readbyte(io)
            b = peekbyte(io)
        elseif b == PLUS
            readbyte(io)
            b = peekbyte(io)
        end
        parseddigits = false
        while NEG_ONE < b < TEN
            b = readbyte(io)
            parseddigits = true
            # process digits
            exp *= iT(10)
            exp += iT(b - ZERO)
            eof(io) && (result = scale(ifelse(negativeexp, -exp, exp) - frac, v, frac); @goto done)
            b = peekbyte(io)
        end
        result = parseddigits ? scale(ifelse(negativeexp, -exp, exp) - frac, v, frac) : scale(-frac, v)
    else
        result = scale(-frac, v)
    end

    @label done
    return T(ifelse(negative, -result, result))

    @label error
    throw(invalid(T, b))
end