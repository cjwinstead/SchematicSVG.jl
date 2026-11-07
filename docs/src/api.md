# API reference

## Drawing

```@docs
ascii_schematic
@schem_str
tikz_schematic
@tikz_str
Schematic
to_svg
layout
```

## Placed primitives

```@docs
Pt
Bipole
Transistor
SchematicSVG.Opamp
Wire
PinRef
pin
Ground
Supply
Port
NodeLabel
Dot
Voltage
Current
Caption
```

## Annotations

```@docs
annotate
si
SchematicSVG.instancename
SchematicSVG.annotation
```

## Netlists

```@docs
schematic_netlist
SchematicNetlist
NetDevice
spice_netlist
spice_subcircuit
to_microelectronics
to_subcircuit
parse_value
```
