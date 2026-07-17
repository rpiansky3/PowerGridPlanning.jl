using Documenter
using Literate
using PowerGridPlanning

# Headless GR backend for the plots generated while executing the tutorial
ENV["GKSwstype"] = "100"

# The tutorial docs page and the repository-root notebook are both generated
# from the single Literate source docs/lit/tutorial.jl, so they cannot drift
# apart. The markdown version runs as @example blocks during makedocs below;
# the notebook is written without outputs for users to execute themselves.
const LIT_TUTORIAL = joinpath(@__DIR__, "lit", "tutorial.jl")
Literate.markdown(LIT_TUTORIAL, joinpath(@__DIR__, "src"); documenter=true)
Literate.notebook(LIT_TUTORIAL, dirname(@__DIR__); execute=false)

makedocs(
    sitename = "PowerGridPlanning.jl",
    modules = [PowerGridPlanning],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://rpiansky3.github.io/PowerGridPlanning.jl",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Tutorial" => "tutorial.md",
        "Guide" => [
            "Models and Methods" => "guide/models.md",
            "Data" => "guide/data.md",
            "Usage Guide" => "guide/usage.md",
            "Command-Line Interface" => "guide/cli.md",
            "Examples" => "guide/examples.md",
        ],
        "Reference" => [
            "Results Dictionary" => "reference/results.md",
            "Plotting" => "reference/plotting.md",
            "API Reference" => "reference/api.md",
        ],
    ],
    checkdocs = :exports,
)

deploydocs(
    repo = "github.com/rpiansky3/PowerGridPlanning.jl.git",
    devbranch = "main",
)
