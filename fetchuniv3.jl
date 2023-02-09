using Pkg
Pkg.activate(@__DIR__)
using Dates
using JSON, HTTP

@enum Mode begin
    pools_mode
    pool_mode
    ticks_mode
end

# Fetches UniV3 data from TheGraph
function get_uniswap_data(; mode=pools_mode, skip=0, pool_address=nothing, block=nothing)
    url = "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3"
    header = Dict("Content-Type" => "application/json")

    query = if mode == pools_mode

        block_modifier_query, block_modifier_pools = if !isnothing(block)
            "\$block:Int", "block: {number: \$block}"
        else
            "\$skip:Int", "skip: \$skip"
        end

        """
        query($block_modifier_query) {
            pools ($block_modifier_pools) {
                id
                tick
                token0 {
                    name
                    symbol
                    decimals
                }
                token1 {
                    name
                    symbol
                    decimals
                }
                token0Price
                token1Price
                feeTier
                totalValueLockedToken0
                totalValueLockedToken1
                totalValueLockedUSD
            }
        }
        """
    elseif mode == pool_mode
        block_modifier_query, block_modifier_pools = if !isnothing(block)
            raw"$block:Int, $poolAddress:String", raw"id: $poolAddress, block: {number: $block}"
        else
            raw"$poolAddress:String", raw"id: $poolAddress"
        end

        """
        query($block_modifier_query) {
            pool($block_modifier_pools) {
                id
                tick
                token0 {
                    name
                    symbol
                    decimals
                }
                token1 {
                    name
                    symbol
                    decimals
                }
                token0Price
                token1Price
                feeTier
                totalValueLockedToken0
                totalValueLockedToken1
                totalValueLockedUSD
            }
        }
        """
    elseif mode == ticks_mode
        block_modifier_query, block_modifier_pools = if !isnothing(block)
            raw"$skip:Int, $block:Int, $poolAddress:String", raw"block: {number: $block}, skip: $skip"
        else
            raw"$skip:Int, $poolAddress:String", raw"skip: $skip"
        end
        query = """
        query($block_modifier_query) {
            ticks ($block_modifier_pools, orderBy:tickIdx, first: 1000, where: {poolAddress: \$poolAddress}) {
                tickIdx
                liquidityGross
                liquidityNet

                price0
                price1
            }
        }
        """
    end

    vars = Dict(
        "block" => block,
        "poolAddress" => pool_address,
        "skip" => skip
    )

    JSON.parse(String(HTTP.post(url, header, JSON.json(Dict("query" => query, "variables" => vars))).body))["data"]
end

function get_specific_pools(pool_ids; limit=5, block=nothing)
    all_results = []
    limit = min(limit, length(pool_ids))

    for (idx, pool_address) in enumerate(lowercase.(pool_ids))
        @info "($idx/$limit) Fetching pool address $pool_address"
        skip = 0
        pool_data = get_uniswap_data(mode=pool_mode; pool_address, block)["pool"]
        all_tick_data = get_uniswap_data(mode=ticks_mode; pool_address, block)["ticks"]

        # We only get the top 1000 results at any one time, so we need to do multiple requests
        while true
            skip += 1000
            tick_data = get_uniswap_data(mode=ticks_mode; pool_address, block, skip)["ticks"]
            if isempty(tick_data)
                break
            else
                append!(all_tick_data, tick_data)
            end
        end

        pool_data["ticks"] = all_tick_data
        push!(all_results, Dict("pool" => pool_data))

        if idx >= limit
            break
        end
    end

    all_results
end

function get_experiment_pools(block=nothing)
    DAI_USDC_0_01 = "0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168"
    DAI_ETH_0_05 = "0x60594a405d53811d3BC4766596EFD80fd545A270"
    DAI_ETH_0_30 = "0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8"
    USDC_ETH_0_01 = "0xE0554a476A092703abdB3Ef35c80e0D76d32939F"
    USDC_ETH_0_05 = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"
    USDC_ETH_0_30 = "0x8ad599c3a0ff1de082011efddc58f1908eb6e6d8"
    USDC_ETH_1_00 = "0x7BeA39867e4169DBe237d55C8242a8f2fcDcc387"
    USDC_USDT_0_01 = "0x3416cF6C708Da44DB2624D63ea0AAef7113527C6"
    USDC_USDT_0_05 = "0x7858E59e0C01EA06Df3aF3D20aC7B0003275D4Bf"
    ETH_USDT_0_30 = "0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36"
    ETH_USDT_0_05 = "0x11b815efB8f581194ae79006d24E0d814B7697F6"

    pool_list = [DAI_USDC_0_01,
        DAI_ETH_0_30,
        DAI_ETH_0_05,
        DAI_ETH_0_30,
        USDC_ETH_0_01,
        USDC_ETH_0_05,
        USDC_ETH_0_30,
        USDC_ETH_1_00,
        USDC_USDT_0_01,
        USDC_USDT_0_05,
        ETH_USDT_0_30,
        ETH_USDT_0_05
    ]

    # Single pool
    res = get_specific_pools([USDC_ETH_0_30]; block)
    open(joinpath(@__DIR__, "data", "univ3_one_pool.json"), "w") do file
        write(file, JSON.json(res, 4))
    end

    # Multiple pools
    res = get_specific_pools(pool_list; limit=100, block)
    open(joinpath(@__DIR__, "data", "univ3_top_pools.json"), "w") do file
        write(file, JSON.json(res, 4))
    end

    nothing
end

get_experiment_pools()