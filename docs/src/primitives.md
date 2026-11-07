# Placed primitives

A [`Schematic`](@ref) is a list of placed primitives, and you can build one directly.
Coordinates are in CircuiTikZ units with y pointing up.

```@example prim
using SchematicSVG

Schematic([
    Bipole(:V, Pt(0, 1), Pt(0, 0), raw"$v_{in}$"), Ground(Pt(0, 0)),
    Wire(Pt(0, 1), PinRef("Q1", :B)),
    Transistor(:npn, "Q1", Pt(1, 1)),
    Bipole(:R, Pt(1, 2.5), Pt(1, 1.5), raw"$R_C$"), Wire(Pt(1, 1.5), PinRef("Q1", :C)),
    Supply(Pt(1, 2.5), "V_{CC}", true),
    Wire(PinRef("Q1", :E), Pt(1, 0)), Ground(Pt(1, 0)),
])
```

| Primitive | Notes |
|---|---|
| [`Bipole`](@ref)`(kind, a, b, label; name, note, side)` | `kind` ∈ `:R :C :L :D :V :I :sV :cV :cI :box :open :short`; drawn along a→b. For sources `a` is SPICE n+ (`+` near a; current arrow a→b). `side` = `:auto`, or `:left`/`:right` of a→b like CircuiTikZ. |
| [`Transistor`](@ref)`(kind, name, at; xflip, yflip, label, note, w, h)` | `:npn :pnp :nmos :pmos`; pins `:B/:G`, `:C/:D`, `:E/:S` via [`pin`](@ref) or [`PinRef`](@ref), at `w` (control) and `h` (top/bottom) from the centre |
| `SchematicSVG.Opamp(name, at; label, note, w, h, inv_up)` | pins `:inp`, `:inn`, `:out`; inputs at (−w, ±h). Not exported, so it doesn't clash with Microelectronics' `Opamp`. |
| [`Wire`](@ref)`(points...)` | points are [`Pt`](@ref) or `PinRef(device, pin)` |
| [`Port`](@ref)`(at, label, side; name)`, [`NodeLabel`](@ref)`(at, name, side; label)` | terminal with circle / node name only; `side` ∈ `:left :right :above :below` |
| [`Ground`](@ref)`(at, flip=false)`, [`Supply`](@ref)`(at, label, up)`, [`Dot`](@ref)`(at)` | |
| [`Voltage`](@ref)`(plus, minus, label; side, kind)` | polarity marks: on the line for `kind=:open`, flanking the symbol of a component of that kind |
| [`Current`](@ref)`(a, b, label; side, into, pos, kind)` | current arrow on the wire a→b, pointing at `b` (at `a` when `into`), `pos` of the way along |
| [`Caption`](@ref)`(at, text; align)` | free text centred on `at` (`align=:left`/`:right` to start/end there) |

`note` is the second line of text (value or model) that [annotations](@ref Annotations)
fill in.

## Currents at a node

To mark the currents branching at a node, give each branch its own arrow starting at the
node; `into=true` marks a current entering it.

```@example prim
node = Pt(0, 0)
Schematic([
    Wire(Pt(-1.5, 0), Pt(1.5, 0)), Wire(node, Pt(0, -1.5)), Dot(node),
    Current(node, Pt(-1.5, 0), "i_1"; into=true, pos=0.4),
    Current(node, Pt(1.5, 0), "i_2"; pos=0.4),
    Current(node, Pt(0, -1.5), "i_3"; pos=0.4),
])
```

## Labels

Labels accept a small subset of LaTeX: `$…$` is stripped, `_x` / `_{xy}` become
subscripts (`\_` is a literal underscore), `\mathrm{…}`/`\text{…}` keep their text,
and Greek letters plus `\infty \cdot \times \pm \approx \parallel \, \;` map to Unicode.

## Settings

`Schematic(items; scale=50, stroke="#222", background="white", font="serif", xscale=1,
yscale=1, border=true)` sets pixels per unit, line colour, background (`"none"` for
transparent), label font, the layout spread ([Spacing and layout](@ref)) and the border
around the figure. `Schematic(s; kw...)` copies a drawing with new settings, and
[`to_svg`](@ref)`(s)` returns the SVG text to save or embed elsewhere.
