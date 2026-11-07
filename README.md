# SchematicSVG.jl

Dependency-free circuit schematics for Jupyter notebooks. Schematics render as inline
SVG, so the drawing is stored inside the `.ipynb` itself: no image files, no LaTeX, no
external tools.

Schematics can also be turned back into netlists: SPICE text, or
[Microelectronics.jl](https://github.com/cjwinstead/Microelectronics.jl) objects ready to
simulate (see [Netlists and simulation](#netlists-and-simulation)).

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
| Two-terminal | `R`, `C`, `L`, `D` (and `zD`, `sD`, `leD`, filled variants), `V`, `I`, `sV`/`sI`, `cV`, `cI`, `short`, `open`, `generic`/`fuse` (box); options `l=`, `l_=`, `a=`, `v=` (and `v^=`, `v<=`), `i=` (and `i_=`, `i<=`, `i>_=`, …), `n=`, `invert`, `*-*`/`o-`/`-o` end markers, siunitx values like `R=4.7<\kilo\ohm>` |
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
| `Ovgs` `O1` | open circuit with voltage marks: `+`/`−` at its ends and a label from the name (`Ovgs` → v<sub>gs</sub>, `O1` → none); same markers as V |
| `gnd` `vdd` `vcc` `vss` `vee` | ground and supply rails |
| other lowercase words | named terminals (open circle) |
| `@name` | node tag: italic node name, no circle (see below) |
| `"text"` `<"text"` `"text">` | caption: centred on the quotes, starting at the opening quote, or ending at the closing one (see below) |
| `~i1>` `<~i1` `~i1^` `~i1v` | current arrow inline in a wire, labelled from the name (`~i1` → i<sub>1</sub>); default right/down (see below) |

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

### Voltage marks

An `O` element is an open circuit that shows the voltage across it, as in small-signal
models. The hybrid-π MOSFET model, with the labels set to math:

```julia
hybrid_pi = """
   g        +------+------d
            |      |
   Ovgs     G1     RO
            |      |
   s--------+------+------s
"""
ascii_schematic(hybrid_pi; labels=Dict("G1" => raw"$g_mv_{gs}$", "RO" => raw"$r_o$"))
```

An open circuit reaches across blank cells to the terminal or wire at each end, so `g` and
`s` above become its terminals with no connecting wires (a dangling wire end reached this way
gets a terminal circle). The `+` is at the top (or left) by default; `Ovgs^`/`<Ovgs` style markers work as for sources.
In CircuiTikZ the same is `to[open, v=$v_{gs}$]`, and `v=` on any other component draws
its polarity marks beside the symbol (`v^=` on the other side, `v<=` reversed). For placed
drawings use `Voltage(plus, minus, label; side, kind)`. Voltage marks are annotation only;
open circuits are left out of netlists.

### Current arrows

A word starting with `~` inside a horizontal or vertical wire draws a current arrow there,
so the currents branching at a node can be marked on each wire leaving it:

```julia
kcl = """
   in--~i1>--*--~i2>--R1--out
             |
            ~i3
             |
             R2
             |
            gnd
"""
ascii_schematic(kcl; labels=Dict("i2" => raw"$i_{R1}$"))
```

The label comes from the name (`~i1` → i<sub>1</sub>, `~iD` → i<sub>D</sub>) unless
`labels` overrides it. Arrows point right or down by default; `<~i1` points left and
`~i1^` up (`~i1v`, down, is accepted after a digit, as for sources). The cell stays a
wire, so arrows don't change the netlist.

In CircuiTikZ use `i=` on any `to[…]`: on a `short` the arrow is mid-wire, and on a
component it sits on the lead after the symbol. `i_=` puts the label on the other side,
`i<=` reverses the arrow (before the symbol), and `i_>=`, `i^<=`, `i>_=`, `i<^=` and so on
follow CircuiTikZ's placement rules. For placed drawings use
`Current(a, b, label; side, into, pos)` (below).

### Captions

Text in double quotes is a caption, such as a title under each stage. Nothing inside the
quotes is parsed, so it may contain dashes, letters and `$…$` math:

```julia
two_stage = """
          vdd            vdd
           |              |
           RD             |
           |              |
           *--@x---+      |
           |       |      |
   in----|N1       +----|N2
           |              |
          gnd             *---out
                          |
                          RS
                          |
                         gnd

    "Common source"      <"Source follower"
"""
ascii_schematic(two_stage)
```

A caption is centred on its quotes by default. A drawn character is narrower than a grid
cell, and markup like `\approx` takes up room in the source, so when the text should line
up with something use `<"text"` (it starts at the opening quote) or `"text">` (it ends at
the closing quote). For placed drawings use `Caption(at, text; align)`.

## Spacing: `xscale` and `yscale`

`xscale` and `yscale` spread a drawing out (or pull it in) horizontally and vertically
without changing the size of symbols or text; wires and leads get longer or shorter.
They work as keywords of `ascii_schematic`, `tikz_schematic` and `Schematic`, and
`Schematic(s; kw...)` copies a finished drawing with new settings:

```julia
s = ascii_schematic(two_stage)
Schematic(s; xscale=1.5)               # wider
Schematic(s; xscale=1.2, yscale=0.8)   # wider and flatter
```

A CircuiTikZ environment's own `[xscale=…, yscale=…]` options do the same (as in TikZ
without `transform shape`). `scale` is different: it sets the pixels per unit, so it also
resizes transistors and op-amps. When a drawing is pulled in, a symbol's leads get
shorter but never run into the symbol: a PMOS gate wire stops outside the bubble, MOSFET
and BJT leads stop at the bars, and an op-amp keeps its inputs where they are and slides
right so its input leads keep some length. Very small values (below about 0.5) can still
crowd neighbouring parts.

## Combining drawings: `layout`

`layout(parts...)` places drawings side by side (`direction=:row`) or stacked
(`direction=:column`) in one figure. Parts are ASCII drawings or `Schematic`s, such as
stages already annotated with their own values, and the result is an ordinary
`Schematic`, so it can be netlisted, made into a subcircuit or laid out again.
`[s1 s2]` and `[s1; s2]` do the same for `Schematic`s.

Parts join at their terminals in two ways, which can be mixed:

```julia
cs = ascii_schematic(CS_DRAWING; elements=cs_values)
sf = ascii_schematic(SF_DRAWING; elements=sf_values)

# drawn: SF is moved so its `in` lines up with CS's `out`, and a wire joins them
two_stage = layout(cs, sf; connect=[(1, "out") => (2, "in")])
to_subcircuit(two_stage; name="cs_sf")          # terminals in, out

# by name: both terminals stay drawn, with one label (out₁); useful for a column
layout(cs, sf; direction=:column, share=[(1, "out") => (2, "in")])
```

A drawn connection needs neighbouring parts, and each neighbouring pair can have one;
`share` joins any parts, and `share=["vb"]` makes a node common to every part that has
it. Supplies and ground are always common. Any other element or node name used in more
than one part gets the part's number (`CC1` → `CC1_1`, `CC1_2`; `@g` → `g_1`, `g_2`), so
separate parts stay separate, and terminal and node labels follow; element labels in the
drawing are left as they are. The joined node keeps the first terminal's name, numbered
if that name is used elsewhere (`out_1` above).

`gap` (circuit units, default 1.5) sets the spacing, and `align` lines up parts that
aren't joined by a drawn connection: `:top`, `:center` or `:bottom` in a row, `:left`,
`:center` or `:right` in a column. Other keywords (`xscale`, `border`, …) are settings of
the result, which otherwise come from the first part.

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

## Netlists and simulation

Any schematic (ASCII, CircuiTikZ or placed primitives) can be netlisted. With
Microelectronics.jl loaded, `to_microelectronics` returns its element objects:

```julia
using SchematicSVG, Microelectronics

amp = """
              vdd               vdd
               |                 |
               RB1               RC
               |                 |
               |                 +---C2---+--@vo
               |                 |        |
   +--RS--C1---+--@vb-----------|Q1       RL
   |           |                 |        |
   VS          RB2               RE      gnd
   |           |                 |
  gnd         gnd               gnd
"""

# The nodes given here are placeholders: the drawing supplies the real ones.
parts = [Resistor("RB1", 0, 0, 47u"kΩ"), Resistor("RB2", 0, 0, 10u"kΩ"),
         Resistor("RC", 0, 0, 4.7u"kΩ"), Resistor("RE", 0, 0, 1u"kΩ"),
         Resistor("RL", 0, 0, 10u"kΩ"), Resistor("RS", 0, 0, 50u"Ω"),
         Capacitor("C1", 0, 0, 10u"μF"), Capacitor("C2", 0, 0, 2.2u"μF"),
         Vsin("VS", 0, 0; amplitude=10u"mV", frequency=1u"kHz")]

s = ascii_schematic(amp; elements=parts)          # the drawing, annotated with the values
ckt = to_microelectronics(s; elements=Dict("Q1" => "Q2N3904"), supplies=Dict("vdd" => 12u"V"))
build_netlist(; ckt...)                           # ckt = (; sources, components)
simulate(:tran; tstep=10u"μs", tmax=3u"ms")
```

Without Microelectronics.jl, `spice_netlist(s; title, include, elements, supplies)`
returns SPICE text and `schematic_netlist(s; elements, supplies)` the devices and nodes
(it displays as SPICE lines).

Values may be Unitful quantities (`4.7u"kΩ"`, `10u"μF"`). The drawing shows them with
their units, and SPICE text gets plain numbers: with Microelectronics.jl loaded they are
formatted by its `qstr` (`4700`, `1e-05`), otherwise converted to SI units by a small
Unitful extension (`4700`, `1.0e-5`). Units never reach the netlist.

**Connectivity** comes from the geometry: wire ends, pins and markers at the same point
are one node, and a point lying on a wire (a T-junction) joins it. Wires that only cross
(`)` in ASCII, or two CircuiTikZ wires crossing mid-segment) stay separate.

**Node names**: ground symbols are `0`; supply symbols name their node (`vdd`, `vcc`,
`vss`…; several symbols with the same name are one node); terminals and `@` tags name
theirs (`vin`, `vo`); the rest are `n1`, `n2`, …. Two names on one wire give a warning.

**Values** for each instance (matched case-insensitively, by drawn name or SPICE name, so
`N1` matches Microelectronics' `MN1`) come from, in order:

1. `elements` passed to `to_microelectronics` / `schematic_netlist`;
2. the elements the schematic was annotated with (`ascii_schematic(…; elements)`,
   `annotate`), kept with the schematic;
3. the drawing's text: notes and `l=`/`a=` labels such as `4.7 kΩ`, `10<\micro F>`,
   `R_1 = 1k`, or a model name. Prefixes are SI (`M` is mega; `meg` also works).

Element objects you supply are reused with the drawn nodes, so their values, models,
waveforms and instance parameters carry over. Plain values work too:

| Device | Value |
|---|---|
| R, C, L | number, quantity, `Symbol` (written as a `{param}`), or SPICE text |
| V, I | number/quantity (DC), a `Waveform` or vector of them, or SPICE text such as `"SIN(0 1 1k)"` |
| sinusoidal (`sV`) | NamedTuple `(amplitude=…, frequency=…, offset=…)`, or an amplitude |
| E, G (voltage-controlled) | `(gain, ("ctrl+", "ctrl-"))`, or a `VCVS`/`VCCS` object |
| H, F (current-controlled) | `(gain, "Vsense")`, or a `CCVS`/`CCCS` object |
| MOSFET | model name, or NamedTuple `(model=…, W=…, L=…, body=…)`; body tied to source otherwise |
| BJT, diode, op-amp | model name |

Devices without a value are written as `{name}` parameters (with a warning). Models default
to the Microelectronics library: `ald1105n`/`ald1105p`, `Q2N3904`/`Q2N3906`, `D1N914`,
`ideal_opamp`. Supplies need a voltage: `supplies=Dict("vdd" => 5u"V")` adds a `Vdc`
source for each. Dangling pins, unknown elements (drawn as boxes) and nodes with two names
produce warnings; a dependent source without its control is an error.

**Nodes with no DC path to ground** also warn, because SPICE can't find an operating
point for them. This is usually an output or input reached only through a coupling
capacitor (or a current source), and the warning names the node and suggests the fix: a
load resistor between that node and ground, or a bias resistor when the node drives a
MOSFET gate or an op-amp input. For example, `+---C2---vo` with nothing else at `vo` gives

```
node vo has no DC path to ground, so SPICE can't find the operating point (it connects
only through capacitors, current sources or high-impedance inputs). Add a load resistor
between vo and ground.
```

A schematic with no ground symbol at all gets its own warning.

### Subcircuits

`to_subcircuit(s; name, terminals, parameters, rename)` returns a Microelectronics
`Subcircuit`, and `spice_subcircuit(s; name, terminals, params, rename)` the
`.subckt … .ends` text.

The terminals come from the drawing: every named node with a terminal circle (`in`,
`out` in an ASCII drawing; an `ocirc` with a text label in CircuiTikZ), ordered left to
right and then top to bottom. A terminal drawn twice counts once, and `@` node tags,
grounds and supplies are not terminals. So for a drawing with `in` on the left and `out`
on the right,

```julia
to_subcircuit(ascii_schematic(cs_drawing); name="cs")      # terminals in, out
```

Pass `terminals=["inp", "inn", "outp", "outn"]` to pick the terminals or their order
(the pin order of the subcircuit), and `schematic_netlist(s).terminals` shows the ones a
drawing gives. Terminals and supply nodes are connected outside, so they don't
trigger the DC-path or supply warnings; `rename` maps drawn names to netlist names, e.g.
`Dict("vdd" => "vdd!", "vss" => "vss!")` for global supplies (declare them in the
enclosing netlist with `.global vdd! vss!`). The same `rename` and `external` keywords work
on `schematic_netlist`. `examples/mos_amplifiers.ipynb` builds common-source,
source-follower, common-gate and differential-pair subcircuits this way.

`SchematicSVG.Opamp` (the drawing primitive) is not exported, so it doesn't clash with
Microelectronics' `Opamp`.

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
| `Voltage(plus, minus, label; side, kind)` | polarity marks: on the line for `kind=:open`, flanking the symbol of a component of that kind |
| `Caption(at, text; align)` | free text centred on `at` (`align=:left`/`:right` to start/end there); `$…$` for math |
| `Current(a, b, label; side, into, pos, kind)` | current arrow on the wire a→b, pointing at `b` (at `a` when `into`), `pos` of the way along; with a component `kind` it goes on the end lead (`pos ≥ 0.5`) or the start lead. For currents at a node use `a` = the node, e.g. `Current(node, Pt(1, 0), "i_2"; pos=0.4)` |

`note` is the second line of text (value or model) that annotations fill in.

Labels accept a small subset of LaTeX: `$…$` is stripped, `_x` / `_{xy}` become
subscripts (`\_` is a literal underscore), `\mathrm{…}`/`\text{…}` keep their text,
and Greek letters plus `\infty \cdot \times \pm \approx \parallel \, \;` map to Unicode.

`Schematic(items; scale=50, stroke="#222", background="white", font="serif", xscale=1, yscale=1, border=true)`
sets pixels per unit, line colour, background (`"none"` for transparent), label font,
the layout spread (see [Spacing](#spacing-xscale-and-yscale)) and the border: a thick
gray frame with rounded corners around the whole figure, so you can tell when a drawing
runs past the edge of the notebook window. Turn it off with `border=false` (also a keyword
of `ascii_schematic` and `tikz_schematic`, or `Schematic(s; border=false)` afterwards).
`to_svg(s)` returns the SVG string if you want to save or embed it elsewhere.

## Tests

```julia
using Pkg; Pkg.test("SchematicSVG")
```

`test/microelectronics.jl` tests the Microelectronics.jl extension (including ngspice
operating points). It runs as part of the suite when Microelectronics is installed, or on
its own from an environment with both packages: `include("test/microelectronics.jl")`.
