# Build the documentation:
#
#     julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
#     julia --project=docs docs/make.jl
#
# and open docs/build/index.html. On GitHub, .github/workflows/Documentation.yml runs
# this and publishes the site to the gh-pages branch.
using Documenter, SchematicSVG

# The changelog lives at the top of the repository; show it in the docs too.
cp(joinpath(@__DIR__, "..", "CHANGELOG.md"), joinpath(@__DIR__, "src", "changelog.md"); force=true)

makedocs(;
    sitename = "SchematicSVG.jl",
    authors = "Chris Winstead",
    modules = [SchematicSVG],
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://cjwinstead.github.io/SchematicSVG.jl",
        edit_link = "main",
        assets = ["assets/schematics.css"],
        size_threshold = 2^21,               # pages carry their figures inline as SVG
        size_threshold_warn = 2^20,
    ),
    pages = [
        "Home" => "index.md",
        "ASCII drawings" => "ascii.md",
        "CircuiTikZ" => "circuitikz.md",
        "Placed primitives" => "primitives.md",
        "Spacing and layout" => "layout.md",
        "Annotations" => "annotations.md",
        "Netlists and simulation" => "netlists.md",
        "API reference" => "api.md",
        "Changelog" => "changelog.md",
    ],
    checkdocs = :exports,
)

deploydocs(; repo = "github.com/cjwinstead/SchematicSVG.jl.git", devbranch = "main")
