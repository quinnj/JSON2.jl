
# JSON2

*Fast JSON for Julia types*

| **PackageEvaluator**                                            | **Build Status**                                                                                |
|:---------------------------------------------------------------:|:-----------------------------------------------------------------------------------------------:|
|[![][pkg-0.6-img]][pkg-0.6-url] | [![][travis-img]][travis-url] [![][codecov-img]][codecov-url] |


## Installation

The package is registered in `METADATA.jl` and so can be installed with `Pkg.add`.

```julia
julia> Pkg.add("JSON2")
```

## Project Status

The package is tested against the current Julia `0.6` release and nightly on Linux and OS X.

## Contributing and Questions

Contributions are very welcome, as are feature requests and suggestions. Please open an
[issue][issues-url] if you encounter any problems or would just like to ask a question.


<!-- [docs-latest-img]: https://img.shields.io/badge/docs-latest-blue.svg
[docs-latest-url]: https://quinnj.github.io/JSON2.jl/latest -->

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://quinnj.github.io/JSON2.jl/stable

[travis-img]: https://travis-ci.org/quinnj/JSON2.jl.svg?branch=master
[travis-url]: https://travis-ci.org/quinnj/JSON2.jl

[codecov-img]: https://codecov.io/gh/quinnj/JSON2.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/quinnj/JSON2.jl

[issues-url]: https://github.com/quinnj/JSON2.jl/issues

[pkg-0.6-img]: http://pkg.julialang.org/badges/JSON2_0.6.svg
[pkg-0.6-url]: http://pkg.julialang.org/?pkg=JSON2

## Documentation

For most use-cases, all you ever need are:
```julia
JSON2.write(obj) => String
JSON2.read(str, T) => T
@pretty json_string # print a "prettified" version of a JSON string
```

Native support for reading/writing is provided for:
* `NamedTuple`
* `Array`
* `Number`
* `Nothing`/`Missing`: corresponds to JSON `null`
* `String`
* `Bool`
* `JSON2.Function`: type that represents a javascipt function (stored in plain text)
* `Union{T, Nothing}`
* `AbstractDict`
* `Tuple`
* `Set`
* `Char`
* `Symbol`
* `Enum`
* `Date`/`DateTime`

Custom types are supported by default as well, utilizing reflection to generate compiled JSON parsers for a type's fields. So in general, you really can just do `JSON2.read(str, MyType)` and everything will "Just Work" (and be freaky fast as well!).

### Custom JSON Formatting

#### Default
In many cases, a type doesn't even _need_ to use `JSON2.@format` since the default reflection-based parsing is somewhat flexible. By default, the JSON input is expected to contain each field of a type and be in the same order as the type was defined. For example, the struct:
```julia
struct T
    a::Int
    b::Int
    c::Union{Nothing, Int}
end
```
Could have valid JSON in the forms:
```json
{"a": 0, "b": 1, "c": null} // all 3 fields provided in correct order
{"a": 0, "b": 1, "c": 2}
{"a": 0, "b": 1, "c": null, "d": 3} // extra fields are ignored
{"a": 0} // will work if T(a) constructor is defined
{"a": 0, "b": 1} // will work if T(a, b) constructor is defined
```
That is, each field _must_ be present in the JSON input and match in position to the original struct definition. Extra arguments after the struct's own fieldtypes are ignored. As noted, the exception to a field needing to be present is if 1) the field and _all subsequent fields_ are not present and 2) appropriate constructors are defined that take these limited subsets of inputs when constructing, e.g. `T(a)`, `T(a, b)`, etc.

#### JSON.@format T
```julia
JSON2.@format T [noargs|keywordargs] begin
    _field_ => (; options...)
    _field2_ => (; options...)
end
```
Specify a custom JSON formatting for a struct `T`, with individual field options being given like `fieldname => (; option1=value1, option2=value2)`, i.e a Pair of the name of the field to a NamedTuple of options. Valid field options include:
* `name`: if a field's name should be read/written differently than it's defined name
* `jsontype`: if the JSON type of a field is different than the julia field type, the JSON type can be provided like `jsontype=String`
* `omitempty`: whether an "empty" julia field should still be written; applies to collection types like `AbstractArray`, `AbstractDict`, `AbstractSet`, etc.
* `exclude`: whether a julia field should be excluded altogether from JSON reading/writing
* `default`: a default value that can be provided for a julia field if it may not appear in a JSON input string when parsing

Again, the default case is for JSON input that will have consistently ordered, always-present fields; for cases where the input JSON is _not_ well-ordered or if there is a possibility of a field not being present in the JSON input, there are a few additional options for custom parsing.

#### Default field values
If the JSON input fields will always be consistenly-ordered, but fields may be missing (i.e. field isn't present at all in the input), field defaults can be provided like:
```julia
JSON2.@format T begin
    c => (default=0,)
end
```
This says that, when reading from a JSON input, if field `c` isn't present, to set it's value to 0.

If the JSON input is not consistenly-ordered, there are two other options for allowing direct type parsing
#### Keywordargs Constructor
```julia
T(; a=0, b=0, c=0, kwargs...) = T(a, b, c)
JSON2.@format T keywordargs begin
    # ...
end
```
Here we've defined a "keywordargs" constructor for `T` that essentially takes a default for each field as keyword arguments, then constructs `T`.
During parsing, the JSON input will be parsed for any valid field key-values and the keyword constructor will be called
with whatever arguments are parsed in whatever order. Note that we also included a catchall `kwargs...` in our constructor which can be used to "throw away" or ignore any extra fields in the JSON input.

#### Noargs Constructor
```julia
mutable struct T
    a::Int
    b::Int
    c::Union{Nothing, Int}
end
T() = T(0, 0, 0)
JSON2.@format T noargs begin
    #...
end
```
In this case, we've made `T` a _mutable_ struct and defined a "noargs" constructor `T() = ...`; we then specified in `JSON2.@format T noargs` the `noargs` option.
During parsing, an instance of `T` will first constructed using the "noargs" constructor, then fields will be set as they're parsed from the JSON input (hence why `mutable struct` is required).
