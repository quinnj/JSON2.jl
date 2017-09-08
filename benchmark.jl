using JSON2, JSON
using BenchmarkTools

const suite2 = BenchmarkGroup()

suite2["print"] = BenchmarkGroup(["serialize"])
# suite["pretty-print"] = BenchmarkGroup(["serialize"])

struct CustomListType
    x::Int
    y::Float64
    z::Union{CustomListType, Void}
end

struct CustomTreeType
    x::String
    y::Union{CustomTreeType, Void}
    z::Union{CustomTreeType, Void}
end

list(x) = x == 0 ? nothing : CustomListType(1, 1.0, list(x - 1))
tree(x) = x == 0 ? nothing : CustomTreeType("!!!", tree(x - 1), tree(x - 1))

const micros = Dict(
    "integer" => 88,
    "float" => -88.8,
    "ascii" => "Hello World!",
    "ascii-1024" => "x" ^ 1024,
    "unicode" => "ສະ​ບາຍ​ດີ​ຊາວ​ໂລກ!",
    "unicode-1024" => "ℜ" ^ 1024,
    "bool" => true,
    "null" => nothing,
    "flat-homogenous-array-16" => collect(1:16),
    "flat-homogenous-array-1024" => collect(1:1024),
    "heterogenous-array" => [
        1, 2, 3, 7, "A", "C", "E", "N", "Q", "R", "Shuttle to Grand Central"],
    "nested-array-16^2" => [collect(1:16) for _ in 1:16],
    "nested-array-16^3" => [[collect(1:16) for _ in 1:16] for _ in 1:16],
    "small-dict" => Dict(
        :a => :b, :c => "💙💙💙💙💙💙", :e => 10, :f => Dict(:a => :b)),
    "flat-dict-128" => Dict(zip(collect(1:128), collect(1:128))),
    "date" => Date(2016, 08, 09),
    "matrix-16" => eye(16),
    "custom-list-128" => list(128),
    "custom-tree-8" => tree(8))


@benchmark JSON2.write($(IOBuffer()), $(micros["integer"]))
@benchmark JSON.print($(IOBuffer()), $(micros["integer"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["float"]))
@benchmark JSON.print($(IOBuffer()), $(micros["float"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["ascii"]))
@benchmark JSON.print($(IOBuffer()), $(micros["ascii"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["ascii-1024"]))
@benchmark JSON.print($(IOBuffer()), $(micros["ascii-1024"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["bool"]))
@benchmark JSON.print($(IOBuffer()), $(micros["bool"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["null"]))
@benchmark JSON.print($(IOBuffer()), $(micros["null"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["flat-homogenous-array-16"])) # should be better
@benchmark JSON.print($(IOBuffer()), $(micros["flat-homogenous-array-16"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["nested-array-16^2"]))
@benchmark JSON.print($(IOBuffer()), $(micros["nested-array-16^2"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["small-dict"]))  #TODO
@benchmark JSON.print($(IOBuffer()), $(micros["small-dict"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["date"]))
@benchmark JSON.print($(IOBuffer()), $(micros["date"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["custom-list-128"]))
@benchmark JSON.print($(IOBuffer()), $(micros["custom-list-128"]))

@benchmark JSON2.write($(IOBuffer()), $(micros["custom-tree-8"]))
@benchmark JSON.print($(IOBuffer()), $(micros["custom-tree-8"]))

b = @benchmarkable JSON2.read("\"id\"", Symbol); tune!(b); run(b)
b = @benchmarkable JSON2.read("\"id\"", String); tune!(b); run(b)

b = @benchmarkable JSON2.read("{\"id\": 1, \"name\": \"sally\"}"); tune!(b); run(b)
b = @benchmarkable JSON.parse("{\"id\": 1, \"name\": \"sally\"}"); tune!(b); run(b)

@time JSON2.read(IOBuffer(Mmap.mmap("/Users/jacobquinn/Downloads/100k_twitter_users.json")));
@time JSON.parsefile("/Users/jacobquinn/Downloads/100k_twitter_users.json");