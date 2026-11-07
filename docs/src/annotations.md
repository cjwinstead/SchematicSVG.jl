# Annotations

Pass your netlist elements and they are matched to the instance names in the drawing
(case-insensitively, as in SPICE). A `Dict` of `name => value` works, and so does any
object with a `name` field and a `value` or `model` field: your own element structs,
NamedTuples, or Microelectronics.jl elements.

```@example ann
using SchematicSVG

amp = """
         vdd               vdd
          |                 |
          RB1               RC
          |                 |
          |                 +---C2---vo
          |                 |
   in--C1-+--@vb-----------|Q1
          |                 |
          RB2               RE
          |                 |
         gnd               gnd
"""
vals = Dict("RB1" => 47e3, "RB2" => 10e3, "RC" => 4.7e3, "RE" => 1e3,
            "C1" => 10e-6, "C2" => 2.2e-6, "Q1" => "2N3904")
ascii_schematic(amp; elements=vals, nodes=Dict("vb" => 1.9, "vo" => raw"$v_o$"))
```

- **Numbers** are printed in engineering notation with a unit implied by the instance
  letter: R → Ω, C → F, L → H, V → V, I → A, G → S, H → Ω (E and F gains are unitless).
  `47e3` on `RB1` becomes "47 kΩ". Unitful quantities keep their own units, and strings
  (`"10k"`, `"SIN(0 1 1k)"`) are printed as they are.
- **Models** (transistors, diodes, op-amps) are printed literally, so `nmos_lv` keeps its
  underscore. Wrap text in `$…$` to use the label syntax instead.
- **Nodes**: a number is shown as a voltage (`"vb" => 1.9` → "vb = 1.9 V"); a string
  replaces the displayed name. This applies to terminals (`vo`) and node tags (`@vb`).
- **`style`**: `:below` (default) puts the value on its own line, under horizontal parts
  and under the name beside vertical parts and transistors; `:inline` prints
  "``R_{B1}`` = 47 kΩ" and "``Q_1``: 2N3904" on one line; `:value` shows only the value.

```@example ann
ascii_schematic(amp; elements=vals, style=:inline)
```

Elements in your list that aren't in the drawing are ignored, and drawn instances with no
matching element keep just their name. The values stay with the schematic, and the
netlisters use them ([Netlists and simulation](@ref)).

[`annotate`](@ref)`(s, elements; nodes, style)` does the same for any `Schematic`,
including hand-placed ones (give each element a `name`), and [`si`](@ref) formats numbers
for your own labels: `si(4700, "Ω") == "4.7 kΩ"`.

## Your own element types

If your element type stores the name or value under other field names, add methods
instead of renaming fields:

```julia
SchematicSVG.instancename(e::MyElement) = e.id
SchematicSVG.annotation(e::MyElement)   = e.params[:R]
```
