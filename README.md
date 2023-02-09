# Experiments

This is a repository containing the code used to generate the plots for "An
Efficient Algorithm for Optimal Routing Through Constant Function Market
Makers."

To run, you'll first need to fetch data from The Graph. This can be done by
running the `fetchuniv3.jl` Julia file, which will spit out two JSON files that
will be used as later input. (Note that this only needs to be run once!)

You can then run the `generate_plots.jl` file, which will, as the name
specifies, generate the plots. These plots might differ from those of the paper
as they're using current data.

The code for our comparison with Mosek is in `comparison.jl`.