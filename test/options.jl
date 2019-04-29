const dtfmt = dateformat"YYYY.mm.dd-HH.MM.SS.sss"

struct OptionsTest
    d::Date
    dt::DateTime
end

JSON2.@format OptionsTest dateformat=dtfmt

@testset "Read/write options" begin
    d = Date(1, 2, 3)
    dt = DateTime(1, 2, 3, 4, 5, 6, 7)

    @testset "Read" begin
        dstr = repr(Dates.format(d, ISODateFormat))
        dtstr = repr(Dates.format(dt, ISODateTimeFormat))

        @test JSON2.read(dstr, Date) == d
        @test JSON2.read(dtstr, DateTime) == dt

        @test JSON2.read(repr(Dates.format(d, dtfmt)), Date; dateformat=dtfmt) == d
        @test JSON2.read(repr(Dates.format(dt, dtfmt)), DateTime; dateformat=dtfmt) == dt
    end

    @testset "Write" begin
        @test JSON2.write(d) == repr(Dates.format(d, ISODateFormat))
        @test JSON2.write(dt) == repr(Dates.format(dt, ISODateTimeFormat))

        @test JSON2.write(d; dateformat=dtfmt) == repr(Dates.format(d, dtfmt))
        @test JSON2.write(dt; datetimeformat=dtfmt) == repr(Dates.format(dt, dtfmt))
    end

    @testset "Structs" begin
        opts = OptionsTest(d, dt)

        s = JSON2.write(opts; dateformat=dtfmt)
        @test JSON2.read(s, OptionsTest) == opts

        s = JSON2.write(opts; dateformat=ISODateTimeFormat)
        @test JSON2.read(s, OptionsTest; dateformat=ISODateTimeFormat) == opts
    end
end
