# Netlists and simulation

Any schematic (ASCII, CircuiTikZ or placed primitives) can be netlisted:
[`spice_netlist`](@ref) gives SPICE text, [`schematic_netlist`](@ref) the devices and
nodes, and with Microelectronics.jl loaded, [`to_microelectronics`](@ref) gives its
element objects, ready to simulate.

```@example net
using SchematicSVG

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
s = ascii_schematic(amp; elements=Dict(
        "RB1" => 47e3, "RB2" => 10e3, "RC" => 4.7e3, "RE" => 1e3, "RL" => 10e3,
        "RS" => 50, "C1" => 10e-6, "C2" => 2.2e-6, "VS" => "SIN(0 10m 1k)",
        "Q1" => "Q2N3904"))
print(spice_netlist(s; title="common-emitter amplifier", supplies=Dict("vdd" => 12)))
```

## Simulating with Microelectronics.jl

With [Microelectronics.jl](https://github.com/cjwinstead/Microelectronics.jl), the same
drawing becomes element objects. Elements you supply are reused with the drawn nodes, so
their values, models, waveforms and instance parameters carry over:

```julia
using SchematicSVG, Microelectronics

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

Values may be Unitful quantities (`4.7u"kΩ"`, `10u"μF"`). The drawing shows them with
their units, and SPICE text gets plain numbers: with Microelectronics.jl loaded they are
formatted by its `qstr` (`4700`, `1e-05`), otherwise converted to SI units by a small
Unitful extension (`4700`, `1.0e-5`). Units never reach the netlist.

## How a drawing becomes a circuit

**Connectivity** comes from the geometry: wire ends, pins and markers at the same point
are one node, and a point lying on a wire (a T-junction) joins it. Wires that only cross
(`)` in ASCII, or two CircuiTikZ wires crossing mid-segment) stay separate.

**Node names**: ground symbols are `0`; supply symbols name their node (`vdd`, `vcc`,
`vss`…; several symbols with the same name are one node); terminals and `@` tags name
theirs (`vin`, `vo`); the rest are `n1`, `n2`, …. Two names on one wire give a warning,
and separate nets with the same name are the same SPICE node.

**Values** for each instance (matched case-insensitively, by drawn name or SPICE name, so
`N1` matches Microelectronics' `MN1`) come from, in order:

1. `elements` passed to `to_microelectronics` / `schematic_netlist` / `spice_netlist`;
2. the elements the schematic was annotated with (`ascii_schematic(…; elements)`,
   `annotate`), kept with the schematic;
3. the drawing's text: notes and `l=`/`a=` labels such as `4.7 kΩ`, `10<\micro F>`,
   `R_1 = 1k`, or a model name. Prefixes are SI (`M` is mega; `meg` also works).

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
`ideal_opamp`. Supplies need a voltage: `supplies=Dict("vdd" => 5)` adds a DC source for
each. Dangling pins, unknown elements (drawn as boxes) and nodes with two names produce
warnings; a dependent source without its control is an error.

## Nodes SPICE can't solve

Nodes with no DC path to ground give a warning, because SPICE can't find an operating
point for them. This is usually an output or input reached only through a coupling
capacitor (or a current source), and the warning names the node and suggests the fix: a
load resistor between that node and ground, or a bias resistor when the node drives a
MOSFET gate or an op-amp input. For example, `+---C2---vo` with nothing else at `vo`
gives

```
node vo has no DC path to ground, so SPICE can't find the operating point (it connects
only through capacitors, current sources or high-impedance inputs). Add a load resistor
between vo and ground.
```

A schematic with no ground symbol at all gets its own warning.

## Subcircuits

[`spice_subcircuit`](@ref) gives the `.subckt … .ends` text for a drawing, and
[`to_subcircuit`](@ref) a Microelectronics `Subcircuit`.

```@example net
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
vals = Dict("RD" => 20e3, "RG" => 1e6, "RL" => 1e5, "CC1" => 1e-5, "CC2" => 1e-5,
            "CB" => 1e-4, "I1" => 1e-4, "N1" => (model="ald1105n", W=20e-6, L=10e-6))
print(spice_subcircuit(ascii_schematic(cs; elements=vals); name="cs_nmos",
                       rename=Dict("vdd" => "vdd!", "vss" => "vss!")))
```

The terminals come from the drawing: every named node with a terminal circle (`in`,
`out` in an ASCII drawing; an `ocirc` with a text label in CircuiTikZ), ordered left to
right and then top to bottom. A terminal drawn twice counts once, and `@` node tags,
grounds and supplies are not terminals. Pass `terminals=["inp", "inn", "outp", "outn"]`
to pick the terminals or their order (the pin order of the subcircuit), and
`schematic_netlist(s).terminals` shows the ones a drawing gives.

Terminals and supply nodes are connected outside, so they don't trigger the DC-path or
supply warnings. `rename` maps drawn names to netlist names, e.g.
`Dict("vdd" => "vdd!", "vss" => "vss!")` for global supplies (declare them in the
enclosing netlist with `.global vdd! vss!`). The same `rename` and `external` keywords
work on `schematic_netlist`. The repository's `examples/mos_amplifiers.ipynb` builds
common-source, source-follower, common-gate and differential-pair subcircuits this way,
and a two-stage amplifier with [`layout`](@ref).
