"""
```julia
vsum(A; dims, multithreaded=:auto)
```
Summate the values contained in `A`, optionally over dimensions specified by `dims`.
As `Base.sum`, but vectorized and (optionally) multithreaded.

## Examples
```julia
julia> using VectorizedStatistics

julia> A = [1 2; 3 4]
2×2 Matrix{Int64}:
 1  2
 3  4

julia> vsum(A, dims=1)
1×2 Matrix{Int64}:
 4  6

julia> vsum(A, dims=2)
2×1 Matrix{Int64}:
 3
 7
```
"""
function vsum(A; dims=:, multithreaded=:auto)
    if (multithreaded===:auto && length(A) > 4095) || multithreaded===true
        _vtsum(A, dims)
    else
        _vsum(A, dims)
    end
end
vtsum(A; dims=:) = _vtsum(A, dims)
export vsum


## Singlethreaded implementation
# Reduce one dim
_vsum(A, dims::Int) = _vsum(A, (dims,))

# Reduce some dims
function _vsum(A::AbstractArray{T,N}, dims::Tuple) where {T,N}
    sᵢ = size(A)
    sₒ = ntuple(Val(N)) do d
        ifelse(d ∈ dims, 1, sᵢ[d])
    end
    Tₒ = Base.promote_op(+, T, Int)
    B = similar(A, Tₒ, sₒ)
    _vsum!(B, A, dims)
end

# Reduce all the dims!
function _vsum(A, ::Colon)
    # Promote type of accumulator to avoid overflow
    Tₒ = Base.promote_op(+, eltype(A), Int)
    Σ = zero(Tₒ)
    @turbo for i ∈ eachindex(A)
        Σ += A[i]
    end
    return Σ
end


# Chris Elrod metaprogramming magic:
# Generate customized set of loops for a given ndims and a vector
# `static_dims` of dimensions to reduce over
function staticdim_sum_quote(static_dims::Vector{Int}, N::Int)
  M = length(static_dims)
  # `static_dims` now contains every dim we're taking the sum over.
  Bᵥ = Expr(:call, :view, :B)
  reduct_inds = Int[]
  nonreduct_inds = Int[]
  # Firstly, build our expressions for indexing each array
  Aind = :(A[])
  Bind = :(Bᵥ[])
  inds = Vector{Symbol}(undef, N)
  for n ∈ 1:N
    ind = Symbol(:i_,n)
    inds[n] = ind
    push!(Aind.args, ind)
    if n ∈ static_dims
      push!(reduct_inds, n)
      push!(Bᵥ.args, :(firstindex(B,$n)))
    else
      push!(nonreduct_inds, n)
      push!(Bᵥ.args, :)
      push!(Bind.args, ind)
    end
  end
  # Secondly, build up our set of loops
  if !isempty(nonreduct_inds)
    firstn = first(nonreduct_inds)
    block = Expr(:block)
    loops = Expr(:for, :($(inds[firstn]) = indices((A,B),$firstn)), block)
    if length(nonreduct_inds) > 1
      for n ∈ @view(nonreduct_inds[2:end])
        newblock = Expr(:block)
        push!(block.args, Expr(:for, :($(inds[n]) = indices((A,B),$n)), newblock))
        block = newblock
      end
    end
    rblock = block
    # Push more things here if you want them at the beginning of the reduction loop
    push!(rblock.args, :(Σ = zero(eltype(Bᵥ))))
    # Build the reduction loop
    for n ∈ reduct_inds
      newblock = Expr(:block)
      push!(block.args, Expr(:for, :($(inds[n]) = axes(A,$n)), newblock))
      block = newblock
    end
    # Push more things here if you want them in the innermost loop
    push!(block.args, :(Σ += $Aind))
    # Push more things here if you want them at the end of the reduction loop
    push!(rblock.args, :($Bind = Σ))
    # Put it all together
    return quote
      Bᵥ = $Bᵥ
      @turbo $loops
      return B
    end
  else
    firstn = first(reduct_inds)
    block = Expr(:block)
    loops = Expr(:for, :($(inds[firstn]) = axes(A,$firstn)), block)
    # Build the reduction loop
    if length(reduct_inds) > 1
      for n ∈ @view(reduct_inds[2:end])
        newblock = Expr(:block)
        push!(block.args, Expr(:for, :($(inds[n]) = axes(A,$n)), newblock))
        block = newblock
      end
    end
    # Push more things here if you want them in the innermost loop
    push!(block.args, :(Σ += $Aind))
    # Put it all together
    return quote
      Bᵥ = $Bᵥ
      Σ = zero(eltype(Bᵥ))
      @turbo $loops
      Bᵥ[] = Σ
      return B
    end
  end
end

# Chris Elrod metaprogramming magic:
# Turn non-static integers in `dims` tuple into `StaticInt`s
# so we can construct `static_dims` vector within @generated code
function branches_sum_quote(N::Int, M::Int, D)
  static_dims = Int[]
  for m ∈ 1:M
    param = D.parameters[m]
    if param <: StaticInt
      new_dim = _dim(param)::Int
      @assert new_dim ∉ static_dims
      push!(static_dims, new_dim)
    else
      t = Expr(:tuple)
      for n ∈ static_dims
        push!(t.args, :(StaticInt{$n}()))
      end
      q = Expr(:block, :(dimm = dims[$m]))
      qold = q
      ifsym = :if
      for n ∈ 1:N
        n ∈ static_dims && continue
        tc = copy(t)
        push!(tc.args, :(StaticInt{$n}()))
        qnew = Expr(ifsym, :(dimm == $n), :(return _vsum!(B, A, $tc)))
        for r ∈ m+1:M
          push!(tc.args, :(dims[$r]))
        end
        push!(qold.args, qnew)
        qold = qnew
        ifsym = :elseif
      end
      # Else, if dimm ∉ 1:N, drop it from list and continue
      tc = copy(t)
      for r ∈ m+1:M
        push!(tc.args, :(dims[$r]))
      end
      push!(qold.args, Expr(:block, :(return _vsum!(B, A, $tc))))
      return q
    end
  end
  return staticdim_sum_quote(static_dims, N)
end

# Efficient @generated in-place sum
@generated function _vsum!(B::AbstractArray{Tₒ,N}, A::AbstractArray{T,N}, dims::D) where {Tₒ,T,N,M,D<:Tuple{Vararg{Integer,M}}}
  branches_sum_quote(N, M, D)
end
@generated function _vsum!(B::AbstractArray{Tₒ,N}, A::AbstractArray{T,N}, dims::Tuple{}) where {Tₒ,T,N}
  :(copyto!(B, A); return B)
end

## As above, but multithreaded
# Reduce one dim
_vtsum(A, dims::Int) = _vtsum(A, (dims,))

# Reduce some dims
function _vtsum(A::AbstractArray{T,N}, dims::Tuple) where {T,N}
    sᵢ = size(A)
    sₒ = ntuple(Val(N)) do d
        ifelse(d ∈ dims, 1, sᵢ[d])
    end
    Tₒ = Base.promote_op(+, T, Int)
    B = similar(A, Tₒ, sₒ)
    _vtsum!(B, A, dims)
end

# Reduce all the dims!
function _vtsum(A, ::Colon)
    # Promote type of accumulator to avoid overflow
    Tₒ = Base.promote_op(+, eltype(A), Int)
    Σ = zero(Tₒ)
    @tturbo for i ∈ eachindex(A)
        Σ += A[i]
    end
    return Σ
end


# Chris Elrod metaprogramming magic:
# Generate customized set of loops for a given ndims and a vector
# `static_dims` of dimensions to reduce over
function staticdim_tsum_quote(static_dims::Vector{Int}, N::Int)
  M = length(static_dims)
  # `static_dims` now contains every dim we're taking the sum over.
  Bᵥ = Expr(:call, :view, :B)
  reduct_inds = Int[]
  nonreduct_inds = Int[]
  # Firstly, build our expressions for indexing each array
  Aind = :(A[])
  Bind = :(Bᵥ[])
  inds = Vector{Symbol}(undef, N)
  for n ∈ 1:N
    ind = Symbol(:i_,n)
    inds[n] = ind
    push!(Aind.args, ind)
    if n ∈ static_dims
      push!(reduct_inds, n)
      push!(Bᵥ.args, :(firstindex(B,$n)))
    else
      push!(nonreduct_inds, n)
      push!(Bᵥ.args, :)
      push!(Bind.args, ind)
    end
  end
  # Secondly, build up our set of loops
  if !isempty(nonreduct_inds)
    firstn = first(nonreduct_inds)
    block = Expr(:block)
    loops = Expr(:for, :($(inds[firstn]) = indices((A,B),$firstn)), block)
    if length(nonreduct_inds) > 1
      for n ∈ @view(nonreduct_inds[2:end])
        newblock = Expr(:block)
        push!(block.args, Expr(:for, :($(inds[n]) = indices((A,B),$n)), newblock))
        block = newblock
      end
    end
    rblock = block
    # Push more things here if you want them at the beginning of the reduction loop
    push!(rblock.args, :(Σ = zero(eltype(Bᵥ))))
    # Build the reduction loop
    for n ∈ reduct_inds
      newblock = Expr(:block)
      push!(block.args, Expr(:for, :($(inds[n]) = axes(A,$n)), newblock))
      block = newblock
    end
    # Push more things here if you want them in the innermost loop
    push!(block.args, :(Σ += $Aind))
    # Push more things here if you want them at the end of the reduction loop
    push!(rblock.args, :($Bind = Σ))
    # Put it all together
    return quote
      Bᵥ = $Bᵥ
      @tturbo $loops
      return B
    end
  else
    firstn = first(reduct_inds)
    block = Expr(:block)
    loops = Expr(:for, :($(inds[firstn]) = axes(A,$firstn)), block)
    # Build the reduction loop
    if length(reduct_inds) > 1
      for n ∈ @view(reduct_inds[2:end])
        newblock = Expr(:block)
        push!(block.args, Expr(:for, :($(inds[n]) = axes(A,$n)), newblock))
        block = newblock
      end
    end
    # Push more things here if you want them in the innermost loop
    push!(block.args, :(Σ += $Aind))
    # Put it all together
    return quote
      Bᵥ = $Bᵥ
      Σ = zero(eltype(Bᵥ))
      @tturbo $loops
      Bᵥ[] = Σ
      return B
    end
  end
end

# Chris Elrod metaprogramming magic:
# Turn non-static integers in `dims` tuple into `StaticInt`s
# so we can construct `static_dims` vector within @generated code
function branches_tsum_quote(N::Int, M::Int, D)
  static_dims = Int[]
  for m ∈ 1:M
    param = D.parameters[m]
    if param <: StaticInt
      new_dim = _dim(param)::Int
      @assert new_dim ∉ static_dims
      push!(static_dims, new_dim)
    else
      t = Expr(:tuple)
      for n ∈ static_dims
        push!(t.args, :(StaticInt{$n}()))
      end
      q = Expr(:block, :(dimm = dims[$m]))
      qold = q
      ifsym = :if
      for n ∈ 1:N
        n ∈ static_dims && continue
        tc = copy(t)
        push!(tc.args, :(StaticInt{$n}()))
        qnew = Expr(ifsym, :(dimm == $n), :(return _vtsum!(B, A, $tc)))
        for r ∈ m+1:M
          push!(tc.args, :(dims[$r]))
        end
        push!(qold.args, qnew)
        qold = qnew
        ifsym = :elseif
      end
      # Else, if dimm ∉ 1:N, drop it from list and continue
      tc = copy(t)
      for r ∈ m+1:M
        push!(tc.args, :(dims[$r]))
      end
      push!(qold.args, Expr(:block, :(return _vtmean!(B, A, $tc))))
      return q
    end
  end
  return staticdim_tsum_quote(static_dims, N)
end

# Efficient @generated in-place sum
@generated function _vtsum!(B::AbstractArray{Tₒ,N}, A::AbstractArray{T,N}, dims::D) where {Tₒ,T,N,M,D<:Tuple{Vararg{Integer,M}}}
  branches_tsum_quote(N, M, D)
end
@generated function _vtsum!(B::AbstractArray{Tₒ,N}, A::AbstractArray{T,N}, dims::Tuple{}) where {Tₒ,T,N}
  :(copyto!(B, A); return B)
end
##
