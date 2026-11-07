# Spacing and layout

## `xscale` and `yscale`

`xscale` and `yscale` spread a drawing out (or pull it in) horizontally and vertically
without changing the size of symbols or text; wires and leads get longer or shorter.
They work as keywords of `ascii_schematic`, `tikz_schematic` and `Schematic`, and
`Schematic(s; kw...)` copies a finished drawing with new settings:

```@example layout
using SchematicSVG

stage = ascii_schematic("""
          vdd
           |
           RD
           |
           *---out
           |
   in----|N1
           |
          gnd
""")
Schematic(stage; xscale=1.6)        # wider
```

```@example layout
Schematic(stage; xscale=0.7, yscale=0.8)        # tighter
```

A CircuiTikZ environment's own `[xscale=…, yscale=…]` options do the same. `scale` is
different: it sets the pixels per unit, so it also resizes transistors and op-amps.

When a drawing is pulled in, a symbol's leads get shorter but never run into the symbol:
a PMOS gate wire stops outside the bubble, MOSFET and BJT leads stop at the bars, and an
op-amp keeps its inputs where they are and slides right so its input leads keep some
length. Very small values (below about 0.5) can still crowd neighbouring parts.

## Border

Every figure has a thick gray border with rounded corners, so a drawing that runs past
the edge of a notebook window is easy to spot. Turn it off with `border=false`, as a
keyword of `ascii_schematic`, `tikz_schematic` or `Schematic`, or afterwards with
`Schematic(s; border=false)`.

## Combining drawings

[`layout`](@ref)`(parts...)` places drawings side by side (`direction=:row`) or stacked
(`direction=:column`) in one figure. Parts are ASCII drawings or `Schematic`s, such as
stages already annotated with their own values, and the result is an ordinary
`Schematic`: it can be annotated, netlisted, made into a subcircuit or laid out again.
`[s1 s2]` and `[s1; s2]` do the same for `Schematic`s.

Two amplifier stages, each with its own values:

```@example layout
cs_drawing = """
                         vdd
                          |
                          RD
                          |
                          +-@d-CC2----+--out
                          |           |
  in----CC1--@g----+-----|N1          RL
                   |      |           |
                   RG     +-@s-+     gnd
                   |      |    |
                  gnd     I1   CB
                          |    |
                         vss  gnd
"""
sf_drawing = """
                         vdd
                          |
                          |
                          |
  in----CC1--@g----+-----|N1
                   |      |
                   RG     +-@s-CC2----+--out
                   |      |           |
                  gnd     I1          RL
                          |           |
                         vss         gnd
"""
fet = (model="ald1105n", W=20e-6, L=10e-6)
cs = ascii_schematic(cs_drawing; elements=Dict("RD" => 20e3, "RG" => 1e6, "RL" => 1e5,
        "CC1" => 1e-5, "CC2" => 1e-5, "CB" => 1e-4, "I1" => 1e-4, "N1" => fet))
sf = ascii_schematic(sf_drawing; elements=Dict("RG" => 1e6, "RL" => 1e5,
        "CC1" => 1e-5, "CC2" => 1e-5, "I1" => 1e-4, "N1" => fet))
nothing # hide
```

Parts join at their terminals in two ways, which can be mixed. `connect` draws the
connection: the second part moves so its terminal lines up with the first one's, and a
wire replaces both terminal circles.

```@example layout
two_stage = layout(cs, sf; connect=[(1, "out") => (2, "in")])
```

`share` connects by name only: both terminals stay drawn and take one name, so their
labels match. This suits a column, or parts that aren't neighbours.

```@example layout
layout(cs, sf; direction=:column, share=[(1, "out") => (2, "in")])
```

The result is one circuit. Its terminals are the ones left over, `in` and `out`:

```@example layout
print(spice_subcircuit(two_stage; name="cs_sf", rename=Dict("vdd" => "vdd!", "vss" => "vss!")))
```

### Names

Supplies and ground are always common to all parts. Any other element or node name used
in more than one part gets the part's number (`CC1` → `CC1_1`, `CC1_2`; `@g` → `g_1`,
`g_2`), so separate parts stay separate, and terminal and node labels follow; element
labels in the drawing are left as they are. Names used in only one part (`RD`, `CB`,
`@d` above) don't change. The joined node keeps the first terminal's name, numbered if
that name is used elsewhere (`out_1` above). `share=["vb"]` makes a node common to every
part that has it.

### Options

- A drawn connection needs neighbouring parts, and each neighbouring pair can have one;
  `share` joins any parts.
- `gap` (circuit units, default 1.5) sets the spacing.
- `align` lines up parts that aren't joined by a drawn connection: `:top` (default),
  `:center` or `:bottom` in a row; `:left` (default), `:center` or `:right` in a column.
- Other keywords (`xscale`, `border`, …) are settings of the result, which otherwise come
  from the first part.
