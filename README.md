# SchematicSVG.jl

Dependency-free circuit schematics for Jupyter notebooks. Schematics render as inline
SVG, so the drawing is stored inside the `.ipynb` itself: no image files, no LaTeX, no
external tools.

There are three ways to build a schematic:

- **CircuiTikZ** — paste (or generate) CircuiTikZ code and display it directly.
- **ASCII art** — sketch the circuit in a string and let the parser place everything.
- **Placed primitives** — build the drawing from Julia objects.

## Installation

```julia
using Pkg
Pkg.develop(path="path/to/SchematicSVG")   # or Pkg.add(url="…") once it is in a git repo
```

## CircuiTikZ

```julia
using SchematicSVG

tikz"""
\begin{circuitikz}
  \draw (0,0) node[ground]{} to[V, l=$v_{in}$] (0,2) to[C=$C_1$] (2,2) coordinate (B)
        to[R=$R_{B1}$, *-] (2,5) node[vcc]{$V_{CC}$};
  \draw (B) to[R=$R_{B2}$] (2,0) node[ground]{};
  \draw (B) -- (3.5,2) node[npn, anchor=B](Q1){$Q_1$};
  \draw (Q1.C) to[R=$R_C$] ++(0,2.23) node[vcc]{$V_{CC}$};
  \draw (Q1.E) to[R=$R_E$] ++(0,-1.23) node[ground]{};
  \draw (Q1.C) to[short, *-o] ++(1.5,0) node[right]{$v_o$};
\end{circuitikz}
"""
```

`tikz_schematic(code; elements, nodes, style, scale, …)` is the function form; annotations
work as for ASCII drawings (instance names come from `n=` or from the label, so
`R=$R_{B1}$` is `RB1`).

Geometry and conventions follow CircuiTikZ, so a drawing lines up the way it does in
LaTeX: coordinates are cm (`scale=50` px per cm by default); transistor and op-amp anchors
are where CircuiTikZ puts them; `to[V]`/`to[cV]` put `+` at the start of the path and
`to[I]`/`to[cI]` point the arrow at the end; `invert` flips the symbol; `l=` labels sit
left of the drawing direction and `l_=`/`a=` on the right; the op-amp − input is on top
unless `noinv input up` or `yscale=-1`; `pmos`/`pnp` have the source/emitter on top.

### Supported subset

| | |
|---|---|
| Statements | `\draw`, `\path`, `\node … at (p) {…}`, `\coordinate (A) at (p)`, inside `circuitikz` / `tikzpicture` (environment `scale=` honoured) or bare |
| Coordinates | `(x,y)` with optional units (cm, mm, pt, in) and simple arithmetic, `+(…)`, `++(…)`, polar `(θ:r)`, named `(A)`, anchors `(M1.D)`, `(OA.+)`, perpendicular `(A \|- B)`, `(A -\| B)` |
| Path operations | `--`, `-\|`, `\|-`, `to[…]`, `node[…](name){text}` (at the point, or mid-segment), `coordinate (name)` |
| Two-terminal | `R`, `C`, `L`, `D` (and `zD`, `sD`, `leD`, filled variants), `V`, `I`, `sV`/`sI`, `cV`, `cI`, `short`, `open`, `generic`/`fuse` (box); options `l=`, `l_=`, `a=`, `v=`, `i=`, `n=`, `invert`, `*-*`/`o-`/`-o` end markers, siunitx values like `R=4.7<\kilo\ohm>` |
| Nodes | `ground` (and variants), `vcc`/`vdd`, `vee`/`vss`, `circ`, `ocirc`, `nmos`/`pmos`/`nfet`/`pfet`, `npn`/`pnp`, `op amp`, plain text nodes (`right`/`left`/`above`/`below`/`anchor=`); options `anchor=`, `xscale=-1`, `yscale=-1`, `noinv input up` |

Anything else (`circle`, `\foreach`, `calc` expressions, rotated nodes, macros, unknown
elements) produces a warning naming what was skipped: unknown two-terminal elements are
drawn as a labelled box, rotated nodes upright, and an unsupported path operation ends
that statement. Nothing is dropped silently.

## ASCII schematics

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

A cell that evaluates to a `Schematic` displays as a drawing. For options, call the
function form:

```julia
ascii_schematic(art; labels=Dict("R1" => raw"$R_1 = 10\,k\Omega$"), dx=0.5, dy=0.8, scale=50)
```

### Legend

| Text | Meaning |
|---|---|
| `-` `\|` | horizontal / vertical wire |
| `+` | corner or junction |
| `*` | junction with an explicit dot |
| `)` | crossing — wires pass without connecting |
| `R1` `C1` `L1` | resistor, capacitor, inductor |
| `D1>` `<D1` `D1^` `D1v` | diode; the marker gives the cathode side (default right/down) |
| `V1` `I1` | voltage / current source; marker points to `+` (V, default left/top) or along the arrow (I, default right/down) |
| `E1` `H1` / `G1` `F1` | dependent voltage / current sources (diamonds), same markers as V / I |
| `-\|N1` | NMOS, gate on the left, drain on top (`N1\|-` puts the gate on the right) |
| `-\|P1` | PMOS, source on top |
| `-\|Q1` | npn BJT, collector on top |
| `OA1` | op-amp: + input wire from above, − input from below, output to the right |
| `gnd` `vdd` `vcc` `vss` `vee` | ground and supply rails |
| other lowercase words | named terminals (open circle) |
| `@name` | node tag: italic node name, no circle (see below) |

Rules of thumb:

- A word with wires on its left and right is drawn horizontally; one with wires above
  and below is drawn vertically.
- A `-` touching a `|` joins it, and cells where three or more wires meet get a dot
  automatically, so `+` is only needed for corners.
- Columns must line up exactly. Use spaces, not tabs.
- Run op-amp input wires down to the first letter of `OA1`.
- Default labels come from the names (`RD` → R<sub>D</sub>); override any of them with
  `labels`.

### Node tags

`@name` names a node without drawing a terminal. Names may contain letters, digits and
`_`, so SPICE node numbers work (`@3`).

| Placement | Result |
|---|---|
| `--@vx--` (inline in a wire) | the wire passes through; the name sits above it |
| `---@vx` / `@vx---` (at a wire end) | name beside the end of the wire |
| on the line below / above a wire | name just under / over the wire |
| in place of a `\|` in a vertical run | the wire passes through; the name sits to the right |

## Annotations: values, models and node voltages

Pass your netlist elements and they are matched to the instance names in the drawing
(case-insensitive, like SPICE). Any object with a `name` field and a `value` or `model`
field works, so your own element structs, NamedTuples, or a `Dict` of `name => value`.

```julia
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

ascii_schematic(amp;
    elements = circuit,                     # e.g. [Resistor("RB1", 47e3), …, BJT("Q1", "2N3904")]
    nodes    = Dict("vb" => 1.9, "vo" => raw"$v_o$"))
```

- **Numbers** are printed in engineering notation with a unit implied by the instance
  letter: R → Ω, C → F, L → H, V → V, I → A, G → S, H → Ω (E and F gains are unitless).
  `47e3` on `RB1` becomes "47 kΩ". Strings (`"10k"`, `"SIN(0 1 1k)"`) are printed as is.
- **Models** (transistors, diodes, op-amps) are printed literally, so `nmos_lv` keeps its
  underscore. Wrap text in `$…$` to use the label syntax instead.
- **Nodes**: a number is shown as a voltage (`"vb" => 1.9` → "vb = 1.9 V"); a string
  replaces the displayed name. This applies to terminals (`vo`) and node tags (`@vb`).
- **`style`**: `:below` (default) puts the value on its own line — under horizontal parts,
  and under the name beside vertical parts and transistors; `:inline` prints
  "R<sub>B1</sub> = 47 kΩ" and "Q<sub>1</sub>: 2N3904" on one line; `:value` shows only the
  value.

Elements in your list that aren't in the drawing are ignored, and drawn instances with no
matching element keep just their name.

If your element type stores these under other field names, add methods instead of
renaming fields:

```julia
SchematicSVG.instancename(e::MyElement) = e.id
SchematicSVG.annotation(e::MyElement)   = e.params[:R]
```

`annotate(s, elements; nodes, style)` does the same for any `Schematic`, including
hand-placed ones (give each element a `name`). `si(4700, "Ω") == "4.7 kΩ"` is exported
for your own labels.

## Placed primitives

Coordinates are in CircuiTikZ units with y pointing up.

```julia
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
| `Bipole(kind, a, b, label; name, note, side)` | `kind` ∈ `:R :C :L :D :V :I :sV :cV :cI :box :open :short`; drawn along a→b. For sources `a` is SPICE n+ (`+` near a; current arrow a→b). `side` = `:auto`, or `:left`/`:right` of a→b like CircuiTikZ. |
| `Transistor(kind, name, at; xflip, yflip, label, note, w, h)` | `:npn :pnp :nmos :pmos`; pins `:B/:G`, `:C/:D`, `:E/:S` via `pin` or `PinRef`, at `w` (control) and `h` (top/bottom) from the centre |
| `Opamp(name, at; label, note, w, h, inv_up)` | pins `:inp`, `:inn`, `:out`; inputs at (−w, ±h) |
| `Wire(points...)` | points are `Pt` or `PinRef(device, pin)` |
| `Port(at, label, side; name)`, `NodeLabel(at, name, side; label)` | terminal with circle / node name only; `side` ∈ `:left :right :above :below` |
| `Ground(at, flip=false)`, `Supply(at, label, up)`, `Dot(at)` | |

`note` is the second line of text (value or model) that annotations fill in.

Labels accept a small subset of LaTeX: `$…$` is stripped, `_x` / `_{xy}` become
subscripts (`\_` is a literal underscore), `\mathrm{…}`/`\text{…}` keep their text,
and Greek letters plus `\infty \cdot \times \pm \approx \parallel \, \;` map to Unicode.

`Schematic(items; scale=50, stroke="#222", background="white", font="serif")` sets pixels
per unit, line colour, background (`"none"` for transparent) and label font.
`to_svg(s)` returns the SVG string if you want to save or embed it elsewhere.

## Tests

```julia
using Pkg; Pkg.test("SchematicSVG")
```
