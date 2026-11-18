# ASCII drawings

Draw the circuit as text and the parser places every symbol, wire and label:

```@example ascii
using SchematicSVG

schem"""
            +--gnd
            |
            OA1-------+---vout
            |         |
  vin--R1---+---R2----+
"""
```

The `schem"…"` literal uses the default options. For options, call the function:

```julia
ascii_schematic(art; labels=Dict("R1" => raw"$R_1 = 10\,k\Omega$"), dx=0.5, dy=0.8, scale=50)
```

`labels` replaces any default label, `dx` and `dy` are the size of a character cell in
circuit units, and other keywords are [`Schematic`](@ref) settings (`xscale`, `border`,
…). `elements` and `nodes` annotate the drawing ([Annotations](@ref)).

## Legend

| Text | Meaning |
|---|---|
| `-` `\|` | horizontal / vertical wire |
| `+` | corner or junction |
| `*` | junction with an explicit dot |
| `)` | crossing: wires pass without connecting |
| `R1` `C1` `L1` | resistor, capacitor, inductor |
| `D1>` `<D1` `D1^` `D1v` | diode; the marker gives the cathode side (default right/down) |
| `V1` `I1` | voltage / current source; marker points to `+` (V, default left/top) or along the arrow (I, default right/down) |
| `SVsig` `SIb` | sinusoidal voltage / current source, named `Vsig` / `Ib` (the `S` is dropped); same markers as V / I |
| `E1` `H1` / `G1` `F1` | dependent voltage / current sources (diamonds), same markers as V / I |
| `-\|N1` | NMOS, gate on the left, drain on top (`N1\|-` puts the gate on the right) |
| `-\|P1` | PMOS, source on top |
| `-\|Q1` | npn BJT, collector on top |
| `OA1` | op-amp: + input wire from above, − input from below, output to the right |
| `INV1` `BUF1` `AND1` `NAND1` `OR1` `NOR1` `XOR1` `XNOR1` | logic gate: inputs from the wires above, to the left of and below the word, output to the right ([Logic gates](@ref)) |
| `TG1` | CMOS transmission gate: `a` left, `b` right, PMOS gate from above (bubble), NMOS gate from below |
| `[p X1/amp s]` | subcircuit instance: a box with `[` and `]` in the same columns on consecutive rows ([Subcircuit instances](@ref)) |
| `Ovgs` `O1` | open circuit with voltage marks: `+`/`−` at its ends and a label from the name (`Ovgs` → ``v_{gs}``, `O1` → none); same markers as V |
| `gnd` `vdd` `vcc` `vss` `vee` | ground and supply rails |
| other lowercase words | named terminals (open circle) |
| `@name` | node tag: italic node name, no circle |
| `"text"` `<"text"` `"text">` | caption |
| `~i1>` `<~i1` `~i1^` `~i1v` | current arrow inline in a wire |

Rules of thumb:

- A word with wires on its left and right is drawn horizontally; one with wires above
  and below is drawn vertically.
- A `-` touching a `|` joins it, and cells where three or more wires meet get a dot
  automatically, so `+` is only needed for corners.
- Columns must line up exactly. Use spaces, not tabs.
- Run op-amp input wires down to the first letter of `OA1`, and gate input wires to the
  first letters of the gate word.
- Default labels come from the names (`RD` → ``R_D``); override any of them with
  `labels`.

## Transistor stages

```@example ascii
cs = """
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
ascii_schematic(cs)
```

## Node tags

`@name` names a node without drawing a terminal. Names may contain letters, digits and
`_`, so SPICE node numbers work (`@3`).

| Placement | Result |
|---|---|
| `--@vx--` (inline in a wire) | the wire passes through; the name sits above it |
| `---@vx` / `@vx---` (at a wire end) | name beside the end of the wire |
| on the line below / above a wire | name just under / over the wire |
| in place of a `\|` in a vertical run | the wire passes through; the name sits to the right |

## Voltage marks

An `O` element is an open circuit that shows the voltage across it, as in small-signal
models. The hybrid-π MOSFET model:

```@example ascii
hybrid_pi = """
   g        +------+------d
            |      |
   Ovgs     G1     RO
            |      |
   s--------+------+------s
"""
ascii_schematic(hybrid_pi; labels=Dict("G1" => raw"$g_mv_{gs}$", "RO" => raw"$r_o$"))
```

An open circuit reaches across blank cells to the terminal or wire at each end, so `g`
and `s` become its terminals with no connecting wires (a dangling wire end reached this
way gets a terminal circle). The `+` is at the top (or left) by default; `Ovgs^` and
`<Ovgs` style markers work as for sources. Voltage marks are annotation only, and open
circuits are left out of netlists.

In CircuiTikZ the same is `to[open, v=$v_{gs}$]`, and `v=` on any other component draws
its polarity marks beside the symbol. For placed drawings use [`Voltage`](@ref).

## Current arrows

A word starting with `~` inside a horizontal or vertical wire draws a current arrow
there, so the currents branching at a node can be marked on each wire leaving it:

```@example ascii
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

The label comes from the name (`~i1` → ``i_1``, `~iD` → ``i_D``) unless `labels`
overrides it. Arrows point right or down by default; `<~i1` points left and `~i1^` up
(`~i1v`, down, is accepted after a digit, as for sources). The cell stays a wire, so
arrows don't change the netlist.

In CircuiTikZ use `i=` on any `to[…]` ([CircuiTikZ](@ref)); for placed drawings use
[`Current`](@ref).

## Logic gates

Gate words (`INV1`, `NAND2`, `NOR1`, `XOR1`, `TG1`, …) draw IEEE distinctive-shape
symbols. A gate takes up to three inputs, in this order: the wire above the word, the
wire ending at its left, and the wire below it (`INV` and `BUF` take one). The output
leaves to the right. The words are recognized before the first-letter kinds, so `NOR1`
is a gate, not an NMOS, and `INV1` is not a current source.

A crossbar decoder is a natural fit: `*` connects an address line to a row and `)`
crosses it without connecting, so editing one character rewires the decoder.

```@example ascii
decoder = """
   a1   a1n  a0   a0n
   |    |    |    |
   |    *----)----)------+
   |    |    |    |      |
   |    |    |    *------NAND0---INV0---wl0
   |    |    |    |
   |    *----)----)------+
   |    |    |    |      |
   |    |    *----)------NAND1---INV1---wl1
   |    |    |    |
   *----)----)----)------+
   |    |    |    |      |
   |    |    |    *------NAND2---INV2---wl2
   |    |    |    |
   *----)----)----)------+
   |    |    |    |      |
             *----)------NAND3---INV3---wl3
"""
ascii_schematic(decoder)
```

In a netlist every gate is a subcircuit instance of a transistor-level gate: `inv`,
`buf`, `tg`, or the kind and input count (`nand2`, `nor3`, …):

```@example ascii
print(spice_netlist(ascii_schematic(decoder)))
```

Those subcircuits are not built in; include their definitions in the netlist. To use
another one, name it in `elements` (`"NAND0" => "nand2_fast"`) or give its `.subckt`
line: when its terminals carry the gate's pin names (`in`/`out` for `INV` and `BUF`;
`a`, `b`, `c`, …, `out`; `a`, `b`, `ng`, `pg` for `TG`) the nodes follow them, and
otherwise they are taken in order, inputs top to bottom and then the output. A
transmission gate is written `a b ng pg`.

## Captions

Text in double quotes is a caption, such as a title under each stage. Nothing inside the
quotes is parsed, so it may contain dashes, letters and `$…$` math:

```@example ascii
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
the closing quote). For placed drawings use [`Caption`](@ref).
