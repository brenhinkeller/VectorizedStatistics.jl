# Test equivalence to Base/Stdlib

    # Test vmean
    for nd = 1:5
        @info "Testing vmean: $nd-dimensional arrays"
        # Generate random array
        A = rand((10 .+ (1:nd))...)

        # Test equivlalence when reducing over all dims
        @test vmean(A) ≈ mean(A)

        # Test equivalence when reducing over a single dimension
        for i = 1:nd
            @info "Testing vmean: reduction over dimension $i"
            @test vmean(A, dims=i) ≈ mean(A, dims=i)
        end

        # Test equivalence when reducing over two dimensions
        if nd > 1
            for i = 2:nd
                for j = 1:i
                    dims = (j,i)
                    @info "Testing vmean: reduction over dimensions $dims"
                    @test vmean(A, dims=dims) ≈ mean(A, dims=dims)
                end
            end
        end

    end


    # # Test vvar
    # for nd = 1:6
    #     @info "Testing vvar: $nd-dimensional arrays"
    #     # Generate random array
    #     A = randn((10 .+ (1:nd))...)
    #
    #     # Test equivlalence when reducing over all dims
    #     @test vvar(A, corrected=false) ≈ var(A, corrected=false)
    #
    #     # Test equivalence when reducing over a single dimension
    #     for i = 1:nd
    #         @info "Testing vvar: reduction over dimension $i"
    #         @test vvar(A, dims=i, corrected=false) ≈ var(A, dims=i, corrected=false)
    #     end
    #
    #     # Test equivalence when reducing over two dimensions
    #     if nd > 1
    #         for i = 2:nd
    #             for j = 1:i
    #                 dims = (j,i)
    #                 @info "Testing vvar: reduction over dimensions $dims"
    #                 @test vvar(A, dims=dims, corrected=false) ≈ var(A, dims=dims, corrected=false)
    #             end
    #         end
    #     end
    # end


    # # Test vstd
    # for nd = 1:6
    #     @info "Testing vstd: $nd-dimensional arrays"
    #     # Generate random array
    #     A = randn((10 .+ (1:nd))...)
    #
    #     # Test equivlalence when reducing over all dims
    #     @test vstd(A) ≈ std(A)
    #
    #     # Test equivalence when reducing over a single dimension
    #     for i = 1:nd
    #         @info "Testing vstd: reduction over dimension $i"
    #         @test vstd(A, dims=i) ≈ std(A, dims=i)
    #     end
    #
    #     # Test equivalence when reducing over two dimensions
    #     if nd > 1
    #         for i = 2:nd
    #             for j = 1:i
    #                 dims = (j,i)
    #                 @info "Testing vstd: reduction over dimensions $dims"
    #                 @test vstd(A, dims=dims) ≈ std(A, dims=dims)
    #             end
    #         end
    #     end
    # end