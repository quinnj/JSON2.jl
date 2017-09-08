using Base.Test, JSON2

include("json.jl")

## custom json formatting for types
struct B
    id::Int
    name::String
    B(id::Int) = new(id)
    B(id::Int, name::String) = new(id, name)
end
B(id::Int, ::Void) = B(id)

b1 = B(1, "harry")
b2 = B(2, "hermione")
b3 = B(3, "ron")

partialB = B(4)

@test JSON2.write(b1) == "{\"id\":1,\"name\":\"harry\"}"
@test JSON2.read(JSON2.write(b1), B) == b1
@test JSON2.write(b2) == "{\"id\":2,\"name\":\"hermione\"}"
@test JSON2.read(JSON2.write(b2), B) == b2
@test JSON2.write(b3) == "{\"id\":3,\"name\":\"ron\"}"
@test JSON2.read(JSON2.write(b3), B) == b3
# #undef field
@test JSON2.write(partialB) == "{\"id\":4,\"name\":null}"
@test JSON2.read(JSON2.write(partialB), B) == partialB

struct B1
    id::Int
    name::String
    B1(id::Int) = new(id)
    B1(id::Int, nm::String) = new(id, nm)
end

JSON2.@format B1 begin
    name => (omitempty=true,)
end

@test JSON2.write(B1(4)) == "{\"id\":4}"
@test JSON2.read(JSON2.write(B1(4)), B1) == B1(4)

struct B2
    id::Int
    name::String
    B2(id::Int) = new(id)
    B2(id::String, ::Void) = new(parse(Int, id))
end

JSON2.@format B2 begin
    id => (T=String,)
end

@test JSON2.write(B2(4)) == "{\"id\":\"4\",\"name\":null}"
@test JSON2.read(JSON2.write(B2(4)), B2) == B2(4)

struct B3
    id::Int
    name::String
    B3(id::Int) = new(id)
    B3(::Void) = new()
end

JSON2.@format B3 begin
    id => (exclude=true,)
end

@test JSON2.write(B3(4)) == "{\"name\":null}"
bb3 = JSON2.read(JSON2.write(B3(4)), B3)
@test !isdefined(bb3, :name)

struct B4
    id::Int
    name::String
    B4(id::Int) = new(id)
    B4() = new()
end

JSON2.@format B4 begin
    id => (exclude=true,)
    name => (omitempty=true, T=String)
end

@test JSON2.write(B4(4)) == "{}"
bb4 = JSON2.read(JSON2.write(B4(4)), B4)
@test !isdefined(bb4, :name)

struct B5
    id::Int
    name::String
    B5(; kwargs...) = (nt = (; kwargs...); return new(get(nt, :id, 0), get(nt, :name, "")))
end

JSON2.@format B5 keywordargs=true

@test JSON2.read("{\"id\":1}", B5) == B5(; id=1)

# builtins
# Any
@test JSON2.read("") == NamedTuple()
@test JSON2.read("{\"hey\":1}") == (hey=1,)
@test JSON2.read("[\"hey\",1]") == ["hey",1]
@test JSON2.read("1.0") === 1
@test JSON2.read("1") === 1
@test JSON2.read("1.1") === 1.1
@test JSON2.read("+1.1") === 1.1
@test JSON2.read("-1.1") === -1.1
@test JSON2.read("\"hey\"") == "hey"
@test JSON2.read("null") === nothing
@test JSON2.read("true") === true
@test JSON2.read("false") === false

# Union
@test JSON2.read("1.0", Union{Float64, Int}) === 1.0
@test JSON2.read("1.1", Union{Float64, Int}) === 1.1
@test JSON2.read("1.1", Union{Float64, String}) === 1.1
@test JSON2.read("\"1.1\"", Union{Float64, String}) === "1.1"
@test JSON2.read("1.1", Union{Void, Float64}) === 1.1
@test JSON2.read("null", Union{Void, Float64}) === nothing

# NamedTuple
@test JSON2.read("{\"hey\":1}", NamedTuple) == (hey=1,)
@test JSON2.read("{\"hey\":1,\"ho\":2}", NamedTuple) == (hey=1,ho=2)

@test JSON2.write(Dict("name"=>1)) == "{\"name\":1}"
@test JSON2.read(JSON2.write(Dict("name"=>1)), Dict) == Dict("name"=>1)
@test JSON2.write(Dict()) == "{}"
@test JSON2.read(JSON2.write(Dict()), Dict) == Dict()

@test JSON2.write([]) == "[]"
@test JSON2.read(JSON2.write([]), Array) == []
@test JSON2.write([1, 2, 3]) == "[1,2,3]"
@test JSON2.read(JSON2.write([1, 2, 3]), Array) == [1, 2, 3]
@test JSON2.write(["hey", "there", "sailor"]) == "[\"hey\",\"there\",\"sailor\"]"
@test JSON2.read(JSON2.write(["hey", "there", "sailor"]), Array) == ["hey", "there", "sailor"]
@test JSON2.write([1, 2, 3, "hey", "there", "sailor"]) == "[1,2,3,\"hey\",\"there\",\"sailor\"]"
@test JSON2.read(JSON2.write([1, 2, 3, "hey", "there", "sailor"]), Array) == [1, 2, 3, "hey", "there", "sailor"]
@test JSON2.write([split("hey there sailor", ' ')...]) == "[\"hey\",\"there\",\"sailor\"]"
@test JSON2.read(JSON2.write([split("hey there sailor", ' ')...]), Array) == [split("hey there sailor", ' ')...]

@test JSON2.write(()) == "[]"
@test JSON2.read(JSON2.write(()), Tuple) == ()
@test JSON2.write((1, 2, 3)) == "[1,2,3]"
@test JSON2.read(JSON2.write((1, 2, 3)), Tuple) == (1, 2, 3)

@test JSON2.read(JSON2.write((1, 2, 3)), Set) == Set([1, 2, 3])

@test JSON2.write(1) == "1"
@test JSON2.read(JSON2.write(1), Int) == 1
for i in rand(Int, 1000000) # takes about 0.8 seconds
    @test JSON2.read(JSON2.write(i), Int) == i
end
@test JSON2.write(1.0) == "1.0"
@test JSON2.read(JSON2.write(1.0), Float64) == 1.0

include("floatparsing.jl")

@test JSON2.write("") == "\"\""
@test JSON2.read(JSON2.write(""), String) == ""
@test JSON2.write("hey") == "\"hey\""
@test JSON2.read(JSON2.write("hey"), String) == "hey"
let tmp = tempname()
    open(tmp, "w") do f
        write(f, "\"hey\"")
    end
    io = open(tmp)
    @test JSON2.read(io, String) == "hey"
    close(io)
    rm(tmp)
end
@test JSON2.read(JSON2.write('h'), Char) == 'h'
@test JSON2.write(Symbol()) == "\"\""
@test JSON2.read(JSON2.write(Symbol()), Symbol) == Symbol()
@test JSON2.write(:hey) == "\"hey\""
@test JSON2.read(JSON2.write(:hey), Symbol) == :hey

@test JSON2.write(Nullable()) == "null"
@test isnull(JSON2.read(JSON2.write(Nullable()), Nullable))
@test JSON2.write(Nullable("hey")) == "\"hey\""
@test JSON2.read(JSON2.write(Nullable("hey")), Nullable{String}) === Nullable("hey")

@test JSON2.write(Date(2017, 1, 1)) == "\"2017-01-01\""
@test JSON2.read(JSON2.write(Date(2017, 1, 1)), Date) == Date(2017, 1, 1)
df = dateformat"mm/dd/yyyy"
@test JSON2.write(Date(2017, 1, 1), df) == "\"01/01/2017\""
@test JSON2.read(JSON2.write(Date(2017, 1, 1), df), Date, df) == Date(2017, 1, 1)

@test JSON2.write(nothing) == "null"
@test JSON2.read(JSON2.write(nothing), Void) == nothing

@test JSON2.write(true) == "true"
@test JSON2.read(JSON2.write(true), Bool) == true
@test JSON2.write(false) == "false"
@test JSON2.read(JSON2.write(false), Bool) == false

@test JSON2.read("function (data) {}") == JSON2.Function("function (data) {}")
@test JSON2.read("function (data) {}", JSON2.Function) == JSON2.Function("function (data) {}")
@test JSON2.read(JSON2.write(JSON2.Function("function (data) {}"))) == JSON2.Function("function (data) {}")

mutable struct A
    int8::Int8
    int::Int
    float::Float64
    str::String
    nullint::Nullable{Int}
    nullnullint::Nullable{Int}
    nullstr::Nullable{String}
    nullnullstr::Nullable{String}
    void::Void
    truebool::Bool
    falsebool::Bool
    b::B

    ints::Vector{Int}
    emptyarray::Vector{Int}
    bs::Vector{B}
    dict::Dict{String,Int}
    emptydict::Dict{String,Int}
end

a = A(0, -1, 3.14, "string \\\" w/ escaped double quote", Nullable(4), Nullable{Int}(),
        Nullable("null string"), Nullable{String}(), nothing, true, false, b1, [1,2,3], Int[], [b2, b3],
        Dict("1"=>1, "2"=>2), Dict{String,Int}())

json = JSON2.write(a)
a2 = JSON2.read(json, A)

str = "{\n          \"int8\": 0,\n           \"int\": -1,\n         \"float\": 3.14,\n           \"str\": \"string \\\\\\\" w/ escaped double quote\",\n       \"nullint\": 4,\n   \"nullnullint\": null,\n       \"nullstr\": \"null string\",\n   \"nullnullstr\": null,\n          \"void\": null,\n      \"truebool\": true,\n     \"falsebool\": false,\n             \"b\": {\n                       \"id\": 1,\n                     \"name\": \"harry\"\n                  },\n          \"ints\": [\n                    1,\n                    2,\n                    3\n                  ],\n    \"emptyarray\": [],\n            \"bs\": [\n                    {\n                         \"id\": 2,\n                       \"name\": \"hermione\"\n                    },\n                    {\n                         \"id\": 3,\n                       \"name\": \"ron\"\n                    }\n                  ],\n          \"dict\": {\n                     \"1\": 1,\n                     \"2\": 2\n                  },\n     \"emptydict\": {}\n}"
io = IOBuffer()
JSON2.pretty(io, json)
@test String(take!(io)) == str

# 230
@test a.int8 == a2.int8
@test a.int == a2.int
@test a.float == a2.float
@test a.str == a2.str
@test get(a.nullint) == get(a2.nullint)
@test isnull(a.nullnullint) && isnull(a2.nullnullint)
@test get(a.nullstr) == get(a2.nullstr)
@test isnull(a.nullnullstr) && isnull(a2.nullnullstr)
@test a.void == a2.void
@test a.truebool == a2.truebool
@test a.falsebool == a2.falsebool
@test a.b == a2.b
@test a.ints == a2.ints
@test a.emptyarray == a2.emptyarray
@test a.bs == a2.bs
@test a.dict == a2.dict
@test a.emptydict == a2.emptydict

# test invalid handling
@test_throws ArgumentError JSON2.read("trua")
@test_throws ArgumentError JSON2.read("tru")
@test_throws ArgumentError JSON2.read("fals")
@test_throws ArgumentError JSON2.read("falst")
@test_throws ArgumentError JSON2.read("f")
@test_throws ArgumentError JSON2.read("a", Bool)

@test_throws ArgumentError JSON2.read("nul", Void)
@test_throws ArgumentError JSON2.read("nule", Void)
@test_throws ArgumentError JSON2.read("abcd", Void)

@test_throws ArgumentError JSON2.read("nule", Nullable{Int})
@test_throws ArgumentError JSON2.read("abc", Nullable{Int})

@test_throws ArgumentError JSON2.read("abc", Int)

@test_throws ArgumentError JSON2.read("a", Char)
@test_throws ArgumentError JSON2.read("\"abc\"", Char)