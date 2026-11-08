# Changelog

All notable changes to SchematicSVG.jl. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) (before 1.0, minor versions may change
behaviour).

## Unreleased

Changes since v0.7.2.

### Added

- **`layout`** combines drawings (ASCII strings or `Schematic`s) in a row or a column.
  Parts join at their terminals with a drawn wire (`connect`) or by name (`share`);
  element and node names used in more than one part get the part number, and supplies
  and ground stay common. `[s1 s2]` and `[s1; s2]` lay out `Schematic`s.
- **Voltage marks**: `+`, `−` and a label across a component or an open circuit. ASCII
  `O` elements (`Ovgs`) reach across blank cells to the terminals or wires at each end;
  CircuiTikZ `v=`, `v^=`, `v<=` and `to[open, v=…]`; the `Voltage` primitive.
- **Current arrows**: ASCII `~i1>`, `<~i1`, `~i1^`, `~i1v` inside a wire; CircuiTikZ `i=`
  and its variants (`i_=`, `i<=`, `i>_=`, …) placed as CircuiTikZ places them; the
  `Current` primitive.
- **Captions**: ASCII `"text"`, `<"text"` and `"text">`; the `Caption` primitive.
- **`xscale` / `yscale`** spread or tighten a drawing without resizing symbols or text,
  as keywords of `ascii_schematic`, `tikz_schematic` and `Schematic`, and from a
  CircuiTikZ environment's own `xscale=`/`yscale=`. `Schematic(s; kw...)` copies a
  drawing with new settings.
- **Border**: a thick gray frame with rounded corners around every figure, so a drawing
  that runs past the edge of a notebook window is easy to spot (`border=false` turns it
  off).
- **Inferred subcircuit terminals**: `to_subcircuit` and `spice_subcircuit` use the drawn
  terminals (named terminal circles, left to right) when `terminals` isn't given.
  `SchematicNetlist` has a new `terminals` field, and `:terminals` in `external` stands
  for them.
- Documentation site (Documenter.jl), this changelog, and GitHub Actions for tests and
  documentation.

### Changed

- When `xscale`/`yscale` squeeze a drawing, transistor and op-amp leads shorten without
  running into the symbol: a PMOS gate wire stops outside the bubble, and an op-amp keeps
  its inputs in place and slides right. Two-terminal symbols (resistors, capacitors,
  sources, …) whose ends are closer than the symbol is long, because of a small `scale`,
  `xscale` or `yscale`, shrink to fit with a short lead at each end.
- The examples notebook's amplifier subcircuits use inferred terminals (except the
  differential pair, which keeps its explicit order), and it adds a two-stage CS + SF
  amplifier built with `layout`.

### Fixed

- SPICE text no longer contains Unitful's unit strings (such as `4.7 kΩ`), which SPICE
  can't read: quantities are written as plain numbers, by Microelectronics' `qstr` when
  it is loaded and otherwise by a small Unitful extension.
- On Julia 1.13, some values gained rounding noise in SPICE text (`1e-12` became
  `1.0000000000000002e-12`); numbers are now written in their shortest form.
- Tests that used the unexported `Opamp` now use `SchematicSVG.Opamp`.
- Loading the Microelectronics extension could fail with
  ``UndefVarError: `SchematicSVGMicroelectronicsExt` not defined in `Main` ``, depending
  on how it was loaded; the extension modules no longer carry docstrings.
