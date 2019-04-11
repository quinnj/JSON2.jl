const dfmt = dateformat"YYYY.mm.dd"
const dtfmt = dateformat"YYYY.mm.dd-HH.MM.SS.sss"

struct OptionsTest
    d::Date
    dt::DateTime
end

JSON2.@format OptionsTest dateformat=dfmt datetimeformat=dtfmt

@testset "Read/write options" begin
    d = Date(1, 2, 3)
    dt = DateTime(1, 2, 3, 4, 5, 6, 7)

    @testset "Read" begin
        dstr = repr(Dates.format(d, ISODateFormat))
        dtstr = repr(Dates.format(dt, ISODateTimeFormat))

        @test JSON2.read(dstr, Date) == d
        @test JSON2.read(dtstr, DateTime) == dt

        @test JSON2.read(repr(Dates.format(d, dfmt)), Date; dateformat=dfmt) == d
        @test JSON2.read(repr(Dates.format(dt, dtfmt)), DateTime; datetimeformat=dtfmt) == dt
    end

    @testset "Write" begin
        @test JSON2.write(d) == repr(Dates.format(d, ISODateFormat))
        @test JSON2.write(dt) == repr(Dates.format(dt, ISODateTimeFormat))

        @test JSON2.write(d; dateformat=dfmt) == repr(Dates.format(d, dfmt))
        @test JSON2.write(dt; datetimeformat=dtfmt) == repr(Dates.format(dt, dtfmt))
    end

    @testset "Structs" begin
        opts = OptionsTest(d, dt)

        s = JSON2.write(opts; dateformat=dfmt, datetimeformat=dtfmt)
        @test JSON2.read(s, OptionsTest) == opts

        s = JSON2.write(opts; dateformat=ISODateFormat, datetimeformat=ISODateTimeFormat)
        @test JSON2.read(s, OptionsTest; dateformat=ISODateFormat, datetimeformat=ISODateTimeFormat) == opts
    end
end
