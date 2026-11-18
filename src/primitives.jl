# ───────────────────────────── geometry ─────────────────────────────
"""
    Pt(x, y)

A point in circuit units, with y pointing up (as in CircuiTikZ; the SVG output flips
it). Points support `+`, `-` and scaling by a number, so `Pt(1, 2) + 0.5 * Pt(2, 0)`
is `Pt(2, 2)`.
"""
struct Pt
    x::Float64
    y::Float64
end
Pt(x::Real, y::Real) = Pt(Float64(x), Float64(y))
Base.:+(a::Pt, b::Pt) = Pt(a.x + b.x, a.y + b.y)
Base.:-(a::Pt, b::Pt) = Pt(a.x - b.x, a.y - b.y)
Base.:*(s::Real, a::Pt) = Pt(s * a.x, s * a.y)
# Numeric equality, so Pt(1, -0.0) == Pt(1, 0.0) (the ASCII grid produces -0.0 on row 1).
Base.:(==)(a::Pt, b::Pt) = a.x == b.x && a.y == b.y
Base.hash(p::Pt, h::UInt) = hash(p.y + 0.0, hash(p.x + 0.0, hash(:Pt, h)))

# ─────────────────────────── placed primitives ──────────────────────
abstract type Placed end

const TPIN = 0.5      # default transistor pin offset (ASCII drawings)

"""
    Bipole(kind, a, b, label=""; name="", note="", side=:auto)

Two-terminal element drawn along the segment a→b (like CircuiTikZ `to[...]`).
`kind` ∈ :R, :C, :L, :D, :V, :I, :cV, :cI, :sV (sinusoidal), :box, :open, :short.
For sources `a` is the SPICE n+ terminal ('+' drawn near a; current arrow a→b).
`name` is the instance name used to match annotations; `note` is a second line of text
(value or model). `side` places the label: `:auto` (above horizontal parts, right of
vertical ones, note stacked/opposite), or `:left`/`:right` of the a→b direction like
CircuiTikZ `l=`/`l_=`, with the note on the other side.
"""
struct Bipole <: Placed
    kind::Symbol
    a::Pt
    b::Pt
    label::String
    name::String
    note::String
    side::Symbol
end
Bipole(kind, a, b, label=""; name="", note="", side=:auto) = Bipole(kind, a, b, label, name, note, side)

"""
    Transistor(kind, name, at; xflip=false, yflip=false, label=name, note="", w=0.5, h=0.5)

Three-terminal device centred at `at`. `kind` ∈ :npn, :pnp, :nmos, :pmos.
`xflip` mirrors left/right (control pin on the right); `yflip` swaps top/bottom.
`w` is the distance from the centre to the gate/base pin and `h` to the top/bottom pins
(circuit units); CircuiTikZ imports use its own dimensions.
"""
struct Transistor <: Placed
    kind::Symbol
    name::String
    at::Pt
    xflip::Bool
    yflip::Bool
    label::String
    note::String
    w::Float64
    h::Float64
end
Transistor(kind, name, at; xflip=false, yflip=false, label=name, note="", w=TPIN, h=TPIN) =
    Transistor(kind, name, at, xflip, yflip, label, note, w, h)

"""
    Opamp(name, at; label="", note="", w=0.5, h=0.2, inv_up=false)

Op-amp centred at `at`: inputs on the left at ±`h`, output on the right, pins `w` from
the centre. The + input is on top unless `inv_up` (the CircuiTikZ default).
Pins `:inp`, `:inn`, `:out` (usable in `PinRef`).
"""
struct Opamp <: Placed
    name::String
    at::Pt
    label::String
    note::String
    w::Float64
    h::Float64
    inv_up::Bool
end
Opamp(name, at; label="", note="", w=0.5, h=0.2, inv_up=false) =
    Opamp(name, at, label, note, w, h, inv_up)

"""
    BlockPin(name, at, side)

A terminal of a [`Block`](@ref): its `name` (shown inside the box; it matches the
subcircuit's terminal names), its point `at` on the box edge, and the `side` it is on
(`:left`, `:right`, `:top` or `:bottom`).
"""
struct BlockPin
    name::String
    at::Pt
    side::Symbol
end

"""
    Block(name, lo, hi, pins; label=name, note="")
    Block(name, at; left=[], right=[], width=2, pitch=0.8, model="", label=name)

A subcircuit instance: a box from corner `lo` (bottom left) to `hi` (top right) with
terminals `pins` (a vector of [`BlockPin`](@ref)) on its edges. `name` is the instance
name (`X1`); `label` is shown in the box with `note` (the subcircuit's name) under it.

The second form builds the box around centre `at` from pin names: `left` and `right`
top to bottom, `pitch` apart, on a box `width` wide, with `model` as the note. Pins are
`PinRef`-able by name: `PinRef("X1", :out)`.

In a netlist the block is an `X` line. Its nodes follow the subcircuit's terminal order
when that is known (see [`schematic_netlist`](@ref)), and otherwise the drawing: left
pins top to bottom, then right pins top to bottom.
"""
struct Block <: Placed
    name::String
    lo::Pt
    hi::Pt
    pins::Vector{BlockPin}
    label::String
    note::String
end
Block(name, lo::Pt, hi::Pt, pins; label=name, note="") =
    Block(name, lo, hi, collect(BlockPin, pins), label, note)
function Block(name, at::Pt; left=String[], right=String[], width=2, pitch=0.8, model="", label=name)
    n = max(length(left), length(right), 1)
    h = n * pitch
    top = at.y + h / 2
    y(i) = at.y + ((n + 1) / 2 - i) * pitch          # from the centre: symmetric, exact
    pins = [[BlockPin(string(p), Pt(at.x - width / 2, y(i)), :left) for (i, p) in enumerate(left)];
            [BlockPin(string(p), Pt(at.x + width / 2, y(i)), :right) for (i, p) in enumerate(right)]]
    Block(name, Pt(at.x - width / 2, at.y - h / 2), Pt(at.x + width / 2, top), pins; label, note=model)
end

"""
    Gate(kind, name, at; n=2, label="", note="", w=0.5, pitch=…)

A logic gate drawn with its IEEE (distinctive-shape) symbol, centred at `at`. `kind` is
`:inv`, `:buf`, `:and`, `:nand`, `:or`, `:nor`, `:xor`, `:xnor` or `:tg` (a CMOS
transmission gate). Inverting gates get an output bubble.

Pins (usable in `PinRef`), in netlist order:
- `:inv`/`:buf`: `:in` at `at - (w, 0)`, `:out` at `at + (w, 0)`;
- the others: `n` inputs `:a`, `:b`, `:c`, … on the left, top to bottom, `pitch` apart
  (0.4 for two inputs, 0.3 for more), then `:out`;
- `:tg`: `:a` on the left, `:b` on the right, `:ng` (the NMOS gate) below and `:pg` (the
  PMOS gate, drawn with a bubble) above, 0.4 from the centre.

In a netlist a gate is a subcircuit instance (an `X` line) of a transistor-level gate:
`inv`, `buf`, `tg` or the kind and input count (`nand2`, `nor3`, …) unless `elements`
names another subcircuit. Those subcircuits are not built in: define them in the
netlist (`.subckt nand2 a b out` …).
"""
struct Gate <: Placed
    kind::Symbol
    name::String
    at::Pt
    n::Int
    label::String
    note::String
    w::Float64
    pitch::Float64
end
const GATE_KINDS = (:inv, :buf, :and, :nand, :or, :nor, :xor, :xnor, :tg)
function Gate(kind::Symbol, name, at::Pt; n::Integer=kind in (:inv, :buf) ? 1 : 2, label="",
              note="", w=0.5, pitch=n <= 2 ? 0.4 : 0.3)
    kind in GATE_KINDS || throw(ArgumentError("unknown gate kind :$kind (one of $(join(GATE_KINDS, ", ")))"))
    kind in (:inv, :buf, :tg) && (n = 1)
    n >= 1 || throw(ArgumentError("a gate needs at least one input"))
    Gate(kind, String(name), at, Int(n), String(label), String(note), Float64(w), Float64(pitch))
end

"Gates whose output is inverted (drawn with a bubble)."
isinverting(g::Gate) = g.kind in (:inv, :nand, :nor, :xnor)

# Half-height of the gate body, in circuit units.
gatehalf(g::Gate) = g.kind in (:inv, :buf) ? 0.3 : g.kind == :tg ? 0.35 :
                    max(0.4, (g.n - 1) * g.pitch / 2 + 0.15)

"Pin names of a gate, in netlist (terminal) order."
function gatepinnames(g::Gate)
    g.kind in (:inv, :buf) && return ["in", "out"]
    g.kind == :tg && return ["a", "b", "ng", "pg"]
    [[string(Char('a' + i - 1)) for i in 1:g.n]; "out"]
end

# Parts with pins that PinRef can name, and every part that is a device in a netlist.
const PinDevice = Union{Transistor,Opamp,Block,Gate}
const Device = Union{Bipole,Transistor,Opamp,Block,Gate}

"""
    PinRef(device, pin)

A pin of a named transistor or op-amp, used as a `Wire` point: `PinRef("Q1", :C)`,
`PinRef("M1", :G)`, `PinRef("A1", :out)`. It is resolved when the schematic is drawn or
netlisted, so wires follow the device wherever it sits. Transistor pins are `:B/:G`,
`:C/:D` and `:E/:S`; op-amp pins `:inp`, `:inn` and `:out`; a `Block`'s pins go by their
names; a `Gate`'s are `:a`, `:b`, … and `:out` (`:in`/`:out`; `:a`, `:b`, `:ng`, `:pg`
for a transmission gate).
"""
struct PinRef
    device::String
    pin::Symbol
end
const WirePt = Union{Pt,PinRef}

"""
    Wire(points...)

A polyline through `points`, each a `Pt` or a `PinRef`. Wire ends and corners that
meet other wires, pins or symbols connect to them, as does a point lying on another
wire (a T-junction); wires that only cross stay separate. Junction dots are not added
automatically for placed drawings: add a `Dot`.
"""
struct Wire <: Placed
    pts::Vector{WirePt}
end
Wire(pts::WirePt...) = Wire(collect(WirePt, pts))

"""
    Ground(at, flip=false)

Ground symbol hanging below `at` (pointing up when `flip`). Every ground is node `0` in
netlists.
"""
struct Ground <: Placed
    at::Pt
    flip::Bool
end
Ground(at) = Ground(at, false)

"""
    Supply(at, label, up)

Supply rail: a bar at `at` with `label` above it (`up=true`, e.g. `"V_{DD}"`) or below
it (`up=false`, e.g. `"V_{SS}"`). The label names the supply node in netlists (`V_{DD}`
→ `vdd`), and supplies with the same name are one node.
"""
struct Supply <: Placed
    at::Pt
    label::String
    up::Bool
end

"""
    Port(at, label, side; name=label)

Open-circle terminal. `side` ∈ :left, :right, :above, :below says where the text goes.
`name` is the node name used to match node annotations.
"""
struct Port <: Placed
    at::Pt
    name::String
    label::String
    side::Symbol
end
Port(at, label, side; name=label) = Port(at, name, label, side)

"""
    NodeLabel(at, name, side; label=name)

Names a node without drawing a terminal: italic text beside the wire point `at`.
`side` ∈ :left, :right, :above, :below.
"""
struct NodeLabel <: Placed
    at::Pt
    name::String
    label::String
    side::Symbol
end
NodeLabel(at, name, side; label=name) = NodeLabel(at, name, label, side)

"""
    Dot(at)

Junction dot at `at`. Purely visual: points connect whether or not a dot is drawn.
"""
struct Dot <: Placed
    at::Pt
end

"""
    Voltage(plus, minus, label=""; side=:right, kind=:open)

Voltage polarity marks, like CircuiTikZ `v=`: `+` at the `plus` end, `−` at the `minus`
end, and `label` between them. For an open circuit (`kind=:open`) the signs sit on the
line near its two ends; for a component (`kind=:R`, `:C`, …, the kind of the `Bipole`
drawn between the same points) they flank its symbol. `side` is `:right` or `:left` of
the plus → minus direction, or `:auto` (above horizontal parts, right of vertical ones).
Voltage marks are annotation only: they don't affect the netlist.
"""
struct Voltage <: Placed
    plus::Pt
    minus::Pt
    label::String
    side::Symbol
    kind::Symbol
end
Voltage(plus, minus, label=""; side=:right, kind=:open) = Voltage(plus, minus, label, side, kind)

"""
    Current(a, b, label=""; side=:auto, into=false, pos=0.5, kind=:short)

Current arrow on the wire from `a` toward `b`, like CircuiTikZ `i=`: it points at `b`
(back at `a` when `into`), with `label` beside it. To mark the currents branching at a
node, give each branch its own arrow with `a` at the node: `Current(node, p, "i_1")` is
a current leaving the node and `into=true` one entering it. `pos` is the arrow's place
as a fraction of a → b. When a `Bipole` of kind `kind` (`:R`, `:C`, …) is drawn between
the same points the arrow goes on one of its leads instead: the end lead when `pos ≥ 0.5`,
the start lead otherwise. `side` is `:left` or `:right` of the a → b direction, or `:auto`
(above horizontal wires, right of vertical ones). Current arrows are annotation only:
they don't affect the netlist.
"""
struct Current <: Placed
    a::Pt
    b::Pt
    label::String
    side::Symbol
    into::Bool
    pos::Float64
    kind::Symbol
end
Current(a, b, label=""; side=:auto, into=false, pos=0.5, kind=:short) =
    Current(a, b, label, side, into, pos, kind)

"""
    Caption(at, text; align=:center)

Free text, such as a title under part of a drawing, centred on `at` (or starting / ending
there with `align=:left` / `:right`). Plain text is shown as written; text with `\$…\$`
uses the same LaTeX subset as labels.
"""
struct Caption <: Placed
    at::Pt
    text::String
    align::Symbol
end
Caption(at, text; align=:center) = Caption(at, text, align)

"""
    pin(device, p) -> Pt

Position of pin `p` of a `Transistor` (`:B`/`:G` control, `:C`/`:D` top, `:E`/`:S`
bottom, after any flips) or an op-amp (`:inp`, `:inn`, `:out`), in circuit units.
"""
function pin(t::Transistor, p::Symbol)
    sx = t.xflip ? -1 : 1
    sy = t.yflip ? -1 : 1
    off = p in (:B, :G) ? Pt(-t.w * sx, 0) :
          p in (:C, :D) ? Pt(0, t.h * sy) :
          p in (:E, :S) ? Pt(0, -t.h * sy) :
          error("unknown pin $p")
    t.at + off
end

function pin(o::Opamp, p::Symbol)
    s = o.inv_up ? -1 : 1
    p == :inp ? o.at + Pt(-o.w, s * o.h) :
    p == :inn ? o.at + Pt(-o.w, -s * o.h) :
    p == :out ? o.at + Pt(o.w, 0) : error("unknown pin $p")
end

function pin(g::Gate, p::Union{Symbol,AbstractString})
    q = lowercase(string(p))
    if g.kind == :tg
        q == "a" && return g.at - Pt(g.w, 0)
        q == "b" && return g.at + Pt(g.w, 0)
        q == "pg" && return g.at + Pt(0, 0.4)
        q == "ng" && return g.at - Pt(0, 0.4)
    else
        q == "out" && return g.at + Pt(g.w, 0)
        names = gatepinnames(g)
        i = findfirst(==(q), names)
        if i !== nothing && i <= g.n
            return g.at + Pt(-g.w, ((g.n + 1) / 2 - i) * g.pitch)
        end
    end
    error("gate $(g.name) has no pin $p (pins: $(join(gatepinnames(g), ", ")))")
end

function pin(b::Block, p::Union{Symbol,AbstractString})
    i = findfirst(q -> lowercase(q.name) == lowercase(string(p)), b.pins)
    i === nothing && error("$(b.name) has no pin $p (pins: $(join((q.name for q in b.pins), ", ")))")
    b.pins[i].at
end
