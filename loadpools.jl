using CFMMRouter
using JSON

# See univ3 factory contract
get_fee_tier(x) = 1 - x / 1e6

tick_to_price0(tick, token0dec, token1dec) = (1.0001^tick) * 10.0^(token0dec - token1dec)

function load_single_pool(pool, symb_to_index)
    token0symb = pool["pool"]["token0"]["symbol"]
    token1symb = pool["pool"]["token1"]["symbol"]
    token0dec = parse(Int64, pool["pool"]["token0"]["decimals"])
    token1dec = parse(Int64, pool["pool"]["token1"]["decimals"])
    current_price = parse(Float64, pool["pool"]["token1Price"])
    token0index = symb_to_index(token0symb)
    token1index = symb_to_index(token1symb)

    γ = get_fee_tier(parse(Int, pool["pool"]["feeTier"]))

    ## You can basically think of the uniswap v3 liquidity as being √(x*y) in virtual reserves terms. 
    ## Hence, since we want to normalize for decimals, we can divide the liquidity by 
    ## Liquidity/(10^(token0dec +token1dec)/2) so for WETH USDT
    ## so for WETH(18) USDT(6) we would divide by 10^12

    ## lower_ticks and liquidity assembly
    running_liquidity = 0.0
    lower_ticks = Vector{Float64}()
    liquidity = Vector{Float64}()
    for tick_raw in pool["pool"]["ticks"]
        lower_tick = tick_to_price0(parse(Float64, tick_raw["tickIdx"]), token0dec, token1dec)
        running_liquidity += parse(Float64, tick_raw["liquidityNet"]) / 10^((token0dec + token1dec) / 2)
        push!(lower_ticks, lower_tick)
        push!(liquidity, running_liquidity^2)
    end

    Ai = Int64.([token0index, token1index])

    UniV3(current_price, reverse(lower_ticks), reverse(liquidity), γ, Ai)
end

function load_univ3_pools(filepath)
    ## Load in data
    f = open(filepath, "r")
    dicttxt = read(f, String)  # file information to string
    close(f)

    data_dict = JSON.parse(dicttxt)  # parse and transform data

    ## Collect all token symbols
    set_symbols = Set()
    for pool in data_dict
        push!(set_symbols, pool["pool"]["token0"]["symbol"])
        push!(set_symbols, pool["pool"]["token1"]["symbol"])
    end

    ## create a symb_to_index function
    symbols = collect(set_symbols)
    symb_to_index(symb) = findfirst(==(symb), symbols)

    ## load the individual pools
    cfmms = Vector{UniV3{Float64}}()
    for pool in data_dict
        push!(cfmms, load_single_pool(pool, symb_to_index))
    end

    (cfmms, symbols, symb_to_index)
end


# XXX: Do we use this at all?
function assemble_prices_vector(cfmms, symbols, symb_to_index)
    usd_weth_idxs = symb_to_index.("USDC", "WETH")
    is_usdc_eth_pool(cfmm) = cfmm.Ai[1] in usd_weth_idxs && cfmm.Ai[2] in usd_weth_idxs

    usdc_eth_price = 1 / cfmms[findfirst(is_usdc_eth_pool, cfmms)].current_price
    prices = Vector{Float64}()

    for symbol in symbols
        if symbol == "USDC"
            push!(prices, 1.0)
        elseif symbol == "WETH"
            push!(prices, usdc_eth_price)
        else
            idx = findfirst(x -> (((x.Ai[1] == symb_to_index("WETH")) && x.Ai[2] == symb_to_index(symbol)) || ((x.Ai[1] == symb_to_index(symbol)) && x.Ai[2] == symb_to_index("WETH"))), cfmms)
            if !isnothing(idx)
                relative_cfmm = cfmms[idx]
                if relative_cfmm.Ai[1] == symb_to_index("WETH")
                    push!(prices, usdc_eth_price / relative_cfmm.current_price)
                else
                    push!(prices, usdc_eth_price * relative_cfmm.current_price)
                end
            else
                push!(prices, -1.0)
            end
        end
    end

    prices
end
