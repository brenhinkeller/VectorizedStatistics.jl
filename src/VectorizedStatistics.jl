module VectorizedStatistics

    using LoopVectorization, Static

    const IntOrStaticInt = Union{Integer, StaticInt}
    _dim(::Type{StaticInt{N}}) where {N} = N::Int

    # Implemented by reduction, recursively
    include("vreducibles.jl")

    # Implemented with @generated functions, single- and multithreaded
    include("vmean.jl")
    include("vsum.jl")
    include("vvar.jl")
    include("vstd.jl")
    include("vcov.jl")

    # Sorting-based statistics
    include("quicksort.jl")
    include("argsort.jl")
    include("vsort.jl")
    include("vmedian.jl")
    include("vquantile.jl")

    # Fully precompile some commonly-used methods
    using SnoopPrecompile
    include("precompile.jl")

end
