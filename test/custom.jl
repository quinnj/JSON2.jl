import Base.==
## custom json formatting for types
struct B
    id::Int
    name::String
    B(id::Int) = new(id)
    B(id::Int, name::String) = new(id, name)
end
B(id::Int, ::Nothing) = B(id)

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
    B2(id::String, ::Nothing) = new(parse(Int, id))
end

JSON2.@format B2 begin
    id => (jsontype=String,)
    name => (omitempty=true,)
end

@test JSON2.write(B2(4)) == "{\"id\":\"4\"}"
@test JSON2.read(JSON2.write(B2(4)), B2) == B2(4)

struct B3
    id::Int
    name::Union{Nothing, String}
    B3(id::Int) = new(id)
    B3(::Nothing) = new()
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
    name => (omitempty=true, jsontype=String)
end

@test JSON2.write(B4(4)) == "{}"
bb4 = JSON2.read(JSON2.write(B4(4)), B4)
@test !isdefined(bb4, :name)

struct B5
    id::Int
    name::String
    B5(; id=0, name="", kwargs...) = new(id, name)
end

JSON2.@format B5 keywordargs

@test JSON2.read("{\"id\":1}", B5) == B5(; id=1)
@test JSON2.read("{}", B5) == B5()
@test JSON2.read("{\"id\":1,\"name\":\"hey\"}", B5) == B5(; id=1, name="hey")
@test JSON2.read("{\"id\":1,\"name2\":\"hey\"}", B5) == B5(; id=1)


const jsons = [
    """{"a": 1, "b": 2, "c": 3, "d": 4}""",
    """{"a": 1, "b": 2, "c": 3, "d": 4, "e": 5}""",
    """{"a": 1, "d": 4}""",
    """{"a": 1, "e": 5, "d": 4}""",
    """{"c": 3, "a": 1, "d": 4, "b": 2}""",
    """{"c": 3, "a": 1, "e": 5, "d": 4, "b": 2}""",
    """{"d": 4, "a": 1}""",
    """{"d": 4, "e": 5, "a": 1}""",
]

# default read
struct AJ1
    a::Int
    b::Int
    c::Int
    d::Int
end

@test JSON2.read(jsons[1], AJ1) == AJ1(1, 2, 3, 4)
@test JSON2.read(jsons[2], AJ1) == AJ1(1, 2, 3, 4)

# providing field defaults
struct AJ2
    a::Int
    b::Int
    c::Int
    d::Int
end

JSON2.@format AJ2 begin
    b => (default=2,)
    c => (default=3,)
end

@test JSON2.read(jsons[3], AJ2) == AJ2(1, 2, 3, 4)
@test JSON2.read(jsons[4], AJ2) == AJ2(1, 2, 3, 4)

# noargs
mutable struct AJ3
    a::Int
    b::Int
    c::Int
    d::Int
    AJ3() = new(0, 0, 0, 0)
end
==(a::AJ3, b::AJ3) = a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d
JSON2.@format AJ3 noargs begin
    b => (default=2,)
    c => (default=3,)
end

const aj3 = AJ3()
aj3.a = 1
aj3.b = 2
aj3.c = 3
aj3.d = 4
@test JSON2.read(jsons[5], AJ3) == aj3
@test JSON2.read(jsons[6], AJ3) == aj3
@test JSON2.read(jsons[7], AJ3) == aj3
@test JSON2.read(jsons[8], AJ3) == aj3

# keywordargs
struct AJ4
    a::Int
    b::Int
    c::Int
    d::Int
    AJ4(; a=1, b=0, c=0, d=4, kwargs...) = new(a, b, c, d)
end
==(a::AJ4, b::AJ4) = a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d
JSON2.@format AJ4 keywordargs begin
    b => (default=2,)
    c => (default=3,)
end

const aj4 = AJ4(b=2, c=3)
@test JSON2.read(jsons[5], AJ4) == aj4
@test JSON2.read(jsons[6], AJ4) == aj4
@test JSON2.read(jsons[7], AJ4) == aj4
@test JSON2.read(jsons[8], AJ4) == aj4
