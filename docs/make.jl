using Documenter
using PowerGridPlanning

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
