using Pkg
Pkg.activate(@__DIR__)
using LinearAlgebra, Random, BenchmarkTools, StatsBase
using JuMP, MosekTools
using Plots, LaTeXStrings
using CFMMRouter
const MOI = JuMP.MathOptInterface

function run_trial_router(n_pools, n_tokens, Rs, γ, As, ws, prices)
    pools = [
        ws[i] == 0.5 ? 
            ProductTwoCoin(Rs[:,i], γ, As[i]) :
            GeometricMeanTwoCoin(Rs[:,i], [ws[i]; 1.0 - ws[i]], γ, As[i])
        for i in 1:n_pools
    ]
    router = Router(
            LinearNonnegative(prices),
            pools,
            n_tokens
        )
    v0 = ones(n_tokens)
    
    GC.gc()
    trial = @timed begin route!(router; v=v0) end
    Ψ = round.(Int, netflows(router))
    return trial.time, Ψ
end

function run_trial_mosek(n_pools, n_tokens, Rs, γ, As, ws, prices)
    # construct model
    routing = Model(Mosek.Optimizer)
    set_silent(routing)
    @variable(routing, Ψ[1:n_tokens])
    Δ = [@variable(routing, [1:2]) for _ in 1:n_pools]
    Λ = [@variable(routing, [1:2]) for _ in 1:n_pools]

    # Construct pools
    for i in 1:n_pools
        Ri = Rs[:,i]
        ϕRi = sqrt(Ri[1]*Ri[2])
        @constraint(routing, vcat(Ri + γ * Δ[i] - Λ[i], ϕRi) in MOI.PowerCone(ws[i]))
        @constraint(routing, Δ[i] .≥ 0)
        @constraint(routing, Λ[i] .≥ 0)
    end

    # net trade constraint
    net_trade = zeros(AffExpr, n_tokens)
    for i in 1:n_pools
        @. net_trade[As[i]] += Λ[i] - Δ[i]
    end
    @constraint(routing, Ψ .== net_trade)

    # Objective: arbitrage
    @constraint(routing, Ψ .>= 0)
    c = rand(n_tokens)
    @objective(routing, Max, sum(c .* Ψ))

    GC.gc()
    optimize!(routing)
    time = solve_time(routing)
    status = termination_status(routing)
    status != MOI.OPTIMAL && @info "\t\tMosek termination status: $status"
    Ψv = round.(Int, value.(Ψ))
    return time, Ψv
end


function run_experiment(ns_pools, factors; rseed=0)
    # Random.seed!(rseed)
    time_router = zeros(length(ns_pools), length(factors))
    time_mosek = zeros(length(ns_pools), length(factors))
    obj_router = zeros(length(ns_pools), length(factors))
    obj_mosek = zeros(length(ns_pools), length(factors))

    for (i, n_pools) in enumerate(ns_pools)
        @info "Starting $n_pools"
        for (j, factor) in enumerate(factors)
            Random.seed!(rseed)
            n_tokens = round(Int, factor * sqrt(n_pools))
            γ = 0.997
            Rs = 1000 * rand(2, n_pools) .+ 1000
            ws = rand((0.5, 0.8), n_pools)
            As = [sample(collect(1:n_tokens), 2, replace=false) for i in 1:n_pools]
            prices = rand(n_tokens)
            
            tt, Ψ = run_trial_router(n_pools, n_tokens, Rs, γ, As, ws, prices)
            time_router[i, j] = tt
            obj_router[i, j] = dot(Ψ, prices)
            
            tt, Ψ = run_trial_mosek(n_pools, n_tokens, Rs, γ, As, ws, prices)
            time_mosek[i, j] = tt
            obj_mosek[i, j] = dot(Ψ, prices)
            @info "\tDone with $n_pools, $factor"
        end
    end

    return time_router, time_mosek, obj_router, obj_mosek
end


ns_pools = round.(Int, 10 .^ range(2, 5, 25))
# ns_pools = round.(Int, range(1e2, 10e4, 20))
factors = [2]
time_router, time_mosek, obj_router, obj_mosek = run_experiment(ns_pools, factors)
obj_diff = obj_router - obj_mosek

plt = plot(
    ns_pools,
    time_router,
    lw=3,
    # yaxis=:log,
    # xaxis=:log,
    title="Routing Solve Time",
    ylabel="Time (seconds)",
    xlabel="Number of Swap Pools (m)",
    label="CFMMRouter",
    dpi=300,
    xlims=(minimum(ns_pools), maximum(ns_pools)),
    # minorgrid=true,
    margin=3Plots.PlotMeasures.mm,
    legend=:topleft,
    right_margin=5Plots.mm,
    color=:blue
)
plot!(plt,
    ns_pools,
    time_mosek,
    label="Mosek",
    lw=3,
    color=:red
)
savefig(plt, joinpath(@__DIR__, "figs/solve-time-3.pdf"))

plt_obj = plot(
    ns_pools, 
    obj_router,
    title="Routing Objective",
    ylabel="Objective Value",
    xlabel="Number of Swap Pools (m)",
    # xaxis=:log,
    # yaxis=:log,
    xlims=(minimum(ns_pools), maximum(ns_pools)),
    lw=3,
    label="CFMMRouter",
    right_margin=15Plots.mm,
    color=:blue,
    legend=:topleft
)
plot!(plt_obj,
    ns_pools,
    obj_mosek,
    label="Mosek",
    lw=3,
    color=:red
)
plot!(twinx(),
    ns_pools,
    obj_diff ./ obj_mosek,
    xlims=(minimum(ns_pools), maximum(ns_pools)),
    legend=false,
    ylabel="Relative differnce",
    # xaxis=:log,
    lw=1,
    ls=:dash,
    color=:purple,
)
savefig(plt_obj, joinpath(@__DIR__, "figs/obj-diff.pdf"))