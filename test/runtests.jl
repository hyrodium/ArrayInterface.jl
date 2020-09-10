using ArrayInterface, Test
using Base: setindex
import ArrayInterface: has_sparsestruct, findstructralnz, fast_scalar_indexing, lu_instance, Static
@test ArrayInterface.ismutable(rand(3))

using Aqua
Aqua.test_all(ArrayInterface)

using StaticArrays
x = @SVector [1,2,3]
@test ArrayInterface.ismutable(x) == false
@test ArrayInterface.ismutable(view(x, 1:2)) == false
x = @MVector [1,2,3]
@test ArrayInterface.ismutable(x) == true
@test ArrayInterface.ismutable(view(x, 1:2)) == true
@test ArrayInterface.ismutable(1:10) == false
@test ArrayInterface.ismutable((0.1,1.0)) == false
@test ArrayInterface.ismutable(Base.ImmutableDict{Symbol,Int64}) == false
@test ArrayInterface.ismutable((;x=1)) == false

@test isone(ArrayInterface.known_first(typeof(StaticArrays.SOneTo(7))))
@test ArrayInterface.known_last(typeof(StaticArrays.SOneTo(7))) == 7
@test ArrayInterface.known_length(typeof(StaticArrays.SOneTo(7))) == 7

using LinearAlgebra, SparseArrays

D=Diagonal([1,2,3,4])
@test has_sparsestruct(D)
rowind,colind=findstructralnz(D)
@test [D[rowind[i],colind[i]] for i in 1:length(rowind)]==[1,2,3,4]
@test length(rowind)==4
@test length(rowind)==length(colind)

Bu = Bidiagonal([1,2,3,4], [7,8,9], :U)
@test has_sparsestruct(Bu)
rowind,colind=findstructralnz(Bu)
@test [Bu[rowind[i],colind[i]] for i in 1:length(rowind)]==[1,7,2,8,3,9,4]
Bl = Bidiagonal([1,2,3,4], [7,8,9], :L)
@test has_sparsestruct(Bl)
rowind,colind=findstructralnz(Bl)
@test [Bl[rowind[i],colind[i]] for i in 1:length(rowind)]==[1,7,2,8,3,9,4]

Tri=Tridiagonal([1,2,3],[1,2,3,4],[4,5,6])
@test has_sparsestruct(Tri)
rowind,colind=findstructralnz(Tri)
@test [Tri[rowind[i],colind[i]] for i in 1:length(rowind)]==[1,2,3,4,4,5,6,1,2,3]
STri=SymTridiagonal([1,2,3,4],[5,6,7])
@test has_sparsestruct(STri)
rowind,colind=findstructralnz(STri)
@test [STri[rowind[i],colind[i]] for i in 1:length(rowind)]==[1,2,3,4,5,6,7,5,6,7]

Sp=sparse([1,2,3],[1,2,3],[1,2,3])
@test has_sparsestruct(Sp)
rowind,colind=findstructralnz(Sp)
@test [Tri[rowind[i],colind[i]] for i in 1:length(rowind)]==[1,2,3]

@test ArrayInterface.ismutable(spzeros(1, 1))
@test ArrayInterface.ismutable(spzeros(1))


@test !fast_scalar_indexing(qr(rand(10, 10)).Q)
@test !fast_scalar_indexing(qr(rand(10, 10), Val(true)).Q)
@test !fast_scalar_indexing(lq(rand(10, 10)).Q)

using BandedMatrices

B=BandedMatrix(Ones(5,5), (-1,2))
B[band(1)].=[1,2,3,4]
B[band(2)].=[5,6,7]
@test has_sparsestruct(B)
rowind,colind=findstructralnz(B)
@test [B[rowind[i],colind[i]] for i in 1:length(rowind)]==[5,6,7,1,2,3,4]
B=BandedMatrix(Ones(4,6), (-1,2))
B[band(1)].=[1,2,3,4]
B[band(2)].=[5,6,7,8]
rowind,colind=findstructralnz(B)
@test [B[rowind[i],colind[i]] for i in 1:length(rowind)]==[5,6,7,8,1,2,3,4]

using BlockBandedMatrices
BB=BlockBandedMatrix(Ones(10,10),[1,2,3,4],[4,3,2,1],(1,0))
BB[Block(1,1)].=[1 2 3 4]
BB[Block(2,1)].=[5 6 7 8;9 10 11 12]
rowind,colind=findstructralnz(BB)
@test [BB[rowind[i],colind[i]] for i in 1:length(rowind)]==
    [1,5,9,2,6,10,3,7,11,4,8,12,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1]

dense=collect(Ones(8,8))
for i in 1:8
    dense[:,i].=[1,2,3,4,5,6,7,8]
end
BBB=BandedBlockBandedMatrix(dense, [4, 4] ,[4, 4], (1, 1), (1, 1))
rowind,colind=findstructralnz(BBB)
@test [BBB[rowind[i],colind[i]] for i in 1:length(rowind)]==
    [1,2,3,1,2,3,4,2,3,4,5,6,7,5,6,7,8,6,7,8,
     1,2,3,1,2,3,4,2,3,4,5,6,7,5,6,7,8,6,7,8]

@testset "setindex" begin
    @testset "$(typeof(x))" for x in [
        zeros(3),
        falses(3),
        spzeros(3),
    ]
        y = setindex(x, true, 1)
        @test iszero(x)  # x is not mutated
        @test y[1] == true
        @test iszero(x[CartesianIndices(size(x)) .== [CartesianIndex(1)]])

        y2 = setindex(x, one.(x), :)
        @test iszero(x)
        @test all(isone, y2)
    end

    @testset "$(typeof(x))" for x in [
        zeros(3, 3),
        falses(3, 3),
        spzeros(3, 3),
    ]
        y = setindex(x, true, 1, 1)
        @test iszero(x)  # x is not mutated
        @test y[1, 1] == true
        @test iszero(x[CartesianIndices(size(x)) .== [CartesianIndex(1, 1)]])

        y2 = setindex(x, one.(x), :, :)
        @test iszero(x)
        @test all(isone, y2)
    end

    @testset "$(typeof(x))" for x in [
        zeros(3, 3, 3),
        falses(3, 3, 3),
    ]
        y = setindex(x, true, 1, 1, 1)
        @test iszero(x)  # x is not mutated
        @test y[1, 1, 1] == true
        @test iszero(x[CartesianIndices(size(x)) .== [CartesianIndex(1, 1, 1)]])

        y2 = setindex(x, one.(x), :, :, :)
        @test iszero(x)
        @test all(isone, y2)
    end
end

using SuiteSparse
@testset "lu_instance" begin
  for A in [
    randn(5, 5),
    @SMatrix(randn(5, 5)),
    @MMatrix(randn(5, 5)),
    sprand(50, 50, 0.5)
  ]
    @test lu_instance(A) isa typeof(lu(A))
  end
  @test lu_instance(1) === 1
end

using Random
using ArrayInterface: issingular
@testset "issingular" begin
    for T in [Float64, ComplexF64]
        R = randn(MersenneTwister(2), T, 5, 5)
        S = Symmetric(R)
        L = UpperTriangular(R)
        U = LowerTriangular(R)
        @test all(!issingular, [R, S, L, U, U'])
        R[:, 2] .= 0
        @test all(issingular, [R, L, U, U'])
        @test !issingular(S)
        R[2, :] .= 0
        @test issingular(S)
        @test all(!issingular, [UnitLowerTriangular(R), UnitUpperTriangular(R), UnitUpperTriangular(R)'])
    end
end

using ArrayInterface: zeromatrix
@test zeromatrix(rand(4,4,4)) == zeros(4*4*4,4*4*4)

using ArrayInterface: parent_type
@testset "Parent Type" begin
    x = ones(4, 4)
    @test parent_type(view(x, 1:2, 1:2)) <: typeof(x)
    @test parent_type(reshape(x, 2, :)) <: typeof(x)
    @test parent_type(transpose(x)) <: typeof(x)
    @test parent_type(Symmetric(x)) <: typeof(x)
    @test parent_type(UpperTriangular(x)) <: typeof(x)
    @test parent_type(PermutedDimsArray(x, (2,1))) <: typeof(x)
    @test parent_type(Base.Slice(1:10)) <: UnitRange{Int}
end

@testset "Range Interface" begin
    @test isnothing(ArrayInterface.known_first(typeof(1:4)))
    @test isone(ArrayInterface.known_first(Base.OneTo(4)))
    @test isone(ArrayInterface.known_first(typeof(Base.OneTo(4))))

    @test isnothing(ArrayInterface.known_last(1:4))
    @test isnothing(ArrayInterface.known_last(typeof(1:4)))

    @test isnothing(ArrayInterface.known_step(typeof(1:0.2:4)))
    @test isone(ArrayInterface.known_step(1:4))
    @test isone(ArrayInterface.known_step(typeof(1:4)))
end

@testset "can_change_size" begin
    @test ArrayInterface.can_change_size([1])
    @test ArrayInterface.can_change_size(Vector{Int})
    @test ArrayInterface.can_change_size(Dict{Symbol,Any})
    @test !ArrayInterface.can_change_size(Base.ImmutableDict{Symbol,Int64})
    @test !ArrayInterface.can_change_size(Tuple{})
end

@testset "known_length" begin
    @test ArrayInterface.known_length(ArrayInterface.indices(SOneTo(7))) == 7
    @test ArrayInterface.known_length(1:2) == nothing
    @test ArrayInterface.known_length((1,)) == 1
    @test ArrayInterface.known_length((a=1,b=2)) == 2
    @test ArrayInterface.known_length([]) == nothing

    x = view(SArray{Tuple{3,3,3}}(ones(3,3,3)), :, SOneTo(2), 2)
    @test @inferred(ArrayInterface.known_length(x)) == 6
    @test @inferred(ArrayInterface.known_length(x')) == 6
end

@testset "indices" begin
    A23 = ones(2,3); SA23 = @SMatrix ones(2,3);
    A32 = ones(3,2); SA32 = @SMatrix ones(3,2);
    @test @inferred(ArrayInterface.indices((A23, A32))) == 1:6
    @test @inferred(ArrayInterface.indices((SA23, A32))) == 1:6
    @test @inferred(ArrayInterface.indices((A23, SA32))) == 1:6
    @test @inferred(ArrayInterface.indices((SA23, SA32))) == 1:6
    @test @inferred(ArrayInterface.indices(A23)) == 1:6
    @test @inferred(ArrayInterface.indices(SA23)) == 1:6
    @test @inferred(ArrayInterface.indices(A23, 1)) == 1:2
    @test @inferred(ArrayInterface.indices(SA23, Static(1))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((A23, A32), (1, 2))) == 1:2
    @test @inferred(ArrayInterface.indices((SA23, A32), (Static(1), 2))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((A23, SA32), (1, Static(2)))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((SA23, SA32), (Static(1), Static(2)))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((A23, A23), 1)) == 1:2
    @test @inferred(ArrayInterface.indices((SA23, SA23), Static(1))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((SA23, A23), Static(1))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((A23, SA23), Static(1))) === Base.Slice(Static(1):Static(2))
    @test @inferred(ArrayInterface.indices((SA23, SA23), Static(1))) === Base.Slice(Static(1):Static(2))
    @test_throws AssertionError ArrayInterface.indices((A23, ones(3, 3)), 1)
    @test_throws AssertionError ArrayInterface.indices((A23, ones(3, 3)), (1, 2))
    @test_throws AssertionError ArrayInterface.indices((SA23, ones(3, 3)), Static(1))
    @test_throws AssertionError ArrayInterface.indices((SA23, ones(3, 3)), (Static(1), 2))
    @test_throws AssertionError ArrayInterface.indices((SA23, SA23), (Static(1), Static(2)))
end

@testset "Static" begin
    @test iszero(Static(0))
    @test !iszero(Static(1))
    # test for ambiguities and correctness
    for i ∈ [Static(0), Static(1), Static(2), 3]
        for j ∈ [Static(0), Static(1), Static(2), 3]
            i === j === 3 && continue
            for f ∈ [+, -, *, ÷, %, <<, >>, >>>, &, |, ⊻, ==, ≤, ≥]
                (iszero(j) && ((f === ÷) || (f === %))) && continue # integer division error
                @test convert(Int, @inferred(f(i,j))) == f(convert(Int, i), convert(Int, j))
            end
        end
        i == 3 && break
        for f ∈ [+, -, *, /, ÷, %, ==, ≤, ≥]
            x = f(convert(Int, i), 1.4)
            y = f(1.4, convert(Int, i))
            @test convert(typeof(x), @inferred(f(i, 1.4))) === x
            @test convert(typeof(y), @inferred(f(1.4, i))) === y # if f is division and i === Static(0), returns `NaN`; hence use of ==== in check.
        end
    end
end

@testset "push, pushfirst, pop, popfirst, insert, deleteat" begin
    @test @inferred(ArrayInterface.push([1,2,3], 4)) == [1, 2, 3, 4]
    @test @inferred(ArrayInterface.pushfirst([2,3,4], 1)) == [1, 2, 3, 4]
    @test @inferred(ArrayInterface.pop([1, 2, 3, 4])) == [1, 2, 3]
    @test @inferred(ArrayInterface.popfirst([1, 2, 3, 4])) == [2, 3, 4]
    @test @inferred(ArrayInterface.insert([1,2,3], 2, -2)) == [1, -2, 2, 3]
    @test @inferred(ArrayInterface.deleteat([1, 2, 3], 2)) == [1, 3]
end

