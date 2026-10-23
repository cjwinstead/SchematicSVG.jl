# ───────────────────────────── geometry ─────────────────────────────
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

"""Refers to a device pin by name, e.g. `PinRef("Q1", :C)`. Resolved at render time,
so wiring never depends on how a particular backend sizes its symbols."""
struct PinRef
    device::String
    pin::Symbol
end
const WirePt = Union{Pt,PinRef}

struct Wire <: Placed
    pts::Vector{WirePt}
end
Wire(pts::WirePt...) = Wire(collect(WirePt, pts))

"""Ground symbol hanging below `at` (or pointing up when `flip`)."""
struct Ground <: Placed
    at::Pt
    flip::Bool
end
Ground(at) = Ground(at, false)

"""Supply rail bar at `at`, label above (`up`, e.g. V_DD) or below (e.g. V_SS)."""
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

struct Dot <: Placed
    at::Pt
end

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
