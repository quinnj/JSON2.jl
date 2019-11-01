const dttmfmt = dateformat"YYYY.mm.dd-HH.MM.SS.sss"
const dtfmt = dateformat"YYYY.mm.dd"

struct OptionsTest
    d::Date
    dt::DateTime
end

JSON2.@format OptionsTest dateformat=dtfmt write_datetimeformat=dttmfmt read_datetimeformats=[dttmfmt]

@testset "Read/write options" begin
    d = Date(1, 2, 3)
    dt = DateTime(1, 2, 3, 4, 5, 6, 7)

    @testset "Read" begin
        dstr = repr(Dates.format(d, ISODateFormat))
        dtstr = repr(Dates.format(dt, ISODateTimeFormat))

        @test JSON2.read(dstr, Date) == d
        @test JSON2.read(dtstr, DateTime) == dt

        @test JSON2.read(repr(Dates.format(d, dtfmt)), Date; dateformat=dtfmt) == d
        @test JSON2.read(repr(Dates.format(dt, dttmfmt)), DateTime; dateformat=dttmfmt) == dt
    end

    @testset "Write" begin
        @test JSON2.write(d) == repr(Dates.format(d, ISODateFormat))
        @test JSON2.write(dt) == repr(Dates.format(dt, ISODateTimeFormat))

        @test JSON2.write(d; dateformat=dtfmt) == repr(Dates.format(d, dtfmt))
        @test JSON2.write(dt; dateformat=dttmfmt) == repr(Dates.format(dt, dttmfmt))
    end

    @testset "Structs" begin
        opts = OptionsTest(d, dt)

        s = JSON2.write(opts; write_datetimeformat=dttmfmt, dateformat=dtfmt)
        @test JSON2.read(s, OptionsTest) == opts

        s = JSON2.write(opts; dateformat=Dates.ISODateFormat, write_datetimeformat=Dates.ISODateTimeFormat)
        @test JSON2.read(s, OptionsTest; dateformat=Dates.ISODateFormat, read_datetimeformats=[Dates.ISODateTimeFormat]) == opts
    end
end
