# SchematicSVG.jl

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://cjwinstead.github.io/SchematicSVG.jl/dev/)
[![CI](https://github.com/cjwinstead/SchematicSVG.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/cjwinstead/SchematicSVG.jl/actions/workflows/CI.yml)

Circuit schematics for Jupyter notebooks, in pure Julia with no dependencies. A
schematic renders as inline SVG, so the drawing is stored inside the `.ipynb` itself: no
image files, no LaTeX, no external tools.

Schematics can also be turned back into circuits: SPICE text, subcircuits, or
[Microelectronics.jl](https://github.com/cjwinstead/Microelectronics.jl) objects ready to
simulate.

**[Documentation](https://cjwinstead.github.io/SchematicSVG.jl/dev/)**

## Installation

SchematicSVG is registered in the
[LEFT registry](https://github.com/cjwinstead/LEFT_registry):

```julia
using Pkg
Pkg.Registry.add(url="https://github.com/cjwinstead/LEFT_registry")   # once
Pkg.add("SchematicSVG")
```

## Three ways to draw

Sketch the circuit as **ASCII art** and let the parser place everything:

```julia
using SchematicSVG

schem"""
            +--gnd
            |
            OA1-------+---vout
            |         |
  vin--R1---+---R2----+
"""
```

Paste **CircuiTikZ** code and display it directly:

```julia
tikz"""
\begin{circuitikz}
  \draw (0,0) node[ground]{} to[V, l=$v_{in}$] (0,2) to[R=$R_1$] (3,2)
        to[C=$C_1$, *-] (3,0) node[ground]{};
  \draw (3,2) to[short, -o] (4.5,2) node[right]{$v_o$};
\end{circuitikz}
"""
```

Or build the drawing from **placed primitives** (`Bipole`, `Transistor`, `Wire`, …).

## Features

- **Drawing**: resistors, capacitors, inductors, diodes, independent and dependent
  sources, MOSFETs, BJTs and op-amps; node names, voltage marks, branch-current arrows
  and captions ([ASCII drawings](https://cjwinstead.github.io/SchematicSVG.jl/dev/ascii/),
  [CircuiTikZ](https://cjwinstead.github.io/SchematicSVG.jl/dev/circuitikz/)).
- **Layout**: spread or tighten a drawing without resizing its symbols, and combine
  several drawings into one figure joined at their terminals
  ([Spacing and layout](https://cjwinstead.github.io/SchematicSVG.jl/dev/layout/)).
- **Annotations**: element values, models and node voltages next to the symbols
  ([Annotations](https://cjwinstead.github.io/SchematicSVG.jl/dev/annotations/)).
- **Netlists**: SPICE text, subcircuits with terminals taken from the drawing, and
  Microelectronics.jl objects, with warnings for nodes SPICE can't solve
  ([Netlists and simulation](https://cjwinstead.github.io/SchematicSVG.jl/dev/netlists/)).

## Examples

`examples/demo.ipynb` is a tour of the drawing features, and
`examples/mos_amplifiers.ipynb` builds common-source, source-follower, common-gate,
differential-pair and two-stage amplifier subcircuits from drawings and simulates them
with Microelectronics.jl.

## Development

```julia
using Pkg; Pkg.test("SchematicSVG")
```

`test/microelectronics.jl` tests the Microelectronics.jl extension (including ngspice
operating points). It runs as part of the suite when Microelectronics is installed, or on
its own from an environment with both packages: `include("test/microelectronics.jl")`.

To build the documentation locally:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl     # then open docs/build/index.html
```

Changes are listed in [CHANGELOG.md](CHANGELOG.md).
