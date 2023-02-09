using Pkg
Pkg.activate(@__DIR__)
using CFMMRouter
using JSON
using Plots

include("loadpools.jl")

function route_many(eth_to_liquidate, loaded_pools)
    @inline solved(router, v0) = !(isapprox(router.v[2], v0[2], atol=1e-1))

    cfmms, symbols, symb_to_index = loaded_pools

    Δin = zeros(length(symbols))
    Δin[2] = eth_to_liquidate
    
    # ["USDC", "WETH", "DAI", "USDT"]
    v0 = [1., 1_656., 1., 1.]

    router = Router(
        BasketLiquidation(symb_to_index("USDC"), Δin),
        cfmms,
        maximum([maximum(cfmm.Ai) for cfmm in cfmms]),
    )

    # Optimize!
    route!(router; v=v0, verbose=false, factr=1e1, pgtol=0, maxfun=15_000, maxiter=15_000)

    if !solved(router, v0)
        @show "Error for $eth_to_liquidate"
        @show router.v

        router = Router(
            BasketLiquidation(symb_to_index("USDC"), Δin),
            cfmms,
            maximum([maximum(cfmm.Ai) for cfmm in cfmms]),
        )
        route!(router; v=v0, verbose=false, m=15, factr=1e1, pgtol=0, maxfun=15_000, maxiter=15_000)
        
        @show router.v
        println("----------------")
    end

    Ψ = netflows(router)
    return solved(router, v0) ? Ψ[1] : NaN
end

route_one_pool(eth_to_liquidate, cfmm) = CFMMRouter.forward_trade([0.0, eth_to_liquidate], cfmm)

function run_experiment(eth_amount)
    # Multiple pools
    filepath = joinpath(@__DIR__, "data", "univ3_top_pools.json")
    loaded_pools = load_univ3_pools(filepath)
    usdc_routing = zeros(length(eth_amount))
    map!(amt -> route_many(amt, loaded_pools), usdc_routing, eth_amount)
    # usdc_routing = route_many.(eth_amount, loaded_pools)
    
    # Single pool
    filepath = joinpath(@__DIR__, "data", "univ3_one_pool.json")
    cfmm = load_univ3_pools(filepath)[1]
    usdc_single = route_one_pool.(eth_amount, cfmm)

    return usdc_routing, usdc_single
end


eth_amount = 10 .^ range(3, log10(100_000); length = 50)
usdc_routing, usdc_single = run_experiment(eth_amount)
surplus = usdc_routing .- usdc_single

price_plt = plot(
    eth_amount,
    usdc_routing ./ eth_amount,
    lw=3,
    fillalpha=0.5,
    title="Price Impact of Selling ETH",
    xaxis=:log,
    ylabel="Avg Price",
    xlabel="Sold ETH",
    legend=:bottomleft,
    label="CFMMRouter",
    dpi=300,
    color=:blue,
)
plot!(price_plt,
    eth_amount,
    usdc_single ./ eth_amount,
    lw=3,
    fillalpha=0.5,
    label="Single Pool",
    color=:red,
)
savefig(price_plt, joinpath(@__DIR__, "figs", "price_impact.pdf"))

routing_surplus_plt = plot(
    eth_amount,
    surplus,
    lw=3,
    title="Routing Surplus",
    ylabel="Surplus USDC",
    xlabel="Sold ETH",
    legend=false,
    dpi=300,
    color=:blue,
)
savefig(routing_surplus_plt, joinpath(@__DIR__, "figs", "routing_surplus.pdf"))
