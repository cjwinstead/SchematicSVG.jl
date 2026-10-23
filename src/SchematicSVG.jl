"""
    SchematicSVG

Dependency-free schematic renderer for Jupyter. A schematic is a list of *placed*
primitives (the same information a CircuiTikZ `\\draw ... to[R] ...` line carries),
rendered as inline SVG so the drawing is stored inside the .ipynb itself.

Coordinates are in CircuiTikZ units (y points up); the SVG backend flips y.
"""
module SchematicSVG

export Pt, Bipole, Transistor, Opamp, Wire, Ground, Dot, Supply, Port, NodeLabel, PinRef
export Schematic, pin, to_svg
export ascii_schematic, @schem_str
export annotate, si
export tikz_schematic, @tikz_str

include("primitives.jl")   # geometry and placed primitives
include("svg.jl")          # Schematic container, show method, SVG renderer
include("annotate.jl")     # element values/models and node annotations
include("ascii.jl")        # ASCII-art front end
include("tikz.jl")         # CircuiTikZ front end

end # module
