# CircuiTikZ

Paste CircuiTikZ code into a `tikz"…"` literal and it displays as a drawing:

```@example tikz
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

The literal does no interpolation or escape processing, so code can be pasted as is.
[`tikz_schematic`](@ref)`(code; elements, nodes, style, scale, …)` is the function form;
annotations work as for ASCII drawings, and instance names come from `n=` or from the
label (`R=$R_{B1}$` is `RB1`).

## Conventions

Geometry follows CircuiTikZ, so a drawing lines up the way it does in LaTeX:

- Coordinates are cm (`scale=50` px per cm by default).
- Transistor and op-amp anchors are where CircuiTikZ puts them.
- `to[V]`/`to[cV]` put `+` at the start of the path, and `to[I]`/`to[cI]` point the
  arrow at the end; `invert` flips the symbol.
- `l=` labels sit left of the drawing direction and `l_=`/`a=` on the right.
- The op-amp − input is on top unless `noinv input up` or `yscale=-1`; `pmos`/`pnp` have
  the source/emitter on top.
- An environment's `xscale=`/`yscale=` spread the layout without resizing symbols, as in
  TikZ without `transform shape` ([Spacing and layout](@ref)).

## Voltages and currents

`v=` marks the voltage across a component (`v^=` on the other side, `v<=` reversed), and
`to[open, v=…]` across an open circuit. `i=` draws a current arrow: mid-wire on a
`short`, and on the lead after the symbol on a component. `i_=` puts the label on the
other side, `i<=` reverses the arrow (before the symbol), and `i_>=`, `i^<=`, `i>_=`,
`i<^=` and so on follow CircuiTikZ's placement rules.

```@example tikz
tikz"""
\begin{circuitikz}
  \draw (0,0) node[ocirc]{} node[left]{in} to[short, i=$i_1$, -*] (2,0)
              to[R, l=$R_1$, i=$i_2$, v=$v_1$] (5,0) node[ocirc]{} node[right]{out};
  \draw (2,0) to[R, l=$R_2$, i=$i_3$] (2,-3) node[ground]{};
\end{circuitikz}
"""
```

## Supported subset

| | |
|---|---|
| Statements | `\draw`, `\path`, `\node … at (p) {…}`, `\coordinate (A) at (p)`, inside `circuitikz` / `tikzpicture` (environment `scale=`, `xscale=`, `yscale=` honoured) or bare |
| Coordinates | `(x,y)` with optional units (cm, mm, pt, in) and simple arithmetic, `+(…)`, `++(…)`, polar `(θ:r)`, named `(A)`, anchors `(M1.D)`, `(OA.+)`, perpendicular `(A \|- B)`, `(A -\| B)` |
| Path operations | `--`, `-\|`, `\|-`, `to[…]`, `node[…](name){text}` (at the point, or mid-segment), `coordinate (name)` |
| Two-terminal | `R`, `C`, `L`, `D` (and `zD`, `sD`, `leD`, filled variants), `V`, `I`, `sV`/`sI`, `cV`, `cI`, `short`, `open`, `generic`/`fuse` (box); options `l=`, `l_=`, `a=`, `v=` (and `v^=`, `v<=`), `i=` (and `i_=`, `i<=`, `i>_=`, …), `n=`, `invert`, `*-*`/`o-`/`-o` end markers, siunitx values like `R=4.7<\kilo\ohm>` |
| Nodes | `ground` (and variants), `vcc`/`vdd`, `vee`/`vss`, `circ`, `ocirc`, `nmos`/`pmos`/`nfet`/`pfet`, `npn`/`pnp`, `op amp`, plain text nodes (`right`/`left`/`above`/`below`/`anchor=`); options `anchor=`, `xscale=-1`, `yscale=-1`, `noinv input up` |

Anything else (`circle`, `\foreach`, `calc` expressions, rotated nodes, macros, unknown
elements) produces a warning naming what was skipped: unknown two-terminal elements are
drawn as a labelled box, rotated nodes upright, and an unsupported path operation ends
that statement. Nothing is dropped silently.
