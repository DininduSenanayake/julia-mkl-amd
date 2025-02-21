using Random
using LinearAlgebra
using Libdl
using BenchmarkTools
using DataFrames
using CSV

const NSAMPLES = 3
const NEVALS = 1
const FUNCS_SIZES = Dict(svd => [1000, 5000, 10000], eigen => [1000, 5000, 10000], cholesky => [5000, 10000, 50000], Base.:* => [5000, 10000, 50000],)
# const FUNCS_SIZES = Dict(svd => [10,50,100], eigen => [10,50,100], cholesky => [50,100,500], Base.:* => [50,100,500],)
# const FUNCS_SIZES = Dict(svd => [1000], eigen => [1000], cholesky => [5000], Base.:* => [5000],)
const BLASSTR = get(ARGS, 1, "OpenBLAS")
const PINNING = get(ARGS, 2, "unknown")

rand_hermitian(s1, s2) = Matrix(Hermitian(rand(s1, s2)))
rand_hermitian_posdef(s1, s2) = rand_hermitian(s1, s2) + max(s1, s2) * I(max(s1, s2))

function getblas()
    blaslib = basename(BLAS.get_config().loaded_libs[1].libname)
    if contains(blaslib, "openblas")
        return "OpenBLAS"
    elseif contains(blaslib, "mkl")
        mkl_workaround = any(contains("fake"), dllist())
        if mkl_workaround
            return "MKL faked"
        else
            return "MKL"
        end
    else
        return blaslib
    end
end

function bench(f, matsize)
    Random.seed!(42)
    if typeof(f) == typeof(*) # two inputs
        t = @belapsed $f(mat1, mat2) setup = (mat1 = rand($matsize, $matsize); mat2 = rand($matsize, $matsize)) samples = NSAMPLES evals = NEVALS
    elseif typeof(f) == typeof(cholesky) # hermitian + posdef input
        t = @belapsed $f(mat) setup = (mat = rand_hermitian_posdef($matsize, $matsize)) samples = NSAMPLES evals = NEVALS
    else # single input
        t = @belapsed $f(mat) setup = (mat = rand($matsize, $matsize)) samples = NSAMPLES evals = NEVALS
    end
    println("Min. runtime: ", t, "s ($f, $matsize)")
    return t
end

function run_benchsuite()
    df = DataFrame(f=String[], size=Int[], time=Float64[], BLAS=String[], pinning=String[])
    for (f, sizes) in FUNCS_SIZES
        for ms in sizes
            t = bench(f, ms)
            push!(df, (string(f), ms, t, getblas(), PINNING))
        end
    end
    return df
end

# main
t_start = time_ns()
println("JULIA VERSION = ", VERSION)
println("HOSTNAME = ", gethostname())
cpu_name = first(Sys.cpu_info()).model
println("CPU = ", cpu_name)
if contains(uppercase(BLASSTR),"MKL")
    using MKL
end
println("BLAS = ", getblas())
println("BLAS.get_num_threads() = ", BLAS.get_num_threads())
println("PINNING = ", PINNING)
df = run_benchsuite()
if isfile("results.csv") # concat if there are already results
    dfprev = DataFrame(CSV.File("results.csv"))
    df = vcat(dfprev, df)
end
CSV.write("results.csv", df)
Δt = (time_ns() - t_start) * 1e-9
println("Done ($(floor(Int, Δt / 60)) minutes and $(round(Δt % 60; digits=1)) seconds elapsed)\n")