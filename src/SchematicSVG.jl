"""
    SchematicSVG

Dependency-free schematic renderer for Jupyter. A schematic is a list of *placed*
primitives (the same information a CircuiTikZ `\\draw ... to[R] ...` line carries),
rendered as inline SVG so the drawing is stored inside the .ipynb itself.

Coordinates are in CircuiTikZ units (y points up); the SVG backend flips y.
"""
module SchematicSVG

# Opamp is not exported: Microelectronics.jl exports its own (use SchematicSVG.Opamp).
export Pt, Bipole, Transistor, Wire, Ground, Dot, Supply, Port, NodeLabel, PinRef
export Schematic, pin, to_svg
export ascii_schematic, @schem_str
export annotate, si
export tikz_schematic, @tikz_str
export schematic_netlist, spice_netlist, to_microelectronics, SchematicNetlist, NetDevice, parse_value
export spice_subcircuit, to_subcircuit

include("primitives.jl")   # geometry and placed primitives
include("svg.jl")          # Schematic container, show method, SVG renderer
include("annotate.jl")     # element values/models and node annotations
include("ascii.jl")        # ASCII-art front end
include("tikz.jl")         # CircuiTikZ front end
include("netlist.jl")      # connectivity, SPICE text, Microelectronics.jl hook

# Until `using Microelectronics` loads the extension, explain what's missing.
function to_microelectronics(args...; kw...)
    throw(ArgumentError("to_microelectronics needs Microelectronics.jl: run `using Microelectronics` first"))
end
function to_subcircuit(args...; kw...)
    throw(ArgumentError("to_subcircuit needs Microelectronics.jl: run `using Microelectronics` first"))
end

end # module
