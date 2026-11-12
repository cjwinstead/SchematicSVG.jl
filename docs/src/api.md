# API reference

## Drawing functions

```@docs
SchematicSVG
ascii_schematic
@schem_str
tikz_schematic
@tikz_str
Schematic
to_svg
layout
```

## Primitive types

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

## Annotation functions

```@docs
annotate
label_nodes
si
SchematicSVG.instancename
SchematicSVG.annotation
```

## Netlist functions

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
