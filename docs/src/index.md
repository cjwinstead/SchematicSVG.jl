# SchematicSVG.jl

Circuit schematics for Jupyter notebooks, in pure Julia with no dependencies. A
schematic renders as inline SVG, so the drawing is stored inside the `.ipynb` itself: no
image files, no LaTeX, no external tools.

Schematics can also be turned back into circuits: SPICE text, subcircuits, or
[Microelectronics.jl](https://github.com/cjwinstead/Microelectronics.jl) objects ready to
simulate.

## Installation

SchematicSVG is registered in the
[LEFT registry](https://github.com/cjwinstead/LEFT_registry):

```julia
using Pkg
Pkg.Registry.add(url="https://github.com/cjwinstead/LEFT_registry")   # once
Pkg.add("SchematicSVG")
```

## Three ways to draw

**ASCII art**: sketch the circuit in a string and let the parser place everything
([ASCII drawings](@ref)).

```@example home
using SchematicSVG

schem"""
            +--gnd
            |
            OA1-------+---vout
            |         |
  vin--R1---+---R2----+
"""
```

**CircuiTikZ**: paste (or generate) CircuiTikZ code and display it directly
([CircuiTikZ](@ref)).

```@example home
tikz"""
\begin{circuitikz}
  \draw (0,0) node[ground]{} to[V, l=$v_{in}$] (0,2) to[R=$R_1$] (3,2)
        to[C=$C_1$, *-] (3,0) node[ground]{};
  \draw (3,2) to[short, -o] (4.5,2) node[right]{$v_o$};
\end{circuitikz}
"""
```

**Placed primitives**: build the drawing from Julia objects ([Placed primitives](@ref)).

```@example home
Schematic([
    Bipole(:V, Pt(0, 1), Pt(0, 0), raw"$v_{in}$"), Ground(Pt(0, 0)),
    Wire(Pt(0, 1), PinRef("Q1", :B)),
    Transistor(:npn, "Q1", Pt(1, 1)),
    Bipole(:R, Pt(1, 2.5), Pt(1, 1.5), raw"$R_C$"), Wire(Pt(1, 1.5), PinRef("Q1", :C)),
    Supply(Pt(1, 2.5), "V_{CC}", true),
    Wire(PinRef("Q1", :E), Pt(1, 0)), Ground(Pt(1, 0)),
])
```

A notebook cell (or documentation example) that ends in a `Schematic` displays the
drawing; `to_svg` gives the SVG text for use elsewhere.

## What else it does

- Mark voltages, branch currents and captions on a drawing ([ASCII drawings](@ref)).
- Spread a drawing out, or combine several into one figure joined at their terminals
  ([Spacing and layout](@ref)).
- Show element values, models and node voltages next to the symbols
  ([Annotations](@ref)).
- Netlist any drawing to SPICE text, a subcircuit, or Microelectronics.jl objects, with
  checks for nodes SPICE can't solve ([Netlists and simulation](@ref)).

The repository's `examples/` folder has two notebooks: `demo.ipynb`, a tour of the
drawing features, and `mos_amplifiers.ipynb`, which builds MOS amplifier subcircuits from
drawings and simulates them with Microelectronics.jl.
