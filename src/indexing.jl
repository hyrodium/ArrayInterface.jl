
_as_index(x) = x
_as_index(x::OneTo) = static(1):length(x)
_as_index(x::StepRange) = OptionallyStaticStepRange(x)
_as_index(x::UnitRange) = OptionallyStaticUnitRange(x)
_as_index(x::OptionallyStaticRange) = x

"""
    StrideIndices
"""
struct StrideIndices{N,R,O1,O,S,A<:Tuple{Vararg{Any,N}}} <: AbstractArray2{Int,N}
    rank::R
    offset1::O1
    offsets::O
    strides::S
    axes::A
end
offset1(x::StrideIndices) = getfield(x, :offset1)
offsets(x::StrideIndices) = getfield(x, :offsets)
axes(x::StrideIndices) = getfield(x, :axes)
@inline function axes(x::StrideIndices{N}, i::Int) where {N}
    if i > N
        return static(1):1
    else
        return getfield(getfield(x, :axes), i)
    end
end
@inline function axes(x::StrideIndices{N}, ::StaticInt{i}) where {N,i}
    if i > N
        return static(1):static(1)
    else
        return getfield(getfield(x, :axes), i)
    end
end
strides(x::StrideIndices) = getfield(x, :strides)
stride_rank(x::StrideIndices) = getfield(x, :rank)

@inline function StrideIndices(x::DenseArray)
    a = axes(x)
    return StrideIndices(
        stride_rank(x),
        offset1(x),
        map(static_first, a),
        size_to_strides(map(static_length, a), static(1)),
        a
    )
end

# TODO optimize this
@inline function StrideIndices(x)
    return StrideIndices(
        stride_rank(x),
        offset1(x),
        offsets(x),
        strides(x),
        axes(x)
    )
end

##############
### layout ###
##############
layout(x, index) = layout(x)
layout(x, index::AbstractVector{<:Integer}) = _maybe_linear_layout(IndexStyle(x), x)
layout(x, index::Integer) = _maybe_linear_layout(IndexStyle(x), x)
layout(x, index::AbstractCartesianIndex{1}) = _maybe_linear_layout(IndexStyle(x), x)
function layout(x, index::AbstractVector{AbstractCartesianIndex{1}})
    return _maybe_linear_layout(IndexStyle(x), x)
end
_maybe_linear_layout(::IndexLinear, x) = _as_index(eachindex(x))
_maybe_linear_layout(::IndexStyle, x) = layout(x)
layout(x::StrideIndices) = x
layout(x::LinearIndices) = x
layout(x::CartesianIndices) = x
function layout(x)
    if defines_strides(x)
        return StrideIndices(x)
    else
        return _layout_indices(IndexStyle(x), axes(x))
    end
end
_layout_indices(::IndexStyle, axs) = CartesianIndices(axs)
_layout_indices(::IndexLinear, axs) = LinearIndices(axs)

"""
    ArrayStyle(::Type{A})

Used to customize the meaning of indexing arguments in the context of a given array `A`.

See also: [`argdims`](@ref), [`UnsafeIndex`](@ref)
"""
abstract type ArrayStyle end

struct DefaultArrayStyle <: ArrayStyle end

ArrayStyle(A) = ArrayStyle(typeof(A))
ArrayStyle(::Type{A}) where {A} = DefaultArrayStyle()

"""
    argdims(::ArrayStyle, ::Type{T})

What is the dimensionality of the indexing argument of type `T`?
"""
argdims(x, arg) = argdims(x, typeof(arg))
argdims(x, ::Type{T}) where {T} = argdims(ArrayStyle(x), T)
argdims(s::ArrayStyle, arg) = argdims(s, typeof(arg))
# single elements initially map to 1 dimension but that dimension is subsequently dropped.
argdims(::ArrayStyle, ::Type{T}) where {T} = static(0)
argdims(::ArrayStyle, ::Type{T}) where {T<:Colon} = static(1)
argdims(::ArrayStyle, ::Type{T}) where {T<:AbstractArray} = static(ndims(T))
argdims(::ArrayStyle, ::Type{T}) where {N,T<:AbstractCartesianIndex{N}} = static(N)
argdims(::ArrayStyle, ::Type{T}) where {N,T<:AbstractArray{<:AbstractCartesianIndex{N}}} = static(N)
argdims(::ArrayStyle, ::Type{T}) where {N,T<:AbstractArray{<:Any,N}} = static(N)
argdims(::ArrayStyle, ::Type{T}) where {N,T<:LogicalIndex{<:Any,<:AbstractArray{Bool,N}}} = static(N)
_argdims(s::ArrayStyle, ::Type{I}, i::StaticInt) where {I} = argdims(s, _get_tuple(I, i))
function argdims(s::ArrayStyle, ::Type{T}) where {N,T<:Tuple{Vararg{Any,N}}}
    return eachop(_argdims, nstatic(Val(N)), s, T)
end

_is_element_index(i) = _is_element_index(typeof(i))
_is_element_index(::Type{T}) where {T} = static(false)
_is_element_index(::Type{T}) where {T<:AbstractCartesianIndex} = static(true)
_is_element_index(::Type{T}) where {T<:Integer} = static(true)
__is_element_index(::Type{T}, i::StaticInt) where {T} = _is_element_index(_get_tuple(T, i))
function _is_element_index(::Type{T}) where {N,T<:Tuple{Vararg{Any,N}}}
    return static(all(eachop(__is_element_index, nstatic(Val(N)), T)))
end
# empty tuples refer to the single element of 0-dimensional arrays
_is_element_index(::Type{Tuple{}}) = static(true)

# are the indexing arguments provided a linear collection into a multidim collection
is_linear_indexing(A, args::Tuple{Arg}) where {Arg} = static(argdims(A, Arg) < 2)
is_linear_indexing(A, args::Tuple{Arg,Vararg{Any}}) where {Arg} = static(false)

"""
    unsafe_reconstruct(A, data; kwargs...)

Reconstruct `A` given the values in `data`. New methods using `unsafe_reconstruct`
should only dispatch on `A`.
"""
function unsafe_reconstruct(axis::OneTo, data; kwargs...)
    if axis === data
        return axis
    else
        return OneTo(data)
    end
end
function unsafe_reconstruct(axis::UnitRange, data; kwargs...)
    if axis === data
        return axis
    else
        return UnitRange(first(data), last(data))
    end
end
function unsafe_reconstruct(axis::OptionallyStaticUnitRange, data; kwargs...)
    if axis === data
        return axis
    else
        return OptionallyStaticUnitRange(static_first(data), static_last(data))
    end
end
function unsafe_reconstruct(A::AbstractUnitRange, data; kwargs...)
    return static_first(data):static_last(data)
end

"""
    to_indices(A, args::Tuple) -> to_indices(A, axes(A), args)
    to_indices(A, axes::Tuple, args::Tuple)

Maps arguments `args` to the axes of `A`. This is done by iteratively passing each
axis and argument to [`to_index`](@ref). Unique behavior based on the type of `A` may be
accomplished by overloading `to_indices(A, args)`. Unique axis-argument behavior can
be accomplished using `to_index(axis, arg)`.
"""
@inline @propagate_inbounds function to_indices(A, args::Tuple)
    return _to_indices(is_linear_indexing(A, args), A, args)
end
@propagate_inbounds function to_indices(A, args::Tuple{})
    @boundscheck ndims(A) > 0 && throw(BoundsError(A, ()))
    return NDIndex{0}()
end
@inline @propagate_inbounds function _to_indices(::True, A, args::Tuple)
    return (to_index(eachindex(A), first(args)),)
end
@inline @propagate_inbounds function _to_indices(::False, A, args::Tuple)
    return to_indices(A, axes(A), args)
end
# to_indices(A::AbstractArray, axes::Tuple, args::Tuple)
@inline @propagate_inbounds function to_indices(A, axs::Tuple, args::Tuple{I,Vararg{Any}}) where {I}
    return _to_indices(argdims(A, I), A, axs, args)
end
@inline @propagate_inbounds function _to_indices(::StaticInt{0}, A, axs::Tuple, args::Tuple)
    return (to_index(first(axs), first(args)), to_indices(A, tail(axs), tail(args))...)
end
@inline @propagate_inbounds function _to_indices(::StaticInt{1}, A, axs::Tuple, args::Tuple)
    return (to_index(first(axs), first(args)), to_indices(A, tail(axs), tail(args))...)
end
@inline @propagate_inbounds function _to_indices(::StaticInt{N}, A, axs::Tuple, args::Tuple) where {N}
    axes_front, axes_tail = Base.IteratorsMD.split(axs, Val(N))
    return _to_multi_indices(A, axes_front, axes_tail, first(args), tail(args))
end
@inline @propagate_inbounds function _to_multi_indices(
    A,
    axes_front::Tuple,
    axes_tail::Tuple,
    arg::Union{LinearIndices,CartesianIndices},
    args::Tuple
)
    return (
        to_indices(_layout_indices(IndexStyle(A), axes_front), axes(arg))...,
        to_indices(A, axes_tail, args)...,
    )
end
@propagate_inbounds function _to_multi_indices(
    A,
    axes_front::Tuple,
    axes_tail::Tuple,
    arg::AbstractCartesianIndex,
    args::Tuple
)
    return (
        to_indices(_layout_indices(IndexStyle(A), axes_front), Tuple(arg))...,
        to_indices(A, axes_tail, args)...,
    )
end

@propagate_inbounds function _to_multi_indices(A, f::Tuple, l::Tuple, arg, args::Tuple)
    return (to_index(_layout_indices(IndexStyle(A), f), arg), to_indices(A, l, args)...)
end

@propagate_inbounds function to_indices(A, axs::Tuple, args::Tuple{})
    @boundscheck if length(first(axs)) != 1
        error("Cannot drop dimension of size $(length(first(axs))).")
    end
    return to_indices(A, tail(axs), args)
end
# TODO should we just drop trailing arguments if they are integers?
# - trailing slices increase the output dimension but everything else is just dropped from the
# user's perspective
@propagate_inbounds function to_indices(A, ::Tuple{}, args::Tuple{I,Vararg{Any}}) where {I}
    return (to_index(OneTo(1), first(args)), to_indices(A, (), tail(args))...)
end
to_indices(A, axs::Tuple{}, args::Tuple{}) = ()

"""
    to_index([::IndexStyle, ]axis, arg) -> index

Convert the argument `arg` that was originally passed to `getindex` for the dimension
corresponding to `axis` into a form for native indexing (`Int`, Vector{Int}, etc.). New
axis types with unique behavior should use an `IndexStyle` trait:

```julia
to_index(axis::MyAxisType, arg) = to_index(IndexStyle(axis), axis, arg)
to_index(::MyIndexStyle, axis, arg) = ...
```
"""
@propagate_inbounds to_index(axis, arg) = to_index(IndexStyle(axis), axis, arg)
function to_index(s, axis, arg)
    throw(ArgumentError("invalid index: IndexStyle $s does not support indices of " *
                        "type $(typeof(arg)) for instances of type $(typeof(axis))."))
end
to_index(::IndexLinear, axis, arg::Colon) = indices(axis) # Colons get converted to slices by `indices`
to_index(::IndexLinear, axis, arg::CartesianIndices{0}) = arg
to_index(::IndexLinear, axis, arg::CartesianIndices{1}) = axes(arg, 1)
@propagate_inbounds function to_index(::IndexLinear, axis, arg::AbstractCartesianIndex{1})
    return to_index(axis, first(Tuple(arg)))
end
@propagate_inbounds function to_index(::IndexLinear, x, arg::Union{Array{Bool}, BitArray})
    @boundscheck checkbounds(x, arg)
    return LogicalIndex{Int}(arg)
end
@propagate_inbounds function to_index(::IndexLinear, x, arg::AbstractArray{<:AbstractCartesianIndex})
    @boundscheck checkbounds(x, arg) # _multi_check_index(axes(x), arg) || throw(BoundsError(x, arg))
    return arg
end
@propagate_inbounds function to_index(::IndexLinear, x, arg::LogicalIndex)
    @boundscheck checkbounds(Bool, x, arg) || throw(BoundsError(x, arg))
    return arg
end
@propagate_inbounds function to_index(::IndexLinear, x, arg::Integer)
    @boundscheck checkindex(Bool, indices(x), arg) || throw(BoundsError(x, arg))
    return _int(arg)
end
@propagate_inbounds function to_index(::IndexLinear, axis, arg::AbstractArray{Bool})
    @boundscheck checkbounds(axis, arg)
    return LogicalIndex(arg)
end
@propagate_inbounds function to_index(::IndexLinear, x, arg::AbstractArray{<:Integer})
    @boundscheck checkindex(Bool, x, arg) || throw(BoundsError(x, arg))
    return arg
end
@propagate_inbounds function to_index(::IndexLinear, x, arg::AbstractRange{Integer})
    @boundscheck checkindex(Bool, indices(axis), arg) || throw(BoundsError(axis, arg))
    return static_first(arg):static_step(arg):static_last(arg)
end

## IndexCartesian ##
to_index(::IndexCartesian, x, arg::Colon) = CartesianIndices(x)
to_index(::IndexCartesian, x, arg::CartesianIndices{0}) = arg
to_index(::IndexCartesian, x, arg::AbstractCartesianIndex) = arg
function to_index(::IndexCartesian, x, arg)
    @boundscheck checkbounds(x, arg) # _multi_check_index(axes(x), arg) || throw(BoundsError(x, arg))
    return arg
end
@propagate_inbounds function to_index(::IndexCartesian, x, arg::AbstractArray{<:AbstractCartesianIndex})
    @boundscheck _multi_check_index(axes(x), arg) || throw(BoundsError(x, arg))
    return arg
end
@propagate_inbounds function to_index(::IndexCartesian, x, arg::AbstractArray{Bool})
    @boundscheck checkbounds(x, arg)
    return LogicalIndex(arg)
end

function _multi_check_index(axs::Tuple, arg::AbstractArray{T}) where {T<:AbstractCartesianIndex}
    b = true
    for i in arg
        b &= Base.checkbounds_indices(Bool, axs, (i,))
    end
    return b
end

@propagate_inbounds function to_index(::IndexCartesian, x, arg::Union{Array{Bool}, BitArray})
    @boundscheck checkbounds(x, arg)
    return LogicalIndex{Int}(arg)
end
"""
    to_axes(A, inds)

Construct new axes given the corresponding `inds` constructed after
`to_indices(A, args) -> inds`. This method iterates through each pair of axes and
indices calling [`to_axis`](@ref).
"""
@inline function to_axes(A, inds::Tuple)
    return to_axes(A, axes(A), inds)
    #= TODO Delete?
    if ndims(A) === 1
        return (to_axis(axes(A, 1), first(inds)),)
    elseif is_linear_indexing(A, inds)
        return (to_axis(eachindex(IndexLinear(), A), first(inds)),)
    else
        return to_axes(A, axes(A), inds)
    end
    =#
end
to_axes(A, a::Tuple, i::Tuple{I,Vararg{Any}},) where {I} = _to_axes(argdims(A, I), A, a, i)
# drop this dimension
_to_axes(::StaticInt{0}, A, axs::Tuple, inds::Tuple) = to_axes(A, tail(inds), tail(inds))
function _to_axes(::StaticInt{1}, A, axs::Tuple, inds::Tuple)
    return (to_axis(first(axs), first(inds)), to_axes(A, tail(axs), tail(inds))...)
end
@propagate_inbounds function _to_axes(::StaticInt{N}, A, axs::Tuple, inds::Tuple) where {N}
    axes_front, axes_tail = Base.IteratorsMD.split(axs, Val(N))
    return (
        to_axis(_layout_indices(IndexStyle(A), axes_front), first(inds)),
        to_axes(A, axes_tail, tail(inds))...
    )
end
to_axes(A, ::Tuple{Ax,Vararg{Any}}, ::Tuple{}) where {Ax} = ()
to_axes(A, ::Tuple{}, ::Tuple{}) = ()

"""
    to_axis(old_axis, index) -> new_axis

Construct an `new_axis` for a newly constructed array that corresponds to the
previously executed `to_index(old_axis, arg) -> index`. `to_axis` assumes that
`index` has already been confirmed to be in bounds. The underlying indices of
`new_axis` begins at one and extends the length of `index` (i.e., one-based indexing).
"""
@inline function to_axis(axis, inds)
    if !can_change_size(axis) &&
       (known_length(inds) !== nothing && known_length(axis) === known_length(inds))
        return axis
    else
        return to_axis(IndexStyle(axis), axis, inds)
    end
end

# don't need to check size b/c slice means it's the entire axis
@inline function to_axis(axis, inds::Slice)
    if can_change_size(axis)
        return copy(axis)
    else
        return axis
    end
end
to_axis(S::IndexLinear, axis, inds) = StaticInt(1):static_length(inds)

################
### getindex ###
################
"""
    ArrayInterface.getindex(A, args...)

Retrieve the value(s) stored at the given key or index within a collection. Creating
another instance of `ArrayInterface.getindex` should only be done by overloading `A`.
Changing indexing based on a given argument from `args` should be done through,
[`to_index`](@ref), or [`to_axis`](@ref).
"""
@propagate_inbounds getindex(A, args...) = _getindex(A, args)
@propagate_inbounds function getindex(A; kwargs...)
    if isempty(kwargs.data)
        @boundscheck ndims(A) > 0 && throw(BoundsError(A, ()))
        return unsafe_get_element(A, NDIndex{0}())
    else
        return getindex(A, order_named_inds(dimnames(A), kwargs.data)...)
    end
end
@propagate_inbounds function _getindex(A, args::Tuple{Arg,Vararg{Any}}) where {Arg}
    lyt = layout(A)
    return unsafe_getindex(A, lyt, to_indices(lyt, args))
end
@propagate_inbounds function _getindex(A, args::Tuple{Arg}) where {Arg}
    lyt = layout(A, first(args))
    return unsafe_getindex(A, lyt, to_indices(lyt, args))
end

@propagate_inbounds getindex(x::Tuple, i::Int) = getfield(x, i)
@propagate_inbounds getindex(x::Tuple, ::StaticInt{i}) where {i} = getfield(x, i)

## unsafe_getindex ##
unsafe_getindex(A, i::Tuple) = unsafe_getindex(A, layout(A), i)
unsafe_getindex(A, lyt, i::Tuple) = _unsafe_getindex(_is_element_index(i), A, lyt, i)
_unsafe_getindex(::False, A, lyt, i::Tuple) = unsafe_get_collection(A, lyt, i)
_unsafe_getindex(::True, A, lyt, i::Tuple) = __unsafe_getindex(A, lyt, i)
__unsafe_getindex(A, lyt, i::Tuple{}) = unsafe_get_element(A, NDIndex{0}())
__unsafe_getindex(A, lyt, i::Tuple{Any}) = unsafe_get_element(A, unsafe_get_element(lyt, first(i)))
__unsafe_getindex(A, lyt, i::Tuple{Any,Vararg{Any}}) = unsafe_get_element(A, unsafe_get_element(lyt, NDIndex(i)))

"""
    unsafe_get_element(A::AbstractArray{T}, inds::Tuple) -> T

Returns an element of `A` at the indices `inds`. This method assumes all `inds`
have been checked for being in bounds. Any new array type using `ArrayInterface.getindex`
must define `unsafe_get_element(::NewArrayType, inds)`.
"""
unsafe_get_element(a::A, inds) where {A} = _unsafe_get_element(has_parent(A), a, inds)
_unsafe_get_element(::True, a, inds) = unsafe_get_element(parent(a), inds)
_unsafe_get_element(::False, a, inds) = @inbounds(a[inds])
_unsafe_get_element(::False, a::AbstractArray2, i) = unsafe_get_element_error(a, i)

unsafe_get_element(x::Ptr{T}, i::Int) where {T} = unsafe_load(x, Int(i))::T
unsafe_get_element(x::Ref, i::Integer) = unsafe_get_element(pointer(x), Int(i))

## Array ##
unsafe_get_element(A::Array, ::AbstractCartesianIndex{0}) = Base.arrayref(false, A, 1)
unsafe_get_element(A::Array, i::Integer) = Base.arrayref(false, A, Int(i))
function unsafe_get_element(A::Array, i::AbstractCartesianIndex)
    return unsafe_get_element(A, unsafe_get_element(LinearIndices(A), i))
end

## LinearIndices ##
unsafe_get_element(A::LinearIndices, i::Integer) = Int(i)
@inline function unsafe_get_element(x::LinearIndices, i::AbstractCartesianIndex)
    ii = Tuple(i)
    o = offsets(x)
    s = size(x)
    return first(ii) + (offset1(x) - first(o)) + _subs2int(first(s), tail(s), tail(o), tail(ii))
end
@inline function _subs2int(stride, s::Tuple{Any,Vararg}, o::Tuple{Any,Vararg}, inds::Tuple{Any,Vararg})
    i = ((first(inds) - first(o)) * stride)
    return i + _subs2int(stride * first(s), tail(s), tail(o), tail(inds))
end
@inline function _subs2int(stride, s::Tuple{Any}, o::Tuple{Any}, inds::Tuple{Any})
    return (first(inds) - first(o)) * stride
end
# trailing inbounds can only be 1 or 1:1
_subs2int(stride, ::Tuple{}, ::Tuple{}, ::Tuple{Any}) = static(0)

## StrideIndices ##
unsafe_get_element(x::StrideIndices, i::Integer) = _int(i)
@inline function unsafe_get_element(x::StrideIndices, i::AbstractCartesianIndex)
    return _strides2int(offsets(x), strides(x), Tuple(i)) + offset1(x)
end
@inline function _strides2int(o::Tuple, s::Tuple, i::Tuple)
    return ((first(i) - first(o)) * first(s)) + _strides2int(tail(o), tail(s), tail(i))
end
_strides2int(::Tuple{}, ::Tuple{}, ::Tuple{}) = static(0)

## CartesianIndices ##
unsafe_get_element(A::CartesianIndices, i::NDIndex) = CartesianIndex(i)
function unsafe_get_element(x::CartesianIndices, i::Integer)
    return NDIndex(_int2subs(offsets(x), size(x), i - offset1(x)))
end
@inline function _int2subs(o::Tuple{Any,Vararg{Any}}, s::Tuple{Any,Vararg{Any}}, i)
    len = first(s)
    inext = div(i, len)
    return (_int(i - len * inext + first(o)), _int2subs(tail(o), tail(s), inext)...)
end
@inline _int2subs(o::Tuple{Any}, s::Tuple{Any}, i) = _int(i + first(o))

unsafe_get_element(A::ReshapedArray, i::Integer) = unsafe_get_element(parent(A), i)
function unsafe_get_element(A::ReshapedArray, i::NDIndex)
    return unsafe_get_element(parent(A), to_index(IndexLinear(), A, i))
end

unsafe_get_element(A::SubArray, i) = @inbounds(A[i])
function unsafe_get_element_error(@nospecialize(A), @nospecialize(i))
    throw(MethodError(unsafe_get_element, (A, i)))
end

# This is based on Base._unsafe_getindex from https://github.com/JuliaLang/julia/blob/c5ede45829bf8eb09f2145bfd6f089459d77b2b1/base/multidimensional.jl#L755.
"""
    unsafe_get_collection(A, inds)

Returns a collection of `A` given `inds`. `inds` is assumed to have been bounds-checked.
"""
function unsafe_get_collection(A, lyt, inds)
    axs = to_axes(lyt, inds)
    dst = similar(A, axs)
    map(Base.unsafe_length, axes(dst)) != map(Base.unsafe_length, axs) || Base.throw_checksize_error(dst, axs)
    # usually a generated function, don't allow it to impact inference result
    _unsafe_get_index!(lyt, dst, A, inds...)
    return dst
end

function unsafe_get_collection(A, lyt::StrideIndices, inds)
    axs = to_axes(lyt, inds)
    dst = similar(A, axs)
    map(Base.unsafe_length, axes(dst)) == map(Base.unsafe_length, axs) || Base.throw_checksize_error(dst, axs)
    # usually a generated function, don't allow it to impact inference result
    _unsafe_get_stride_index!(lyt, dst, buffer(A), inds...)
    return dst
end

function _generate_unsafe_get_stride_index!_body(N::Int)
    quote
        Base.@_inline_meta
        D = eachindex(dst)
        Dy = iterate(D)
        @inbounds Base.Cartesian.@nloops $N j d -> I[d] begin
            # This condition is never hit, but at the moment
            # the optimizer is not clever enough to split the union without it
            Dy === nothing && return dst
            (idx, state) = Dy
            i = unsafe_get_element(lyt, NDIndex(Base.Cartesian.@ntuple($N, j)))
            dst[idx] = unsafe_get_element(src, i)
            Dy = iterate(D, state)
        end
        return dst
    end
end
@generated function _unsafe_get_stride_index!(lyt::StrideIndices{N}, dst, src, I::Vararg{Any,N}) where {N}
    return _generate_unsafe_get_stride_index!_body(N)
end

function _generate_unsafe_get_index!_body(N::Int)
    quote
        Base.@_inline_meta
        D = eachindex(dst)
        Dy = iterate(D)
        @inbounds Base.Cartesian.@nloops $N j d -> I[d] begin
            # This condition is never hit, but at the moment
            # the optimizer is not clever enough to split the union without it
            Dy === nothing && return dst
            (idx, state) = Dy
            dst[idx] = unsafe_get_element(src, NDIndex(Base.Cartesian.@ntuple($N, j)))
            Dy = iterate(D, state)
        end
        return dst
    end
end
@generated function _unsafe_get_index!(dst, src, I::Vararg{Any,N}) where {N}
    return _generate_unsafe_get_index!_body(N)
end

_ints2range(x::Integer) = x:x
_ints2range(x::AbstractRange) = x
@inline function unsafe_get_collection(x::CartesianIndices{N,A}, ::CartesianIndices{N,A}, inds) where {N,A}
    if (length(inds) === 1 && N > 1) || stride_preserving_index(typeof(inds)) === False()
        return Base._getindex(IndexStyle(x), x, inds...)  # FIXME
    else
        return CartesianIndices(to_axes(x, _ints2range.(inds)))
    end
end

@inline function unsafe_get_collection(x::LinearIndices{N,A}, lyt::AbstractRange, i) where {N,A}
    return @inbounds(lyt[i...])
end
@inline function unsafe_get_collection(x::LinearIndices{N,A}, ::LinearIndices{N,A}, i) where {N,A}
    if stride_preserving_index(typeof(i)) === True()
        return LinearIndices(to_axes(x, _ints2range.(i)))
    else
        return Base._getindex(IndexStyle(x), x, i...)  # FIXME
    end
end

#################
### setindex! ###
#################
"""
    ArrayInterface.setindex!(A, args...)

Store the given values at the given key or index within a collection.
"""
@propagate_inbounds setindex!(A, v, args...) = _setindex!(A, v, args)
@propagate_inbounds function setindex!(A, v; kwargs...)
    if isempty(kwargs.data)
        @boundscheck ndims(A) > 0 && throw(BoundsError(A, ()))
        return unsafe_set_element!(A, v, NDIndex{0}())
    else
        return setindex!(A, v, order_named_inds(dimnames(A), kwargs.data)...)
    end
end
@propagate_inbounds function _setindex!(A, v, args::Tuple{Arg,Vararg{Any}}) where {Arg}
    lyt = layout(A)
    return unsafe_setindex!(A, lyt, v, to_indices(lyt, args))
end
@propagate_inbounds function _setindex!(A, v, args::Tuple{Arg}) where {Arg}
    lyt = layout(A, first(args))
    return unsafe_setindex!(A, lyt, v, to_indices(lyt, args))
end

unsafe_setindex!(A, v, inds::Tuple) = unsafe_setindex!(A, layout(A), v, inds)
unsafe_setindex!(A, lyt, v, inds::Tuple) = _unsafe_setindex!(_is_element_index(inds), A, lyt, v, inds)
_unsafe_setindex!(::False, A, lyt, v, inds::Tuple) = unsafe_set_collection!(A, lyt, v, inds)
_unsafe_setindex!(::True, A, lyt, v, inds::Tuple) = __unsafe_setindex!(A, lyt, v, inds)
__unsafe_setindex!(A, lyt, v, inds::Tuple{}) = unsafe_set_element!(A, v, NDIndex{0}())
__unsafe_setindex!(A, lyt, v, inds::Tuple{Any}) = unsafe_set_element!(A, v, unsafe_get_element(lyt, first(inds)))
__unsafe_setindex!(A, lyt, v, inds::Tuple{Any,Vararg{Any}}) = unsafe_set_element!(A, v, unsafe_get_element(lyt, NDIndex(inds)))

"""
    unsafe_set_element!(A, val, inds::Tuple)

Sets an element of `A` to `val` at indices `inds`. This method assumes all `inds`
have been checked for being in bounds. Any new array type using `ArrayInterface.setindex!`
must define `unsafe_set_element!(::NewArrayType, val, inds)`.
"""
unsafe_set_element!(a, val, inds) = _unsafe_set_element!(has_parent(a), a, val, inds)
_unsafe_set_element!(::True, a, val, inds) = unsafe_set_element!(parent(a), val, inds)
_unsafe_set_element!(::False, a, val, inds) = @inbounds(parent(a)[inds] = val)

function _unsafe_set_element!(::False, a::AbstractArray2, val, inds)
    unsafe_set_element_error(a, val, inds)
end
unsafe_set_element_error(A, v, i) = throw(MethodError(unsafe_set_element!, (A, v, i)))

function unsafe_set_element!(A::Array{T}, val, ::AbstractCartesianIndex{0}) where {T}
    return Base.arrayset(false, A, convert(T, val)::T, 1)
end
function unsafe_set_element!(A::Array{T}, val, i::Integer) where {T}
    return Base.arrayset(false, A, convert(T, val)::T, Int(i))
end

# This is based on Base._unsafe_setindex!.
"""
    unsafe_set_collection!(A, val, inds)

Sets `inds` of `A` to `val`. `inds` is assumed to have been bounds-checked.
"""
@inline unsafe_set_collection!(A, lyt, v, i) = _unsafe_setindex!(A, v, i...)

function _generate_unsafe_setindex!_body(N::Int)
    quote
        x′ = Base.unalias(A, x)
        Base.Cartesian.@nexprs $N d -> (I_d = Base.unalias(A, I[d]))
        idxlens = Base.Cartesian.@ncall $N Base.index_lengths I
        Base.Cartesian.@ncall $N Base.setindex_shape_check x′ (d -> idxlens[d])
        Xy = iterate(x′)
        @inbounds Base.Cartesian.@nloops $N i d->I_d begin
            # This is never reached, but serves as an assumption for
            # the optimizer that it does not need to emit error paths
            Xy === nothing && break
            (val, state) = Xy
            unsafe_set_element!(A, val, NDIndex(Base.Cartesian.@ntuple($N, i)))
            Xy = iterate(x′, state)
        end
        A
    end
end
@generated function _unsafe_setindex!(A, x, I::Vararg{Any,N}) where {N}
    return _generate_unsafe_setindex!_body(N)
end

